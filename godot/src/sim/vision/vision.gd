class_name Vision extends RefCounted
## Tick step 11 (03 s3.7, ADR-05, R0 C2-23; TA-37): per team t, bit t of `EntityStore.visible_mask` and t's
## interest lists (InterestGrid). Entity x of another team (or neutral) is visible to t when some live non-wreck
## entity e of t with sensor radius s_e (`sensor_radius` of its doctrine-resolved def) has |p_e - p_x| <= s_e and
## `Sphere.is_occluded_by_datum(p_e, p_x)` false (A-10 endpoint semantics: units below the datum see and are
## seen), or reveal radius r_e (`deck_reveal_radius`, the Sensor Mast) has |p_e - p_x| <= r_e regardless of
## occlusion (01 s6.2). Own-team entities always carry their own bit. The result is an OR over exact pair tests
## (`sees`), so it is independent of iteration order: deterministic for identical state on every peer.
##
## Stagger: the pass rate is `hz` (10 Hz, every 3 ticks at 30 Hz) or `rung_2_hz` (5 Hz) while cut rung 2 is in
## `MatchRules.sim_budget_profile`; team t runs on ticks with tick % period == t % period, so every team runs
## exactly once per period and at most ceil(TEAMS / period) teams share a tick. A team's bit and list keep their
## last pass in between (consumers assume <= 200 ms latency, 03 s3.7). Pruning: SensorGroups (exact bounds only).

const TEAMS: int = InterestGrid.TEAMS
const VISION_HZ: int = 10          ## 03 s3.7 base rate; documented default until rules.json carries it (needs content)
const RUNG_2_VISION_HZ: int = 5    ## default of rules.cut_ladder.rung_2_vision_hz (R0 B.11 A-51); `rung_2_hz` reads the def
const RUNG_VISION: int = 2         ## the cut-ladder rung that lowers the rate (03 s4.3)
const OWNERS: int = WorldDefs.NEUTRAL + 1
const DEF_N: int = DefRanges.WEAPON_BASE   ## entity def_ids are below the weapon range

var grid: InterestGrid = InterestGrid.new()
var groups: SensorGroups = SensorGroups.new()
var tick_hz: int = 0
var hz: int = VISION_HZ
var rung_2_hz: int = RUNG_2_VISION_HZ
var last_pass: PackedInt32Array = PackedInt32Array()   ## per team: tick of its last pass, -1 before the first
var sensor_r: PackedFloat32Array = PackedFloat32Array()   ## [owner * DEF_N + def_id]: sensor radius, 0 = none
var reveal_r: PackedFloat32Array = PackedFloat32Array()   ## [owner * DEF_N + def_id]: deck reveal radius, 0 = none

var _store: EntityStore
var _seen: PackedInt32Array = PackedInt32Array()


## `ticks_per_s` = MatchRules.tick_hz; `rung_2_hz` = rules.cut_ladder.rung_2_vision_hz; every owner row starts
## from `defs.resolved(owner)`.
func _init(store: EntityStore, defs: WorldDefs, ticks_per_s: int) -> void:
	_store = store
	tick_hz = ticks_per_s
	if defs.rules != null and defs.rules.rung_2_vision_hz > 0:
		rung_2_hz = defs.rules.rung_2_vision_hz
	var e: int = _seen.resize(EntityStore.SLOT_COUNT) | last_pass.resize(TEAMS)
	e |= sensor_r.resize(OWNERS * DEF_N) | reveal_r.resize(OWNERS * DEF_N)
	assert(e == OK)
	last_pass.fill(-1)
	sensor_r.fill(0.0)
	reveal_r.fill(0.0)
	for o: int in OWNERS:
		bind(o, defs.resolved(o))


