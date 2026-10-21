class_name SimViewContract extends RefCounted
## The SimView contract (01 s9.4, R0 C2-05 / B.5 / A-56) as data: `run(view, scene)` evaluates one clause per accessor
## on the scripted scene and records the accessor names that failed (`failed`) and that were exercised
## (`covered`). It never asserts, so the same clauses judge a real view (must fail nothing) and a mutant (must fail
## the broken accessor). Accessors whose system has not landed (service / pad queue: GD-15; field_remaining,
## player_score, landing_grade_last: scoring; path_grid_version: TA-50)
## are held to the neutral default of the SimView base class; the clause changes when the system lands.

const EPS: float = 1e-4

var failed: PackedStringArray = PackedStringArray()
var covered: PackedStringArray = PackedStringArray()
var _v: SimView
var _s: SimViewScene
var _st: EntityStore


func run(view: SimView, scene: SimViewScene) -> void:
	_v = view
	_s = scene
	_st = scene.world.store()
	failed = PackedStringArray()
	covered = PackedStringArray()
	_identity()
	_vitals()
	_lists()
	_flight()
	_docking_and_orders()
	_team_and_match()
	_poses()


func _t(accessor: StringName, ok: bool) -> void:
	var n: String = String(accessor)
	if not covered.has(n):
		var _a: bool = covered.push_back(n)
	if not ok and not failed.has(n):
		var _b: bool = failed.push_back(n)


static func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


static func _sorted(ids: PackedInt32Array) -> Array:
	var a: Array = Array(ids)
	a.sort()
	return a


func _same(got: PackedInt32Array, want: Array) -> bool:
	want.sort()
	return _sorted(got) == want


func _slot(id: int) -> int:
	return EntityId.slot(id)


func _identity() -> void:
	var s: SimViewScene = _s
	var dart: int = WorldTestKit.def_id(&"dart")
	_t(&"alive", _v.alive(s.a) and _v.alive(s.b) and _v.alive(s.wreck) and _v.alive(s.rocket)
			and not _v.alive(s.dead) and not _v.alive(0))
	_t(&"pos", _v.pos(s.a).is_equal_approx(_st.pos[_slot(s.a)]) and _v.pos(s.b).is_equal_approx(_st.pos[_slot(s.b)])
			and _v.pos(s.dead) == Vector3.ZERO)
	_t(&"vel", _v.vel(s.a).is_equal_approx(_st.vel[_slot(s.a)]) and _v.vel(s.a) != Vector3.ZERO and _v.vel(s.dead) == Vector3.ZERO)
	var sa: int = _slot(s.a)
	var want: Basis = Basis(_st.fwd[sa].cross(_st.up[sa]), _st.up[sa], -_st.fwd[sa])     # 03 s15.4: Godot -Z forward
	_t(&"basis", _v.basis(s.a).is_equal_approx(want) and _v.basis(s.dead) == Basis.IDENTITY)
	_t(&"def_id", _v.def_id(s.a) == dart and _v.def_id(s.core) == WorldTestKit.def_id(&"core") and _v.def_id(s.dead) == -1)
	_t(&"owner", _v.owner(s.a) == 0 and _v.owner(s.b) == 1 and _v.owner(s.wreck) == -1 and _v.owner(s.dead) == -1)
	_t(&"team", _v.team(s.a) == 0 and _v.team(s.b) == 1 and _v.team(s.wreck) == -1 and _v.team(s.dead) == -1)
	_t(&"flags", (_v.flags(s.a) & EntityStore.F_POSSESSABLE) != 0 and (_v.flags(s.a) & EntityStore.F_ALIVE) != 0
			and (_v.flags(s.c) & EntityStore.F_DOCKED) != 0 and (_v.flags(s.a) & EntityStore.F_DOCKED) == 0 and _v.flags(s.dead) == 0)
	_t(&"radius", _near(_v.radius(s.a), s.ship_def().bounding_radius) and _near(_v.radius(s.wreck), 5.0) and _v.radius(s.dead) == 0.0)
	_t(&"def_kind", _v.def_kind(s.a) == EntityStore.K_SHIP and _v.def_kind(s.core) == EntityStore.K_STRUCTURE
			and _v.def_kind(s.wreck) == EntityStore.K_WRECK and _v.def_kind(s.dead) == -1)
	_t(&"tick", _v.tick() == s.world.tick() and _v.tick() > 0)
	_t(&"terrain_height", _near(_v.terrain_height(Vector3.RIGHT), 0.0) and _near(_v.terrain_height(Vector3.UP), 0.0))   # flat datum map


