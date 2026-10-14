class_name SimWorld extends RefCounted
## The tick driver (03 s3.5, s4.1; R0 B.5 tick order). Content is injected at `_init` (no autoload in the sim);
## `load_map` builds every system for one match. `step()` runs, in order: 1 queued commands (+ disconnect releases),
## 2 human inputs into input slots (silent-pilot rule), 3 control check + AI hook, 3b pathing (TA-50), 4 assist
## substitution (AI-10), 5 kinematics (ships: DOCKED skipped, A-41, terrain contacts to Collision; ground: GroundMotion,
## TA-38), 6 projectiles, 7 spatial rebuild, 8 collision, 9 weapon fire, damage from the contacts and fuses (Combat),
## deferred deaths, 10 match timers (Economy, Production, Build, Docking and scoring land later), 11 vision, 12 the
## caller drains events. Helpers: `sim/world/`; control transitions: `sim/control/` (05 s2, AI-02).

const _MAPS_ROOT: String = "res://content/maps/"
const _MAGIC: int = 0x57535750   ## "PWSW" little-endian
const _FORMAT: int = 4   ## 4: Combat fire state (GD-36)
const _RULES_STATE: PackedStringArray = ["mode", "caps_profile", "sim_budget_profile", "core_exposure_s", "hard_end_s",
	"debug_commands", "profile_enabled", "friendly_fire", "adjutant_allowed", "sun_period_s", "ranked", "tick_hz"]
const _CAPS_STATE: PackedStringArray = ["id", "units", "structures", "projectiles", "wrecks", "slots"]
const _COLLISION_STATE: PackedStringArray = ["ep_gen", "ep_last", "born_gen", "born_tick"]
const _BUDGET_RUNGS_MAX: int = 8   ## rung 7 (native twins) is code, not a profile entry; 8 is A-55

var rng: Rng = Rng.new(0)              ## S7: the only RNG of the match; systems and the AI hook use forks
var spatial: Spatial = null            ## read-only outside the sim lane: step 7's hash (tests, Combat, Vision)
var collision: Collision = null        ## read-only outside the sim lane: step 8's Contact records
var vision: Vision = null              ## read-only outside the sim lane: step 11 (TA-37); net reads interest_*()

var _defs: WorldDefs
var _rules: MatchRules = null
var _store: EntityStore = null
var _proj: ProjectileStore = null
var _terrain: Terrain = Terrain.new()
var _orders: OrderQueue = null
var _players: PlayerTable = null
var _inputs: InputSlots = null
var _events: SimEvents = SimEvents.new()
var _state: MatchState = MatchState.new()
var _validator: CommandValidator = null
var _applier: CommandApplier = null
var _control: ControlMachine = null
var _intake: CommandIntake = null
var _motion: ProjectileMotion = null
var _combat: Combat = null
var _ships: ShipMotion = null
var _ground: GroundMotion = null
var _profiler: TickProfiler = TickProfiler.new()
var _view: LocalSimView = null
var _sink: SimSink = null
var _hook: SimAiHook = null
var _pathing: Pathing = null           ## step 3b; sim_ai reaches it only through CommandSinkBase.pathing() (A-55)
var _restoring: bool = false           ## deserialize: the region graphs come from the bytes, load_map skips prepare
var _match_seed: int = 0
var _map_id: StringName = &""
var _dt: float = 0.0


func _init(content: ContentSet) -> void:
	_defs = WorldDefs.new(content)


## Builds every system for one match: `map` null or with an empty id keeps the flat datum (tests); otherwise
## `res://content/maps/<id>` is loaded and SHA-verified (S9). Failure leaves the world unusable.
func load_map(map: MapDef, _seed: int, rules: MatchRules) -> Result:
	if _defs.rules == null or _defs.common == null:
		return Result.failure(ERR_UNCONFIGURED, "SimWorld: content has no rules / flight_common")
	_wire(rules)
	_map_id = map.id if map != null else &""
	if _map_id != &"":
		var err: Error = _terrain.load_map(_MAPS_ROOT + String(_map_id))
		if err != OK:
			return Result.failure(err, "SimWorld: map %s failed to load" % _map_id)
		err = _load_pathing(_MAPS_ROOT + String(_map_id))
		if err != OK:
			return Result.failure(err, "SimWorld: path grid of %s failed to load" % _map_id)
	collision.configure(_defs.projectile_radius, _defs.pad_radius_by_def, _defs.common, rules.tick_hz)
	_match_seed = _seed
	rng = Rng.new(_seed)
	return Result.success()


