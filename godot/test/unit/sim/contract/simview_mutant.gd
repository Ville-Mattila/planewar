class_name SimViewMutant extends SimView
## A SimView that forwards to a real one and corrupts exactly one accessor (TEST-02 "one failing fixture per
## accessor"): `broken` names it; the corrupted answer differs from the real one for every argument, so a contract
## clause that exercises the accessor must fail. Generated one override per `SimView` method; the test
## `test_contract_covers_every_simview_accessor` fails if SimView gains a method this class lacks.

var _inner: SimView
var broken: StringName = &""


func _init(inner: SimView, broken_accessor: StringName) -> void:
	_inner = inner
	broken = broken_accessor


func alive(_id: int) -> bool:
	return _b(&"alive", _inner.alive(_id))


func pos(_id: int) -> Vector3:
	return _v3(&"pos", _inner.pos(_id))


func vel(_id: int) -> Vector3:
	return _v3(&"vel", _inner.vel(_id))


func basis(_id: int) -> Basis:
	return _bs(&"basis", _inner.basis(_id))


func def_id(_id: int) -> int:
	return _i(&"def_id", _inner.def_id(_id))


func owner(_id: int) -> int:
	return _i(&"owner", _inner.owner(_id))


func team(_id: int) -> int:
	return _i(&"team", _inner.team(_id))


func hp01(_id: int) -> float:
	return _f(&"hp01", _inner.hp01(_id))


func fuel01(_id: int) -> float:
	return _f(&"fuel01", _inner.fuel01(_id))


func ammo(_id: int) -> int:
	return _i(&"ammo", _inner.ammo(_id))


func bombs(_id: int) -> int:
	return _i(&"bombs", _inner.bombs(_id))


func control_state(_id: int) -> int:
	return _i(&"control_state", _inner.control_state(_id))


func possessor(_id: int) -> int:
	return _i(&"possessor", _inner.possessor(_id))


func ids_in_cell(_cell: int) -> PackedInt32Array:
	return _pia(&"ids_in_cell", _inner.ids_in_cell(_cell))


func ids_near(_p: Vector3, _radius: float, _mask: int) -> PackedInt32Array:
	return _pia(&"ids_near", _inner.ids_near(_p, _radius, _mask))


func stockpile(_team: int) -> Vector3:
	return _v3(&"stockpile", _inner.stockpile(_team))


func visible_to(_team: int, _id: int) -> bool:
	return _b(&"visible_to", _inner.visible_to(_team, _id))


func tick() -> int:
	return _i(&"tick", _inner.tick())


func visible_ids(_team: int) -> PackedInt32Array:
	return _pia(&"visible_ids", _inner.visible_ids(_team))


func ships() -> PackedInt32Array:
	return _pia(&"ships", _inner.ships())


func structures() -> PackedInt32Array:
	return _pia(&"structures", _inner.structures())


func wrecks() -> PackedInt32Array:
	return _pia(&"wrecks", _inner.wrecks())


func flags(_id: int) -> int:
	return _i(&"flags", _inner.flags(_id))


func radius(_id: int) -> float:
	return _f(&"radius", _inner.radius(_id))


func def_kind(_id: int) -> int:
	return _i(&"def_kind", _inner.def_kind(_id))


func cargo(_id: int) -> float:
	return _f(&"cargo", _inner.cargo(_id))


func cargo_kind(_id: int) -> int:
	return _i(&"cargo_kind", _inner.cargo_kind(_id))


func link(_id: int) -> int:
	return _i(&"link", _inner.link(_id))


func boost_state(_id: int) -> int:
	return _i(&"boost_state", _inner.boost_state(_id))


func flip_cooldown01(_id: int) -> float:
	return _f(&"flip_cooldown01", _inner.flip_cooldown01(_id))


func rockets(_id: int) -> int:
	return _i(&"rockets", _inner.rockets(_id))


func dock_state(_id: int) -> int:
	return _i(&"dock_state", _inner.dock_state(_id))


func service_progress(_id: int) -> Vector3:
	return _v3(&"service_progress", _inner.service_progress(_id))


func service_state(_id: int) -> int:
	return _i(&"service_state", _inner.service_state(_id))


func pad_queue(_pad: int) -> PackedInt32Array:
	return _pia(&"pad_queue", _inner.pad_queue(_pad))


func pad_occupant(_pad: int) -> int:
	return _i(&"pad_occupant", _inner.pad_occupant(_pad))


func nearest_friendly_pad(_id: int) -> int:
	return _i(&"nearest_friendly_pad", _inner.nearest_friendly_pad(_id))


func order_head(_id: int) -> OrderSpec:
	return _os(&"order_head", _inner.order_head(_id))


func order_issuer(_id: int) -> int:
	return _i(&"order_issuer", _inner.order_issuer(_id))


func pending_order(_id: int) -> OrderSpec:
	return _os(&"pending_order", _inner.pending_order(_id))