func _vitals() -> void:
	var s: SimViewScene = _s
	_t(&"hp01", _near(_v.hp01(s.a), SimViewScene.HP01) and _near(_v.hp01(s.b), 1.0) and _v.hp01(s.dead) == 0.0)
	_t(&"fuel01", _near(_v.fuel01(s.a), SimViewScene.FUEL01) and _v.fuel01(s.core) == 0.0 and _v.fuel01(s.dead) == 0.0)
	_t(&"ammo", _v.ammo(s.a) == SimViewScene.AMMO and _v.ammo(s.dead) == 0)
	_t(&"bombs", _v.bombs(s.a) == SimViewScene.BOMBS and _v.bombs(s.dead) == 0)
	_t(&"rockets", _v.rockets(s.a) == SimViewScene.ROCKETS and _v.rockets(s.dead) == 0)
	_t(&"control_state", _v.control_state(s.a) == SimViewScene.CONTROL and _v.control_state(s.dead) == 0)
	_t(&"possessor", _v.possessor(s.a) == 0 and _v.possessor(s.b) == -1 and _v.possessor(s.dead) == -1)
	_t(&"ai_tag", _v.ai_tag(s.a) == SimViewScene.AI_TAG and _v.ai_tag(s.b) == 0 and _v.ai_tag(s.dead) == 0)
	_t(&"overlay", _v.overlay(s.a) == SimViewScene.OVERLAY and _v.overlay(s.b) == 0 and _v.overlay(s.dead) == 0)
	_t(&"cargo", _near(_v.cargo(s.a), SimViewScene.CARGO) and _v.cargo(s.b) == 0.0 and _v.cargo(s.dead) == 0.0)
	_t(&"cargo_kind", _v.cargo_kind(s.a) == SimViewScene.CARGO_KIND and _v.cargo_kind(s.b) == 0 and _v.cargo_kind(s.dead) == 0)
	_t(&"link", _v.link(s.c) == s.pad and _v.link(s.a) == 0 and _v.link(s.dead) == 0)
	_t(&"boost_state", _v.boost_state(s.a) == 2 and _v.boost_state(s.b) == 0 and _v.boost_state(s.dead) == 0)   # 2 cooling, 0 ready
	_t(&"flip_cooldown01", _near(_v.flip_cooldown01(s.a), SimViewScene.FLIP_CD01) and _v.flip_cooldown01(s.b) == 0.0)
	_t(&"landing_grade_last", _v.landing_grade_last(s.a) == -1)
	_t(&"supply01", _near(_v.supply01(s.tower), SimViewScene.TOWER_SUPPLY01) and _v.supply01(s.core) == 0.0
			and _v.supply01(s.a) == 0.0 and _v.supply01(s.dead) == 0.0)


func _lists() -> void:
	var s: SimViewScene = _s
	var cell: int = Spatial.cell_of(_v.pos(s.a))
	_t(&"ids_in_cell", _same(_v.ids_in_cell(cell), [s.a, s.rocket]))
	_t(&"ids_near", _same(_v.ids_near(_v.pos(s.a), 50.0, Spatial.MASK_SHIP), [s.a])
			and _same(_v.ids_near(_v.pos(s.a), 300.0, Spatial.MASK_SHIP), [s.a, s.b])
			and _v.ids_near(_v.pos(s.a), 50.0, Spatial.MASK_STRUCTURE).is_empty())
	_t(&"ships", _same(_v.ships(), [s.a, s.b, s.c]))
	_t(&"structures", _same(_v.structures(), [s.core, s.pad, s.yard, s.tower]))
	_t(&"wrecks", _same(_v.wrecks(), [s.wreck]))
	_t(&"visible_ids", _same(_v.visible_ids(0), [s.core, s.pad, s.yard, s.tower, s.a, s.b, s.c]) and _v.visible_ids(7).is_empty())
	_t(&"visible_enemy_ships", _enemy_ships_ok())
	_t(&"visible_to", _v.visible_to(0, s.a) and _v.visible_to(0, s.b) and not _v.visible_to(0, s.wreck)
			and not _v.visible_to(0, s.dead) and not _v.visible_to(9, s.a))
	_t(&"unit_count", _v.unit_count(0) == 2 and _v.unit_count(1) == 1 and _v.unit_count(2) == 0)