func add_player(slot: int, team: int, doctrine: StringName, kind: int) -> void:
	if slot < 0 or slot >= PlayerTable.SLOTS or team < 0 or team >= PlayerTable.TEAMS or _players == null:
		return
	var members: PackedInt32Array = PackedInt32Array()
	_players.members(team, members)
	if members.is_empty() and _defs.economy != null:
		_players.team_ore[team] = _defs.economy.start_ore
		_players.team_ice[team] = _defs.economy.start_ice
	_players.active[slot] = 1
	_players.team[slot] = team
	_players.kind[slot] = kind
	_players.doctrine[slot] = String(doctrine)
	_players.connected[slot] = 0 if kind == PlayerTable.KIND_OPEN else 1
	_players.disconnect_tick[slot] = -1
	var _ok: bool = _defs.resolve(slot, doctrine)
	vision.bind(slot, _defs.resolved(slot))


## Disconnect: the player is flagged now; its possession ends in step 1 of the next tick (05 C12).
func remove_player(slot: int) -> void:
	if _players != null and _players.is_active(slot) and _players.connected[slot] != 0:
		_players.connected[slot] = 0
		_players.disconnect_tick[slot] = _state.tick


## Admin action (05 C18): `slot`'s possession ends with RELEASED(reason=ADMIN) in step 1 of the next tick.
func admin_release(slot: int) -> void:
	if _control != null:
		_control.admin_release(slot)


func set_ai_hook(hook: SimAiHook) -> void:
	_hook = hook


## Validates and queues `cmd` for step 1 of the next `step()` (S1, S10); PILOT_INPUT is stored at once.
func apply_command(cmd: Command) -> CommandResult:
	if _intake == null:
		var r: CommandResult = CommandResult.new()
		r.code = CommandResult.Code.REJECTED_PHASE
		return r
	return _intake.submit(cmd)


## One tick in the R0 B.5 order; profile rows per 03 s4.4 when `MatchRules.profile_enabled`.
func step() -> void:
	if _intake == null:
		return
	var t: int = _state.tick + 1
	_state.tick = t
	_events.tick = t
	_profiler.begin()
	_intake.apply_all(t)                                     # 1
	_control.step_releases()                                 # 1: C12 disconnect, C18 admin
	_control.step_inputs(t)                                  # 2: C13 / C14
	_profiler.lap(TickProfiler.ROW_COMMANDS)
	_control.control_check()                                 # 3: C11, C18, C17, then the hook
	if _hook != null:
		_hook.on_tick(t, _view, _sink)
	_profiler.lap(TickProfiler.ROW_AI)
	_pathing.expansions_per_tick = path_expansions_per_tick()   # 3b: cut rung 8 reaches the budget (TA-49)
	var _units: int = _pathing.advance()
	_profiler.lap(TickProfiler.ROW_PATHING)
	_assist_substitution()                                   # 4
	_profiler.lap(TickProfiler.ROW_AI)
	_ships.step(t, _dt)                                      # 5 (DOCKED skipped, A-41)
	_ground.step(t, _dt)                                     # 5: GroundMotion (TA-38)
	_profiler.lap(TickProfiler.ROW_KINEMATICS)
	_motion.step(t, _dt)                                     # 6
	_profiler.lap(TickProfiler.ROW_PROJECTILES)
	spatial.rebuild()                                        # 7
	_profiler.lap(TickProfiler.ROW_SPATIAL)
	collision.step(t)                                        # 8 + 8b
	_profiler.lap(TickProfiler.ROW_COLLISION)
	_step_combat(t)                                          # 9
	_profiler.lap(TickProfiler.ROW_COMBAT)
	_step_match(t)                                           # 10
	_profiler.lap(TickProfiler.ROW_ECONOMY)
	vision.step(t, _rules.sim_budget_profile)                # 11: staggered per team (TA-37)
	_profiler.lap(TickProfiler.ROW_VISION)
	_profiler.finish()                                       # 12: the caller drains events


