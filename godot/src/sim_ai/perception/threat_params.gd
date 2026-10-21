class_name ThreatParams extends RefCounted
## Static tables of the perception layer (05 s7.4; AI-22), built once from the content and the `threat` block, shared
## read-only by every `Perception` / `ThreatMap` of a session. Four parts:
##   per def id     Ore value (`cost_ore`), sensor and deck-reveal radius, threat profile (0 = harmless);
##   per profile    sustained DPS on the channels AIR_DECK, AIR_LOW, AIR_HIGH, GROUND and the own-defence sum;
##                  towers by envelope (`towers.json` h_rel / target_agl_min / target_kinds at the band AGLs), the
##                  `fighters` at `fighter_share` of their primary gun over `fighter_radius_m`, the
##                  `ground_attackers` on GROUND (ships over `fighter_radius_m`, ground units over their weapon range);
##   cell geometry  the 384 interest cells (ADR-05): centre direction, inscribed-cap cosine (a point inside it is in
##                  the cell: the cell-hint shortcut), a gap-sorted near list (cells whose points can lie within
##                  `near_reach_m` of the cell's points);
##   rings          per profile p and source cell c the cells h with weight w > 0 (`ring_*`): the 05 rule "dps x
##                  falloff to cells whose centre is within range + `cell_margin_m`", binned per interest cell and
##                  taken at the nearest point of the source cell: d = max(D(c, h) - circ(c), 0) with D the great-circle
##                  distance of the centres, w = 1 for d <= range, linear to 0 at range + margin. Sensor rings (index
##                  NP + k for sensor class k): the source cell and every cell with D <= the sensor radius.
## Built at session setup (allocates); queries allocate nothing.

const N: int = Sphere.GRID_INTEREST
const CELLS: int = 6 * N * N
const AIR_DECK: int = 0
const AIR_LOW: int = 1
const AIR_HIGH: int = 2
const GROUND: int = 3
const BANDS: int = 4                       ## channels a profile carries (the three air bands + GROUND)
const KEYS: PackedStringArray = ["ghost_half_life_s", "cell_margin_m", "fighter_share", "fighter_radius_m",
	"route_sample_m", "band_agl_m", "defence_floor_dps", "fighters", "ground_attackers"]

var decay_per_tick: float = 0.0            ## ln 2 / (ghost_half_life_s in ticks): a ghost weighs exp(-age x this)
var margin_m: float = 0.0                  ## cell_margin_m (05: 590 m)
var route_step_m: float = 0.0              ## route_sample_m (05: 500 m)
var defence_floor: float = 0.0             ## defence_floor_dps: the hottest-cell ratio's denominator floor
var value_by_def: PackedFloat32Array = PackedFloat32Array()   ## by def id: Ore value
var sensor_by_def: PackedFloat32Array = PackedFloat32Array()  ## by def id: sensor_radius (0 = none)
var reveal_by_def: PackedFloat32Array = PackedFloat32Array()  ## by def id: deck_reveal_radius (0 = none)
var profile_by_def: PackedByteArray = PackedByteArray()       ## by def id: threat profile, 0 = none
var sclass_by_def: PackedByteArray = PackedByteArray()        ## by def id: sensor class, 0 = none
var profiles: int = 1                      ## NP: profile 0 (none) + one per armed def
var classes: int = 1                       ## NC: range class 0 (none) + one per distinct profile range (ring k = class k)
var prof_class: PackedByteArray = PackedByteArray([0])        ## [p] range class of profile p's air bands (0: none)
var prof_gclass: PackedByteArray = PackedByteArray([0])       ## [p] range class of profile p's GROUND channel (0: none)
var class_range: PackedFloat32Array = PackedFloat32Array([0.0])   ## [k] range of class k (m)
var prof_dps: PackedFloat32Array = PackedFloat32Array()       ## [p * BANDS + channel]
var prof_defence: PackedFloat32Array = PackedFloat32Array()   ## [p]: max air band + GROUND (own_defence)
var max_sensor_m: float = 0.0
var centre: PackedVector3Array = PackedVector3Array()         ## [cell] unit centre direction
var circ_m: PackedFloat32Array = PackedFloat32Array()         ## [cell] circumradius on the datum (m)
var in_cos: PackedFloat32Array = PackedFloat32Array()         ## [cell] cosine of the inscribed cap (with margin)
var near_start: PackedInt32Array = PackedInt32Array()         ## [cell .. cell + 1] into near_cell / near_gap
var near_cell: PackedInt32Array = PackedInt32Array()
var near_gap: PackedFloat32Array = PackedFloat32Array()       ## ascending per cell (m)
var ring_start: PackedInt32Array = PackedInt32Array()         ## [ring * (CELLS + 1) + cell] into ring_cell / ring_w
var ring_cell: PackedInt32Array = PackedInt32Array()
var ring_w: PackedFloat32Array = PackedFloat32Array()

