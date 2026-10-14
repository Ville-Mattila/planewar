class_name LandingWorld extends SimView
## Landing test world for AI-09 (a FakeSimView, 05 s11.1): ships stepped by Kinematics.step_ship over a Terrain,
## pads as structures, the R0 B.5 landing rule evaluated every tick in the pad volume (A-31, Collision.landing_band)
## and off-pad terrain contacts classified per episode (Collision.classify_terrain). Docking service is not in the
## sim yet (GD-15), so a docked ship is "serviced" after `service_ticks` and removed, which frees the pad.
## Not a contract: the SimView accessors LandingPilot reads, filled from these arrays.

enum Outcome { FLYING, LANDED, DAMAGED, CRASHED, OFF_PAD }

const SHIP_SLOT0: int = 1
const PAD_SLOT0: int = 200
const PAD_DEF: int = 1

var terrain: Terrain
var common: FlightCommonDef
var rules: RulesDef
var pad_radius_by_def: PackedFloat32Array = PackedFloat32Array([0.0, 10.0])
var service_ticks: int = 1 << 30
var contact_release_m: float = 2.0
var now: int = 0
# ships
var ids: PackedInt32Array = PackedInt32Array()
var ss: Array[ShipState] = []
var defs: Array[ShipDef] = []
var teams: PackedInt32Array = PackedInt32Array()
var outcome: PackedInt32Array = PackedInt32Array()      ## Outcome
var dock_pad: PackedInt32Array = PackedInt32Array()     ## pad id while docked
var dock_tick: PackedInt32Array = PackedInt32Array()
var removed: PackedByteArray = PackedByteArray()        ## serviced and gone
var scrapes: PackedInt32Array = PackedInt32Array()      ## off-pad scrape episodes
var touchdown: PackedVector4Array = PackedVector4Array()   ## sink, horizontal speed, tilt deg, offset m at the pad contact
var _in_contact: PackedByteArray = PackedByteArray()
# pads
var pad_ids: PackedInt32Array = PackedInt32Array()
var pad_pos: PackedVector3Array = PackedVector3Array()
var pad_up: PackedVector3Array = PackedVector3Array()
var pad_team: PackedInt32Array = PackedInt32Array()
var pad_alive: PackedByteArray = PackedByteArray()
var threat_ids: PackedInt32Array = PackedInt32Array()  ## returned by projectiles_near for any query (scripted)


func _init(t: Terrain, flight_common: FlightCommonDef, rules_def: RulesDef) -> void:
	terrain = t
	common = flight_common
	rules = rules_def


## A pad on the terrain at unit direction `dir` (normal = local up), team `team`.
func add_pad(dir: Vector3, team_id: int = 0) -> int:
	var id: int = EntityId.make(PAD_SLOT0 + pad_ids.size(), 1)
	var _a: bool = pad_ids.push_back(id)
	var n: Vector3 = dir.normalized()
	var _b: bool = pad_pos.push_back(n * (Sphere.PLANET_RADIUS + terrain.height_at(n)))
	var _c: bool = pad_up.push_back(n)
	var _d: bool = pad_team.push_back(team_id)
	var _e: bool = pad_alive.push_back(1)
	return id


func add_ship(def: ShipDef, s: ShipState, team_id: int = 0) -> int:
	var id: int = EntityId.make(SHIP_SLOT0 + ids.size(), 1)
	var _r: Array[bool] = [ids.push_back(id), teams.push_back(team_id), outcome.push_back(Outcome.FLYING),
		dock_pad.push_back(0), dock_tick.push_back(-1), removed.push_back(0), scrapes.push_back(0),
		touchdown.push_back(Vector4.ZERO), _in_contact.push_back(0)]
	ss.append(s)
	defs.append(def)
	return id


func ship_index(id: int) -> int:
	return EntityId.slot(id) - SHIP_SLOT0 if EntityId.slot(id) < PAD_SLOT0 else -1


func pad_index(id: int) -> int:
	return EntityId.slot(id) - PAD_SLOT0 if EntityId.slot(id) >= PAD_SLOT0 else -1


## True while ship `i` flies (not docked, not crashed, not removed).
func flying(i: int) -> bool:
	return outcome[i] == Outcome.FLYING