func tick() -> int:
	return _state.tick


func view() -> SimView:
	return _view


func drain_events() -> Array[SimEvent]:
	return _events.drain()


## The whole match state (S4) in a fixed order: header, rules, clock, players, input slots, rate buckets, pending
## commands, entity and projectile stores, Collision's per-slot state, Combat's fire state, orders, pathing, then the AI hook's bytes.
## Events are not included: the caller drains them every tick (step 12).
func serialize() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_32(_MAGIC)
	buf.put_32(_FORMAT)
	buf.put_64(_match_seed)
	buf.put_var(rng.state())
	buf.put_var(String(_map_id))
	StateIO.put_props(buf, _rules, _RULES_STATE)
	StateIO.put_props(buf, _rules.caps, _CAPS_STATE)
	_state.write_state(buf)
	_players.write_state(buf)
	_inputs.write_state(buf)
	_validator.write_state(buf)
	_intake.write_state(buf)
	_control.write_state(buf)
	_store.write_state(buf)
	_proj.write_state(buf)
	StateIO.put_props(buf, collision, _COLLISION_STATE)
	_combat.write_state(buf)
	buf.put_var(OrderQueueCodec.serialize(_orders))
	_pathing.write_state(buf)
	buf.put_var(_hook.serialize() if _hook != null else PackedByteArray())
	return buf.data_array


## A world equal to the one `serialize` saw (S4), with `hook` attached and handed its bytes; null when `bytes`
## are malformed or the map fails to load.
static func deserialize(bytes: PackedByteArray, content: ContentSet, hook: SimAiHook) -> SimWorld:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	if bytes.size() < 8 or buf.get_32() != _MAGIC or buf.get_32() != _FORMAT:
		return null
	var w: SimWorld = SimWorld.new(content)
	w._restoring = true
	var seed_v: int = buf.get_64()
	var rng_v: Variant = buf.get_var()
	var map_v: Variant = buf.get_var()
	var rules: MatchRules = MatchRules.new()
	rules.caps = CapsDef.new()
	if typeof(rng_v) != TYPE_PACKED_BYTE_ARRAY or typeof(map_v) != TYPE_STRING:
		return null
	rules.adopt_match_def(content.match_rules)
	if not StateIO.get_props(buf, rules, _RULES_STATE) or not StateIO.get_props(buf, rules.caps, _CAPS_STATE):
		return null
	var map: MapDef = MapDef.new()
	map.id = StringName(str(map_v))
	if not w.load_map(map, seed_v, rules).ok or not w._read_state(buf):
		return null
	var rng_b: PackedByteArray = rng_v
	w.rng = Rng.from_state(rng_b)
	w._hook = hook
	if hook != null:
		var hv: Variant = buf.get_var()
		var hook_b: PackedByteArray = PackedByteArray()
		if typeof(hv) == TYPE_PACKED_BYTE_ARRAY:
			hook_b = hv
		hook.deserialize(hook_b)
	w.spatial.rebuild()
	w.vision.rebuild_lists()
	return w


## The 14 rows of 03 s4.4 for the last tick, in ms (zeros unless `MatchRules.profile_enabled`); a copy.
func profile() -> PackedFloat32Array:
	return _profiler.rows.duplicate()