static var _g_centre: PackedVector3Array = PackedVector3Array()
static var _g_circ: PackedFloat32Array = PackedFloat32Array()
static var _g_in_cos: PackedFloat32Array = PackedFloat32Array()
static var _g_near_reach: float = -1.0
static var _g_near_start: PackedInt32Array = PackedInt32Array()
static var _g_near_cell: PackedInt32Array = PackedInt32Array()
static var _g_near_gap: PackedFloat32Array = PackedFloat32Array()


## Null on a missing key of `threat` (KEYS). `tick_hz` converts the half-life.
static func from_content(c: ContentSet, threat: Dictionary, tick_hz: int) -> ThreatParams:
	for k: String in KEYS:
		if not threat.has(k):
			return null
	var bands: Array = threat["band_agl_m"]
	if bands.size() != 3:
		return null
	var p: ThreatParams = ThreatParams.new()
	p.decay_per_tick = log(2.0) / maxf(TargetParams.num(threat, "ghost_half_life_s", 0.0) * float(tick_hz), 1.0)
	p.margin_m = TargetParams.num(threat, "cell_margin_m", 0.0)
	p.route_step_m = TargetParams.num(threat, "route_sample_m", 0.0)
	p.defence_floor = TargetParams.num(threat, "defence_floor_dps", 0.0)
	_geometry()
	p.centre = _g_centre
	p.circ_m = _g_circ
	p.in_cos = _g_in_cos
	var granges: PackedFloat32Array = PackedFloat32Array([0.0])
	var ranges: PackedFloat32Array = p._defs(c, threat, bands, granges)
	var reach: float = p.max_sensor_m
	for r: float in granges:
		reach = maxf(reach, r + p.margin_m)
	for r: float in ranges:
		reach = maxf(reach, r + p.margin_m)
	_near(reach)
	p.near_start = _g_near_start
	p.near_cell = _g_near_cell
	p.near_gap = _g_near_gap
	p._rings(p._classes(ranges, granges), p._sensor_radii())
	return p


## Sustained DPS of a weapon (mean damage x shots per second): bursts `burst / (burst / rof + burst_interval_s)`,
## else `rof`, else `salvo / reload_s`; 0 for a null weapon.
static func sustained_dps(w: WeaponDef) -> float:
	if w == null:
		return 0.0
	var per_s: float = 0.0
	if w.rof > 0.0:
		per_s = w.rof
		if w.burst > 0 and w.burst_interval_s > 0.0:
			per_s = float(w.burst) / (float(w.burst) / w.rof + w.burst_interval_s)
	elif w.salvo > 0 and w.reload_s > 0.0:
		per_s = float(w.salvo) / w.reload_s
	return 0.5 * float(w.damage_min + w.damage_max) * per_s


## The interest cell of `p`; `hint` (a previous cell or -1) is returned without the cube mapping when `p` lies inside
## its inscribed cap (so the answer always equals `Sphere.cell_of`).
func cell_of(p: Vector3, hint: int) -> int:
	if hint >= 0 and p.normalized().dot(centre[hint]) >= in_cos[hint]:
		return hint
	return Sphere.cell_of(p, N)


## Number of rings (range classes + sensor classes).
func ring_count() -> int:
	return MathX.floori_div(ring_start.size(), CELLS + 1)