## Kinematics for ship `i` with `inp`, then the landing rule and terrain contact classification.
func step_ship(i: int, inp: PilotInput) -> void:
	var s: ShipState = ss[i]
	var _r: ShipState = Kinematics.step_ship(s, inp, defs[i], common, rules, terrain, 1.0 / float(rules.tick_hz))
	for k: int in pad_ids.size():
		if pad_alive[k] == 0 or pad_team[k] != teams[i] or _occupant_index(pad_ids[k]) >= 0:
			continue
		var rel: Vector3 = s.p - pad_pos[k]
		var hh: float = rel.dot(pad_up[k])
		var off: float = (rel - pad_up[k] * hh).length()
		if off > pad_radius_by_def[PAD_DEF] or hh > defs[i].bounding_radius + 0.5 or hh < -(defs[i].bounding_radius + 0.5):
			continue
		var sink: float = -s.v.dot(pad_up[k])
		var v_hor: float = (s.v + pad_up[k] * sink).length()
		var tilt: float = rad_to_deg(s.fwd.angle_to(pad_up[k]))
		touchdown[i] = Vector4(sink, v_hor, tilt, off)
		var band: int = Collision.landing_band(sink, v_hor, tilt, common)
		if band == Collision.L_DESTROY:
			outcome[i] = Outcome.CRASHED
			return
		outcome[i] = Outcome.LANDED if band == Collision.L_SAFE else Outcome.DAMAGED
		dock_pad[i] = pad_ids[k]
		dock_tick[i] = now
		s.v = Vector3.ZERO
		return
	if not s.terrain_hit:
		if _in_contact[i] != 0 and s.p.length() - Sphere.PLANET_RADIUS - terrain.height_at(s.p) \
				- defs[i].bounding_radius >= contact_release_m:
			_in_contact[i] = 0
		return
	if Collision.classify_terrain(s.hit_normal_speed, common) != Collision.T_SCRAPE:
		outcome[i] = Outcome.OFF_PAD
		touchdown[i] = Vector4(s.hit_normal_speed, 0.0, 0.0, -1.0)
		return
	if _in_contact[i] == 0:
		scrapes[i] += 1
	_in_contact[i] = 1


## End of tick: service timers (a docked ship leaves after service_ticks), clock.
func end_tick() -> void:
	for i: int in ids.size():
		if dock_pad[i] != 0 and removed[i] == 0 and now - dock_tick[i] >= service_ticks:
			removed[i] = 1
	now += 1


func _occupant_index(pad: int) -> int:
	for i: int in ids.size():
		if dock_pad[i] == pad and removed[i] == 0:
			return i
	return -1


# region SimView
func alive(id: int) -> bool:
	var i: int = ship_index(id)
	if i >= 0:
		return i < ids.size() and ids[i] == id and removed[i] == 0 and outcome[i] != Outcome.CRASHED \
			and outcome[i] != Outcome.OFF_PAD
	var k: int = pad_index(id)
	return k >= 0 and k < pad_ids.size() and pad_ids[k] == id and pad_alive[k] != 0


func pos(id: int) -> Vector3:
	var i: int = ship_index(id)
	if i >= 0:
		return ss[i].p
	return pad_pos[pad_index(id)]


func vel(id: int) -> Vector3:
	var i: int = ship_index(id)
	return ss[i].v if i >= 0 else Vector3.ZERO


func basis(id: int) -> Basis:
	var i: int = ship_index(id)
	if i >= 0:
		var s: ShipState = ss[i]
		return Basis(s.fwd.cross(s.up), s.up, -s.fwd)
	var n: Vector3 = pad_up[pad_index(id)]
	var f: Basis = Sphere.tangent_frame(n)
	return Basis(f.x, n, -f.y)


func def_id(id: int) -> int:
	return PAD_DEF if pad_index(id) >= 0 else 0


func team(id: int) -> int:
	var i: int = ship_index(id)
	return teams[i] if i >= 0 else pad_team[pad_index(id)]


func fuel01(id: int) -> float:
	var i: int = ship_index(id)
	return ss[i].fuel / defs[i].fuel_s


func dock_state(id: int) -> int:
	var i: int = ship_index(id)
	return 2 if i >= 0 and dock_pad[i] != 0 else 0


func pad_occupant(pad: int) -> int:
	var i: int = _occupant_index(pad)
	return ids[i] if i >= 0 else 0


func hp01(id: int) -> float:
	return 1.0 if alive(id) else 0.0


func nearest_friendly_pad(id: int) -> int:
	var best: int = 0
	var best_d: float = INF
	for k: int in pad_ids.size():
		if pad_alive[k] != 0 and pad_team[k] == team(id) and pos(id).distance_to(pad_pos[k]) < best_d:
			best_d = pos(id).distance_to(pad_pos[k])
			best = pad_ids[k]
	return best


func pad_queue(_pad: int) -> PackedInt32Array:
	return PackedInt32Array()


func structures() -> PackedInt32Array:
	return pad_ids


func ships() -> PackedInt32Array:
	return ids


func projectiles_near(_p: Vector3, _r: float, _team_mask: int) -> PackedInt32Array:
	return threat_ids


func terrain_height(dir: Vector3) -> float:
	return terrain.height_at(dir)


func tick() -> int:
	return now
# endregion
