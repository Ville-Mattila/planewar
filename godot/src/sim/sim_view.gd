class_name SimView extends RefCounted
## Read-only view of the simulation (01 s9.4 + 03 s15.4 + R0 C2-05). `LocalSimView` reads the arrays of a local
## `SimWorld`; net's `NetSimView` reads replicated state. Reads stay valid until the next `step()` and never
## allocate except the list getters (S3). This base is abstract: every accessor returns the neutral default
## (false, 0, -1 for "none" slots and ids, zero vectors, empty lists).


func alive(_id: int) -> bool:
	return false


func pos(_id: int) -> Vector3:
	return Vector3.ZERO


func vel(_id: int) -> Vector3:
	return Vector3.ZERO


func basis(_id: int) -> Basis:
	return Basis.IDENTITY


func def_id(_id: int) -> int:
	return -1


func owner(_id: int) -> int:
	return -1


func team(_id: int) -> int:
	return -1


func hp01(_id: int) -> float:
	return 0.0


func fuel01(_id: int) -> float:
	return 0.0


func ammo(_id: int) -> int:
	return 0


func bombs(_id: int) -> int:
	return 0


func control_state(_id: int) -> int:
	return 0


func possessor(_id: int) -> int:
	return -1


func ids_in_cell(_cell: int) -> PackedInt32Array:
	return PackedInt32Array()


func ids_near(_p: Vector3, _radius: float, _mask: int) -> PackedInt32Array:
	return PackedInt32Array()


func stockpile(_team: int) -> Vector3:
	return Vector3.ZERO


func visible_to(_team: int, _id: int) -> bool:
	return false


func tick() -> int:
	return 0


func visible_ids(_team: int) -> PackedInt32Array:
	return PackedInt32Array()


func ships() -> PackedInt32Array:
	return PackedInt32Array()


func structures() -> PackedInt32Array:
	return PackedInt32Array()


func wrecks() -> PackedInt32Array:
	return PackedInt32Array()


func flags(_id: int) -> int:
	return 0


func radius(_id: int) -> float:
	return 0.0


func def_kind(_id: int) -> int:
	return -1


func cargo(_id: int) -> float:
	return 0.0


func cargo_kind(_id: int) -> int:
	return 0


func link(_id: int) -> int:
	return 0


func boost_state(_id: int) -> int:
	return 0


func flip_cooldown01(_id: int) -> float:
	return 0.0


func rockets(_id: int) -> int:
	return 0


func dock_state(_id: int) -> int:
	return 0


func service_progress(_id: int) -> Vector3:
	return Vector3.ZERO


func service_state(_id: int) -> int:
	return 0


func pad_queue(_pad: int) -> PackedInt32Array:
	return PackedInt32Array()


func pad_occupant(_pad: int) -> int:
	return 0


func nearest_friendly_pad(_id: int) -> int:
	return 0


func order_head(_id: int) -> OrderSpec:
	return null


func order_issuer(_id: int) -> int:
	return -1


func pending_order(_id: int) -> OrderSpec:
	return null


func incoming_rockets(_id: int) -> int:
	return 0


func projectiles_near(_p: Vector3, _r: float, _team_mask: int) -> PackedInt32Array:
	return PackedInt32Array()


func ai_tag(_id: int) -> int:
	return 0


func field_remaining(_node: int) -> int:
	return 0


func path_grid_version(_face: int) -> int:
	return 0


func stockpile_cap(_team: int) -> Vector2i:
	return Vector2i.ZERO


func power_balance(_team: int) -> Vector2:
	return Vector2.ZERO


func unit_count(_player: int) -> int:
	return 0


func supply01(_id: int) -> float:
	return 0.0


func production_queue(_factory: int) -> PackedInt32Array:
	return PackedInt32Array()


func production_progress01(_factory: int) -> float:
	return 0.0


func tech_available(_team: int, _def_id: int) -> bool:
	return false


func auto_replenish_target(_player: int, _def_id: int) -> int:
	return 0


func player_score(_slot: int) -> Vector2i:
	return Vector2i.ZERO


func landing_grade_last(_id: int) -> int:
	return -1


func team_state(_team: int) -> TeamStateView:
	return null


func player_state(_slot: int) -> PlayerStateView:
	return null


func terrain_height(_dir: Vector3) -> float:
	return 0.0


func match_arc() -> int:
	return MatchArc.Arc.OPEN


func match_phase() -> int:
	return MatchRules.Phase.PLAYING


func match_clock_s() -> float:
	return 0.0