# Per-def tables and profiles; returns the air range of every profile (index p), the GROUND range into `granges`.
func _defs(c: ContentSet, threat: Dictionary, bands: Array, granges: PackedFloat32Array) -> PackedFloat32Array:
	var e: int = value_by_def.resize(DefRanges.END) | sensor_by_def.resize(DefRanges.END)
	e |= reveal_by_def.resize(DefRanges.END) | profile_by_def.resize(DefRanges.END) | sclass_by_def.resize(DefRanges.END)
	assert(e == OK)
	value_by_def.fill(0.0)
	sensor_by_def.fill(0.0)
	reveal_by_def.fill(0.0)
	profile_by_def.fill(0)
	sclass_by_def.fill(0)
	var ranges: PackedFloat32Array = PackedFloat32Array([0.0])
	prof_dps = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	prof_defence = PackedFloat32Array([0.0])
	var share: float = TargetParams.num(threat, "fighter_share", 0.0)
	var fr: float = TargetParams.num(threat, "fighter_radius_m", 0.0)
	var fighters: Array = threat["fighters"]
	var attackers: Array = threat["ground_attackers"]
	for sh: ShipDef in c.ships:
		var w: WeaponDef = _weapon(c, sh.primary_weapon)
		var air: float = share * sustained_dps(w) if fighters.has(str(sh.id)) else 0.0
		var gnd: float = sustained_dps(w) * (w.ground_mult if w != null else 0.0) if attackers.has(str(sh.id)) else 0.0
		_def(c, sh.id, float(sh.cost_ore), sh.sensor_radius, 0.0, PackedFloat32Array([air, air, air, gnd]), fr,
			w.range_m if w != null else 0.0, ranges, granges)
	for gd: GroundUnitDef in c.ground_units:
		var w: WeaponDef = _weapon(c, gd.weapon)
		var gnd: float = sustained_dps(w) * w.ground_mult if w != null and attackers.has(str(gd.id)) else 0.0
		var gr: float = w.range_m if w != null else 0.0
		_def(c, gd.id, float(gd.cost_ore), gd.sensor_radius, 0.0, PackedFloat32Array([0.0, 0.0, 0.0, gnd]), gr, gr,
			ranges, granges)
	for sd: StructureDef in c.structures:
		var dps: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		var rng: float = 0.0
		if sd.is_tower():
			var w: WeaponDef = _weapon(c, StringName(str(sd.tower.get("weapon", ""))))
			rng = w.range_m if w != null else 0.0
			_tower(sd.tower, sustained_dps(w), w.ground_mult if w != null else 0.0, bands, dps)
		_def(c, sd.id, float(sd.cost_ore), sd.sensor_radius, sd.deck_reveal_radius, dps, rng, rng, ranges, granges)
	return ranges


# One def's row; an armed def (a channel > 0 with its range > 0) gets the next profile.
func _def(c: ContentSet, name: StringName, value: float, sensor: float, reveal: float, dps: PackedFloat32Array,
		rng: float, grng: float, ranges: PackedFloat32Array, granges: PackedFloat32Array) -> void:
	var d: int = c.entity_index.get(name, -1)
	if d < 0 or d >= DefRanges.END:
		return
	value_by_def[d] = value
	sensor_by_def[d] = sensor
	reveal_by_def[d] = reveal
	max_sensor_m = maxf(max_sensor_m, maxf(sensor, reveal))
	if rng <= 0.0:
		dps[0] = 0.0
		dps[1] = 0.0
		dps[2] = 0.0
	if grng <= 0.0:
		dps[3] = 0.0
	if dps[0] + dps[1] + dps[2] + dps[3] <= 0.0:
		return
	profile_by_def[d] = profiles
	profiles += 1
	prof_dps.append_array(dps)
	var _a: bool = prof_defence.push_back(maxf(dps[0], maxf(dps[1], dps[2])) + dps[3])
	var _b: bool = ranges.push_back(rng if dps[0] + dps[1] + dps[2] > 0.0 else 0.0)
	var _g: bool = granges.push_back(grng if dps[3] > 0.0 else 0.0)


# 05 s7.4 tower envelope: a ship band counts when its AGL is inside [h_rel_min, h_rel_max] and >= target_agl_min.
static func _tower(t: Dictionary, dps: float, ground_mult: float, bands: Array, out: PackedFloat32Array) -> void:
	var kinds: Array = t.get("target_kinds", [])
	if kinds.has("ship"):
		var lo: float = TargetParams.num(t, "h_rel_min", 0.0)
		var hi: float = TargetParams.num(t, "h_rel_max", 0.0)
		var agl_min: float = TargetParams.num(t, "target_agl_min", 0.0)
		for b: int in 3:
			var h: float = TargetParams.as_num(bands[b], 0.0)
			if h >= lo and h <= hi and h >= agl_min:
				out[b] = dps
	if kinds.has("ground"):
		out[GROUND] = dps * ground_mult


static func _weapon(c: ContentSet, id: StringName) -> WeaponDef:
	if id == &"":
		return null
	for w: WeaponDef in c.weapons:
		if w.id == id:
			return w
	return null


# Distinct sensor radii -> sensor classes 1..K (ascending); fills sclass_by_def; returns [0, r_1, .., r_K].
func _sensor_radii() -> PackedFloat32Array:
	var radii: PackedFloat32Array = PackedFloat32Array()
	for d: int in DefRanges.END:
		if sensor_by_def[d] > 0.0 and not radii.has(sensor_by_def[d]):
			var _a: bool = radii.push_back(sensor_by_def[d])
	radii.sort()
	for d: int in DefRanges.END:
		if sensor_by_def[d] > 0.0:
			sclass_by_def[d] = radii.find(sensor_by_def[d]) + 1
	var out: PackedFloat32Array = PackedFloat32Array([0.0])
	out.append_array(radii)
	return out