## Activates cut rungs 1..level of 03 s4.3 by rewriting `MatchRules.sim_budget_profile`; consumers read the list:
## rung 1 the AI hook (think cadence), rung 2 Vision (`cut_ladder.rung_2_vision_hz`, read every step); rung 3 caps live
## projectiles at `cut_ladder` `rung_3_projectile_cap` here; rung 8 is read through `path_expansions_per_tick()`; rungs 4, 5 and 6 wait for their systems.
func set_budget_profile(level: int) -> void:
	var n: int = clampi(level, 0, _BUDGET_RUNGS_MAX)
	var rungs: PackedInt32Array = PackedInt32Array()
	for k: int in n:
		var _a: bool = rungs.push_back(k + 1)
	_rules.sim_budget_profile = rungs
	var live_cap: int = _rules.caps.projectiles if _rules.caps.projectiles > 0 else ProjectileStore.SLOT_COUNT
	_proj.live_cap = mini(live_cap, _defs.rules.rung_3_projectile_cap) if n >= 3 else live_cap


## Path budget of this tick: `rules.path_expansions_per_tick`, `cut_ladder.rung_8_path_expansions_per_tick` at rung 8.
## `Pathing.expansions_per_tick` is assigned this value by the step 3b wiring (TA-50).
func path_expansions_per_tick() -> int:
	if _rules.sim_budget_profile.has(8):
		return _defs.rules.rung_8_path_expansions_per_tick
	return _defs.rules.path_expansions_per_tick


## Vision's per-team interest lists (03 s3.6; layout in sim/vision/MODULE.md): team t, interest cell c
## (Sphere.cell_of(p, GRID_INTEREST)) -> interest_ids()[interest_start()[t * 384 + c] + k], k < interest_count()[...].
## Read-only and valid until the next step() (S3); shared, not copied, so do not keep them across ticks.
func interest_start() -> PackedInt32Array:
	return vision.grid.cell_start


func interest_count() -> PackedInt32Array:
	return vision.grid.cell_count


func interest_ids() -> PackedInt32Array:
	return vision.grid.ids


func terrain() -> Terrain:
	return _terrain


func store() -> EntityStore:
	return _store


func projectiles() -> ProjectileStore:
	return _proj


func _wire(rules: MatchRules) -> void:
	_rules = rules
	if rules.tick_hz <= 0:
		rules.tick_hz = _defs.rules.tick_hz
	if rules.caps == null:
		rules.caps = CapsDef.new()
	_dt = 1.0 / float(rules.tick_hz)
	_store = EntityStore.new()
	_proj = ProjectileStore.new(rules.caps.projectiles if rules.caps.projectiles > 0 else ProjectileStore.SLOT_COUNT)
	_terrain = Terrain.new()
	spatial = Spatial.new(_store, _proj)
	collision = Collision.new(_store, _proj, spatial, _terrain)
	collision.friendly_fire = rules.friendly_fire
	_orders = OrderQueue.new(_store)
	_players = PlayerTable.new()
	_inputs = InputSlots.new()
	_events = SimEvents.new()
	_state = MatchState.new()
	_control = ControlMachine.new(_store, _orders, _players, _inputs, _events, _defs.rules.ceiling_hard_m, rules.tick_hz)
	_control.configure(_defs.rules)
	collision.shooter_grace_ticks = _defs.rules.shooter_grace_ticks
	_validator = CommandValidator.new(_store, _players, _defs, rules, _control)
	var c: ContentSet = _defs.content
	if c.order_rules != null:
		_validator.order_rules = OrderRules.from_def(c.order_rules)
		_validator.order_rules.bind(c.ships, c.ground_units, c.structures)
		_orders.limit = _validator.order_rules.queue_max
		_control.orders.rules = _validator.order_rules
	_applier = CommandApplier.new(_store, _orders, _players, _inputs, _events, _defs, _validator, _control)
	_intake = CommandIntake.new(_validator, _applier, _state)
	_motion = ProjectileMotion.new(_store, _proj, _defs)
	_combat = Combat.new(_store, _proj, collision, spatial, _defs, rules, _events, _applier, _inputs)
	_ships = ShipMotion.new(_store, _inputs, _defs, collision, _terrain)
	_profiler.enabled = rules.profile_enabled
	_pathing = Pathing.from_rules(_defs.rules)
	_pathing.set_terrain(_terrain)
	_ground = GroundMotion.new(_store, _inputs, _defs, _terrain, _pathing)
	_view = LocalSimView.new(_store, _proj, spatial, _terrain, _players, _defs, _orders, rules, _state, _pathing)
	_sink = SimSink.new(_intake, _store, _inputs, _pathing)
	vision = Vision.new(_store, _defs, rules.tick_hz)