func incoming_rockets(_id: int) -> int:
	return _i(&"incoming_rockets", _inner.incoming_rockets(_id))


func projectiles_near(_p: Vector3, _r: float, _team_mask: int) -> PackedInt32Array:
	return _pia(&"projectiles_near", _inner.projectiles_near(_p, _r, _team_mask))


func ai_tag(_id: int) -> int:
	return _i(&"ai_tag", _inner.ai_tag(_id))


func field_remaining(_node: int) -> int:
	return _i(&"field_remaining", _inner.field_remaining(_node))


func path_grid_version(_face: int) -> int:
	return _i(&"path_grid_version", _inner.path_grid_version(_face))


func stockpile_cap(_team: int) -> Vector2i:
	return _v2i(&"stockpile_cap", _inner.stockpile_cap(_team))


func power_balance(_team: int) -> Vector2:
	return _v2(&"power_balance", _inner.power_balance(_team))


func unit_count(_player: int) -> int:
	return _i(&"unit_count", _inner.unit_count(_player))


func supply01(_id: int) -> float:
	return _f(&"supply01", _inner.supply01(_id))


func production_queue(_factory: int) -> PackedInt32Array:
	return _pia(&"production_queue", _inner.production_queue(_factory))


func production_progress01(_factory: int) -> float:
	return _f(&"production_progress01", _inner.production_progress01(_factory))


func tech_available(_team: int, _def_id: int) -> bool:
	return _b(&"tech_available", _inner.tech_available(_team, _def_id))


func auto_replenish_target(_player: int, _def_id: int) -> int:
	return _i(&"auto_replenish_target", _inner.auto_replenish_target(_player, _def_id))


func player_score(_slot: int) -> Vector2i:
	return _v2i(&"player_score", _inner.player_score(_slot))


func landing_grade_last(_id: int) -> int:
	return _i(&"landing_grade_last", _inner.landing_grade_last(_id))


func team_state(_team: int) -> TeamStateView:
	return _ts(&"team_state", _inner.team_state(_team))


func player_state(_slot: int) -> PlayerStateView:
	return _ps(&"player_state", _inner.player_state(_slot))


func terrain_height(_dir: Vector3) -> float:
	return _f(&"terrain_height", _inner.terrain_height(_dir))


func match_arc() -> int:
	return _i(&"match_arc", _inner.match_arc())


func match_phase() -> int:
	return _i(&"match_phase", _inner.match_phase())


func match_clock_s() -> float:
	return _f(&"match_clock_s", _inner.match_clock_s())


func read_poses(ids: PackedInt32Array, _pos: PackedVector3Array, _rot: PackedVector4Array) -> int:
	var n: int = _inner.read_poses(ids, _pos, _rot)
	if broken == &"read_poses" and not _pos.is_empty():
		_pos[0] += Vector3.ONE
		_rot[_rot.size() - 1] += Vector4(0.0, 0.0, 0.0, 0.5)
	return n


func _b(n: StringName, v: bool) -> bool:
	return not v if n == broken else v


func _i(n: StringName, v: int) -> int:
	return v + 1 if n == broken else v


func _f(n: StringName, v: float) -> float:
	return v + 0.25 if n == broken else v


func _v3(n: StringName, v: Vector3) -> Vector3:
	return v + Vector3(1.0, 2.0, 3.0) if n == broken else v


func _v2(n: StringName, v: Vector2) -> Vector2:
	return v + Vector2(1.0, 2.0) if n == broken else v


func _v2i(n: StringName, v: Vector2i) -> Vector2i:
	return v + Vector2i(1, 2) if n == broken else v


func _bs(n: StringName, v: Basis) -> Basis:
	return Basis(Vector3.UP, 0.5) * v if n == broken else v


func _pia(n: StringName, v: PackedInt32Array) -> PackedInt32Array:
	if n != broken:
		return v
	var out: PackedInt32Array = v.duplicate()
	var _a: bool = out.push_back(987654)
	return out


func _os(n: StringName, v: OrderSpec) -> OrderSpec:
	if n != broken:
		return v
	var out: OrderSpec = OrderSpec.make(OrderSpec.Kind.HOLD)
	if v != null:
		out.kind = OrderSpec.Kind.GUARD if v.kind == OrderSpec.Kind.HOLD else OrderSpec.Kind.HOLD
		out.point = v.point
	return out


func _ts(n: StringName, v: TeamStateView) -> TeamStateView:
	if n != broken:
		return v
	var out: TeamStateView = TeamStateView.new()
	if v != null:
		out.team = v.team
		out.ore = v.ore
		out.ice = v.ice
		out.members = v.members
	out.ore += 1
	return out


func _ps(n: StringName, v: PlayerStateView) -> PlayerStateView:
	if n != broken:
		return v
	var out: PlayerStateView = PlayerStateView.new()
	if v != null:
		out.team = v.team
		out.kind = v.kind
		out.unit_count = v.unit_count
	out.unit_count += 1
	out.team += 1
	return out