# Gap-sorted near list per cell (gap = a lower bound of the distance between points of the two cells) covering at
# least `reach` m; shared per process (rebuilt only for a larger reach).
static func _near(reach: float) -> void:
	if reach <= _g_near_reach:
		return
	var start: PackedInt32Array = PackedInt32Array([0])
	var cells: PackedInt32Array = PackedInt32Array()
	var gaps: PackedFloat32Array = PackedFloat32Array()
	for c: int in CELLS:
		var keys: PackedInt64Array = PackedInt64Array()
		for h: int in CELLS:
			var gap: float = maxf(0.0, _g_centre[c].angle_to(_g_centre[h]) * Sphere.PLANET_RADIUS - _g_circ[c] - _g_circ[h])
			if gap <= reach:
				var _k: bool = keys.push_back(int(gap) * CELLS + h)
		keys.sort()
		for key: int in keys:
			var _c: bool = cells.push_back(key % CELLS)
			var _g: bool = gaps.push_back(float(MathX.floori_div(key, CELLS)))
		var _s: bool = start.push_back(cells.size())
	_g_near_reach = reach
	_g_near_start = start
	_g_near_cell = cells
	_g_near_gap = gaps


# Distinct non-zero profile ranges, air and GROUND (ascending) -> range classes 1..; fills prof_class / prof_gclass /
# class_range; returns class_range.
func _classes(ranges: PackedFloat32Array, granges: PackedFloat32Array) -> PackedFloat32Array:
	var distinct: PackedFloat32Array = PackedFloat32Array()
	for list: PackedFloat32Array in [ranges, granges]:
		for r: float in list:
			if r > 0.0 and not distinct.has(r):
				var _a: bool = distinct.push_back(r)
	distinct.sort()
	var _r: int = prof_class.resize(ranges.size()) | prof_gclass.resize(ranges.size())
	for i: int in ranges.size():
		prof_class[i] = distinct.find(ranges[i]) + 1 if ranges[i] > 0.0 else 0
		prof_gclass[i] = distinct.find(granges[i]) + 1 if granges[i] > 0.0 else 0
	classes = distinct.size() + 1
	class_range = PackedFloat32Array([0.0])
	class_range.append_array(distinct)
	return class_range


# Rings for every range class (ranges[k], k >= 1) then every sensor class (sensors[k], k >= 1).
func _rings(ranges: PackedFloat32Array, sensors: PackedFloat32Array) -> void:
	ring_start = PackedInt32Array()
	var total: int = ranges.size() + sensors.size() - 1
	for ring: int in total:
		var is_sensor: bool = ring >= ranges.size()
		var r: float = sensors[ring - ranges.size() + 1] if is_sensor else ranges[ring]
		for c: int in CELLS:
			var _s: bool = ring_start.push_back(ring_cell.size())
			if r <= 0.0:
				continue
			for k: int in range(near_start[c], near_start[c + 1]):
				var h: int = near_cell[k]
				var w: float = _sensor_w(c, h, r) if is_sensor else _threat_w(c, h, r)
				if w > 0.0:
					var _a: bool = ring_cell.push_back(h)
					var _b: bool = ring_w.push_back(w)
		var _e: bool = ring_start.push_back(ring_cell.size())


func _threat_w(c: int, h: int, r: float) -> float:
	var d: float = maxf(_arc(c, h) - circ_m[c], 0.0)
	if d <= r:
		return 1.0
	return clampf(1.0 - (d - r) / margin_m, 0.0, 1.0) if margin_m > 0.0 else 0.0


func _sensor_w(c: int, h: int, r: float) -> float:
	return 1.0 if c == h or _arc(c, h) <= r else 0.0


func _arc(c: int, h: int) -> float:
	return centre[c].angle_to(centre[h]) * Sphere.PLANET_RADIUS


# Cell centres, circumradius (corners) and the inscribed cap (distance to the four edge great circles, x 0.999).
static func _geometry() -> void:
	if not _g_centre.is_empty():
		return
	var cen: PackedVector3Array = PackedVector3Array()
	var circ: PackedFloat32Array = PackedFloat32Array()
	var inc: PackedFloat32Array = PackedFloat32Array()
	for c: int in CELLS:
		var m: Vector3 = Sphere.cell_center_dir(c, N)
		var k: PackedVector3Array = Sphere.cell_bounds_dirs(c, N)
		var cmin: float = 1.0
		var ang_in: float = PI
		for i: int in 4:
			cmin = minf(cmin, m.dot(k[i]))
			var n: Vector3 = k[i].cross(k[(i + 1) % 4]).normalized()
			ang_in = minf(ang_in, asin(absf(m.dot(n))))
		var _a: bool = cen.push_back(m)
		var _b: bool = circ.push_back(acos(clampf(cmin, -1.0, 1.0)) * Sphere.PLANET_RADIUS)
		var _c: bool = inc.push_back(cos(ang_in * 0.999))
	_g_centre = cen
	_g_circ = circ
	_g_in_cos = inc