## TA-63: team 0 sees only `b` (its own ships, the structures and the wreck are never listed), team 1 `a` and `c` (not the core it also sees); ids ascending (V10: a state-only order); a long pre-filled `out` is neither reallocated nor read past the count; bad teams give 0.
func _enemy_ships_ok() -> bool:
	var s: SimViewScene = _s
	var out0: PackedInt32Array = PackedInt32Array()
	var n0: int = _v.visible_enemy_ships(0, out0)
	var out1: PackedInt32Array = PackedInt32Array([-7, -7, -7, -7, -7, -7, -7, -7, -7, -7])
	var n1: int = _v.visible_enemy_ships(1, out1)
	var out2: PackedInt32Array = PackedInt32Array([-7])
	return n0 == 1 and out0.size() >= 1 and out0[0] == s.b 			and n1 == 2 and out1.size() == 10 and out1[2] == -7 and out1[0] == s.a and out1[1] == s.c 			and _v.visible_enemy_ships(7, out2) == 0 and _v.visible_enemy_ships(-1, out2) == 0 			and _v.visible_enemy_ships(8, out2) == 0 and out2[0] == -7


func _flight() -> void:
	var s: SimViewScene = _s
	var rp: Vector3 = _v.pos(s.rocket)
	_t(&"incoming_rockets", _v.incoming_rockets(s.a) == 1 and _v.incoming_rockets(s.b) == 0)
	_t(&"projectiles_near", _same(_v.projectiles_near(rp, 30.0, 1 << 1), [s.rocket]) and _v.projectiles_near(rp, 30.0, 1 << 0).is_empty())
	_t(&"nearest_friendly_pad", _v.nearest_friendly_pad(s.a) == s.pad and _v.nearest_friendly_pad(s.b) == 0)
	_t(&"path_grid_version", _v.path_grid_version(0) == 0)


func _docking_and_orders() -> void:
	var s: SimViewScene = _s
	_t(&"dock_state", _v.dock_state(s.c) == 2 and _v.dock_state(s.a) == 0 and _v.dock_state(s.dead) == 0)   # 2 DOCKED
	_t(&"service_state", _v.service_state(s.c) == 1 and _v.service_state(s.a) == 0 and _v.service_state(s.dead) == 0)   # 1 DOCKED
	_t(&"pad_occupant", _v.pad_occupant(s.pad) == s.c and _v.pad_occupant(s.core) == 0 and _v.pad_occupant(s.dead) == 0)
	_t(&"service_progress", _v.service_progress(s.c) == Vector3.ZERO)
	_t(&"pad_queue", _v.pad_queue(s.pad).is_empty())
	var head: OrderSpec = _v.order_head(s.a)
	_t(&"order_head", head != null and head.kind == OrderSpec.Kind.MOVE and head.point.is_equal_approx(SimViewScene.MOVE_POINT)
			and _v.order_head(s.b) == null and _v.order_head(s.dead) == null)
	_t(&"order_issuer", _v.order_issuer(s.a) == 0 and _v.order_issuer(s.b) == -1 and _v.order_issuer(s.dead) == -1)
	_t(&"pending_order", _v.pending_order(s.a) == null and _v.pending_order(s.dead) == null)
	_t(&"production_queue", _v.production_queue(s.yard).is_empty() and _v.production_queue(s.dead).is_empty())
	_t(&"production_progress01", _v.production_progress01(s.yard) == 0.0 and _v.production_progress01(s.dead) == 0.0)