func _read_state(buf: StreamPeerBuffer) -> bool:
	if not (_state.read_state(buf) and _players.read_state(buf) and _inputs.read_state(buf)):
		return false
	if not (_validator.read_state(buf) and _intake.read_state(buf) and _control.read_state(buf)):
		return false
	if not (_store.read_state(buf) and _proj.read_state(buf)):
		return false
	if not StateIO.get_props(buf, collision, _COLLISION_STATE) or not _combat.read_state(buf):
		return false
	var ov: Variant = buf.get_var()
	if typeof(ov) != TYPE_PACKED_BYTE_ARRAY:
		return false
	var ob: PackedByteArray = ov
	if not OrderQueueCodec.deserialize(_orders, ob) or not _pathing.read_state(buf):
		return false
	for p: int in PlayerTable.SLOTS:
		if _players.is_active(p):
			var _ok: bool = _defs.resolve(p, StringName(_players.doctrine[p]))
			vision.bind(p, _defs.resolved(p))
	_events.tick = _state.tick
	return true


# Map load (A-55): baked weights; region graphs for each distinct ground-unit slope mask (at most MASK_SLOTS, in
# def order) unless deserialize brings them. The flat datum keeps weight 1 everywhere and builds graphs lazily.
func _load_pathing(map_dir: String) -> Error:
	var err: Error = _pathing.load_weights(map_dir)
	if err != OK or _restoring:
		return err
	var masks: PackedInt32Array = PackedInt32Array()
	for g: GroundUnitDef in _defs.content.ground_units:
		var m: int = Pathing.mask_for(g.max_slope_deg)
		if m > 0 and not masks.has(m) and masks.size() < PathSearch.MASK_SLOTS:
			var _a: bool = masks.push_back(m)
	for m: int in masks:
		_pathing.prepare(m)
	return OK


# Step 4 (R0 B.5): Assist.auto_dock() / Assist.link_bridge() (sim/steer, AI-10, AI-08) overwrite the input slots
# of possessed entities holding DOCK near a free friendly pad or under LINK_BRIDGE. Stub until AI-10: no change.
func _assist_substitution() -> void:
	pass


# Step 9: Combat fires weapons (GD-36), applies the step-8 contacts (GD-08: damage, blasts, ramming) and the fuses,
# then the deferred deaths of this tick drop their fire state and are freed (03 s4.1 rule 6). Combat draws on the
# world's `rng`, passed per step (S7).
func _step_combat(t: int) -> void:
	_combat.step(t, rng)
	for s: int in _applier.dying:
		_combat.forget(s)
	_applier.resolve_deaths(t)


# Step 10 match timers (02 s12.1): CORE_EXPOSURE once at core_exposure_s; at hard_end_s every possession is released
# (05 C16) and MATCH_END fires (winner by surviving structure value is Economy's, GD-20). Shield, caps, scoring join here.
func _step_match(t: int) -> void:
	if _state.ended():
		return
	var ph: MatchRules.Phase = _rules.phase(t)
	var clock: float = float(t) / float(_rules.tick_hz)
	if ph != MatchRules.Phase.PLAYING and _state.exposure_tick < 0:
		_state.exposure_tick = t
		var _e: SimEvent = _events.emit(SimEvent.Kind.CORE_EXPOSURE, 0, 0, Vector3.ZERO, clock, -1)
	if ph == MatchRules.Phase.ENDED:
		_state.ended_tick = t
		_control.release_all(ControlMachine.ReleaseReason.MATCH)
		var _m: SimEvent = _events.emit(SimEvent.Kind.MATCH_END, _state.winner_team, 0, Vector3.ZERO, clock, -1)