## Fills owner row `owner` (player slot, or WorldDefs.NEUTRAL) from resolved defs; call after a doctrine resolve.
func bind(owner: int, r: ResolvedDefs) -> void:
	var row: int = clampi(owner, 0, OWNERS - 1) * DEF_N
	var reach: float = 0.0
	for i: int in r.ships.size():
		sensor_r[row + DefRanges.SHIP_BASE + i] = r.ships[i].sensor_radius
		reach = maxf(reach, r.ships[i].sensor_radius)
	for i: int in r.ground_units.size():
		sensor_r[row + DefRanges.GROUND_BASE + i] = r.ground_units[i].sensor_radius
		reach = maxf(reach, r.ground_units[i].sensor_radius)
	for i: int in r.structures.size():
		var sd: StructureDef = r.structures[i]
		sensor_r[row + DefRanges.STRUCTURE_BASE + i] = sd.sensor_radius
		reveal_r[row + DefRanges.STRUCTURE_BASE + i] = sd.deck_reveal_radius
		reach = maxf(reach, maxf(sd.sensor_radius, sd.deck_reveal_radius))
	grid.ensure_reach(reach)


## Ticks between two passes of one team: tick_hz / hz, or tick_hz / rung_2_hz under cut rung 2.
func period(rungs: PackedInt32Array) -> int:
	var rate: int = rung_2_hz if rungs.has(RUNG_VISION) else hz
	return maxi(1, MathX.floori_div(tick_hz, maxi(1, rate)))


## True when `team` runs its pass on `tick` (the stagger rule).
func runs(team: int, tick: int, rungs: PackedInt32Array) -> bool:
	var p: int = period(rungs)
	return MathX.posmod_i(tick, p) == team % p


## Tick step 11: the passes of the teams scheduled on `tick` (`rungs` = MatchRules.sim_budget_profile).
func step(tick: int, rungs: PackedInt32Array) -> void:
	var p: int = period(rungs)
	var phase: int = MathX.posmod_i(tick, p)
	var indexed: bool = false
	for t: int in TEAMS:
		if t % p != phase:
			continue
		if not indexed:
			grid.index(_store)
			indexed = true
		pass_team(t, tick)


## Every team's pass now, ignoring the stagger (tests, tools); not part of the tick.
func refresh(tick: int) -> void:
	grid.index(_store)
	for t: int in TEAMS:
		pass_team(t, tick)


## Re-derives every team's interest list from the current `visible_mask` (the slots carrying bit t, own team
## included) without sensing and without changing a bit: after deserialize the bits are state (S4), the lists derived.
func rebuild_lists() -> void:
	grid.index(_store)
	for t: int in TEAMS:
		grid.build_list(t, _store, _seen, grid.seen_from_mask(t, _store, _seen), false)


## One sensing pass for team `t` over the current index (`grid.index` this tick), then its list and bit t.
func pass_team(t: int, tick: int) -> void:
	var seen_n: int = 0
	if groups.gather(t, grid, _store, sensor_r, reveal_r) > 0:
		groups.cover(grid)
		var seen: PackedInt32Array = _seen
		_seen = PackedInt32Array()                 # sole owner while writing
		seen_n = groups.scan(t, grid, _store.pos, seen)
		_seen = seen
		groups.clear_cover()
	grid.build_list(t, _store, _seen, seen_n, true)
	last_pass[t] = tick


## EntityIds visible to `team` in interest `cell` at its last pass (allocates; NET-08 reads the flat arrays).
func ids_in_cell(team: int, cell: int) -> PackedInt32Array:
	if team < 0 or team >= TEAMS or cell < 0 or cell >= InterestGrid.CELLS:
		return PackedInt32Array()
	var i: int = team * InterestGrid.CELLS + cell
	var s: int = grid.cell_start[i]
	return grid.ids.slice(s, s + grid.cell_count[i])


## The pair test of 03 s3.7 for one sensor: in reveal range, or in sensor range and not occluded by the datum.
static func sees(sensor: Vector3, target: Vector3, sensor_radius: float, reveal_radius: float) -> bool:
	var d2: float = sensor.distance_squared_to(target)
	if d2 <= reveal_radius * reveal_radius:
		return true
	return d2 <= sensor_radius * sensor_radius and not Sphere.is_occluded_by_datum(sensor, target)