func _team_and_match() -> void:
	var s: SimViewScene = _s
	var eco: EconomyDef = s.content.economy
	var cap: Vector2i = Vector2i.ZERO
	var power: Vector2 = Vector2.ZERO
	for id: int in [s.core, s.pad, s.yard, s.tower]:
		var sd: StructureDef = s.content.structures[_st.def_id[_slot(id)] - DefRanges.STRUCTURE_BASE]
		cap += Vector2i(sd.storage_ore, sd.storage_ice)
		power += Vector2(maxf(sd.power, 0.0), maxf(-sd.power, 0.0))
	var ratio: float = 1.0 if power.y <= 0.0 else minf(power.x / power.y, 1.0)
	_t(&"stockpile", _v.stockpile(0).is_equal_approx(Vector3(float(eco.start_ore * 2), float(eco.start_ice * 2), ratio))   # C2-14
			and _v.stockpile(1).is_equal_approx(Vector3(float(eco.start_ore), float(eco.start_ice), 1.0)) and _v.stockpile(99) == Vector3.ZERO)
	_t(&"stockpile_cap", _v.stockpile_cap(0) == cap and _v.stockpile_cap(1) == Vector2i.ZERO)
	_t(&"power_balance", _v.power_balance(0).is_equal_approx(power) and _v.power_balance(1) == Vector2.ZERO)
	_t(&"tech_available", _v.tech_available(0, WorldTestKit.def_id(&"solar_array")) and _v.tech_available(0, WorldTestKit.def_id(&"outpost"))
			and not _v.tech_available(1, WorldTestKit.def_id(&"solar_array")))
	var harv: int = WorldTestKit.def_id(&"harvester")
	_t(&"auto_replenish_target", _v.auto_replenish_target(0, harv) == 2 and _v.auto_replenish_target(0, WorldTestKit.def_id(&"dart")) == 0
			and _v.auto_replenish_target(1, harv) == 0)
	_t(&"field_remaining", _v.field_remaining(0) == 0)
	_t(&"player_score", _v.player_score(0) == Vector2i.ZERO)
	var ts: TeamStateView = _v.team_state(0)
	_t(&"team_state", ts != null and ts.team == 0 and ts.ore == eco.start_ore * 2 and ts.ice == eco.start_ice * 2
			and ts.ore_cap == cap.x and ts.ice_cap == cap.y and _near(ts.power_supply, power.x) and _near(ts.power_demand, power.y)
			and _sorted(ts.members) == [0, 2] and ts.flags == 0 and _v.team_state(9) == null)
	var p0: PlayerStateView = _v.player_state(0)
	var p1: PlayerStateView = _v.player_state(1)
	_t(&"player_state", p0 != null and p1 != null and p0.team == 0 and p1.team == 1 and p0.unit_count == 2
			and p0.structure_count == 4 and p1.doctrine == &"vanguard" and p1.connected
			and _v.player_state(2).kind == PlayerTable.KIND_BOT and _v.player_state(9) == null)
	_t(&"match_arc", _v.match_arc() == MatchArc.Arc.OPEN)
	_t(&"match_phase", _v.match_phase() == MatchRules.Phase.PLAYING)
	_t(&"match_clock_s", _near(_v.match_clock_s(), float(s.world.tick()) / SimViewScene.TICK_HZ))


## R0 B.11 A-56: read_poses equals pos / basis element-wise; dead ids write ZERO + identity; returns the alive count.
func _poses() -> void:
	var s: SimViewScene = _s
	var ids: PackedInt32Array = PackedInt32Array([s.a, s.dead, s.rocket, s.b, s.wreck, 0, s.c])
	var p: PackedVector3Array = PackedVector3Array()
	var r: PackedVector4Array = PackedVector4Array()
	var _x: int = p.resize(ids.size())
	var _y: int = r.resize(ids.size())
	p.fill(Vector3.ONE)
	r.fill(Vector4.ONE)
	var n: int = _v.read_poses(ids, p, r)
	var ok: bool = n == 5 and p.size() == ids.size() and r.size() == ids.size()
	for i: int in ids.size():
		var q: Quaternion = _v.basis(ids[i]).get_rotation_quaternion()
		var alive: bool = _v.alive(ids[i])
		ok = ok and p[i].is_equal_approx(_v.pos(ids[i]) if alive else Vector3.ZERO)
		ok = ok and _near(r[i].x, q.x) and _near(r[i].y, q.y) and _near(r[i].z, q.z) and _near(r[i].w, q.w)
	_t(&"read_poses", ok)
