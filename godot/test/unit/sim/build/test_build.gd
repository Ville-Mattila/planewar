extends GdUnitTestSuite
## Build.can_place (TA-19; 02 s6.2, R0 C2-12): one fixture per Reject, cross-edge and corner footprints, Outpost
## presence / spacing, rotation, determinism. Cells are the 1024 build grid; metres along +Y from the face-0 centre.

const R: float = Sphere.PLANET_RADIUS
const N: int = Sphere.GRID_BUILD

var _content: ContentSet
var _defs: WorldDefs
var _store: EntityStore
var _players: PlayerTable
var _rules: MatchRules
var _b: Build


func before_test() -> void:
	_content = WorldTestKit.content()
	_defs = WorldDefs.new(_content)
	_store = EntityStore.new()
	_players = PlayerTable.new()
	_rules = WorldTestKit.rules()
	_players.active[0] = 1
	_players.team[0] = 0
	_players.active[1] = 1
	_players.team[1] = 1
	_players.team_ore[0] = 100000
	_players.team_ice[0] = 100000
	_b = Build.new(_defs, _store, _players, Terrain.new(), _rules)
	var _c: int = _spawn(&"core", 0, _dir(0.0), 0.0)
	var _e: int = _spawn(&"core", 1, Vector3(-1, 0, 0), 0.0)


func _dir(metres: float) -> Vector3:
	var a: float = metres / R
	return Vector3(cos(a), sin(a), 0.0)


func _def(id: StringName) -> int:
	var d: int = _content.entity_index[id]
	return d


func _spawn(id: StringName, team: int, dir: Vector3, alt: float, building: bool = false) -> int:
	var s: int = EntityId.slot(_store.alloc(_store_kind(id), 0))
	_store.def_id[s] = _def(id)
	_store.team[s] = team
	_store.owner[s] = team
	_store.pos[s] = dir * (R + alt)
	if building:
		_store.flags[s] |= EntityStore.F_BUILDING
	return s


func _store_kind(id: StringName) -> int:
	return _defs.entity_kind(_def(id))


func _cell(metres: float) -> int:
	return Sphere.cell_of(_dir(metres), N)


func _place(id: StringName, metres: float, rot: int = 0) -> Build.Reject:
	return _b.can_place(0, _def(id), _cell(metres), rot)


func test_ok_pylon_inside_core_radius() -> void:
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.OK)


func test_eliminated() -> void:
	_players.eliminated[0] = 1
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.ELIMINATED)


func test_prereq_missing_structure() -> void:
	assert_int(_place(&"outpost", 1000.0)).is_equal(Build.Reject.PREREQ)


## GD-16 / 02 s6.2 rule 1: the prerequisite is team-wide and alive: a teammate's finished structure counts, an enemy's,
## an unfinished site and a dead one do not (B1).
func test_prereq_is_team_wide_alive_and_finished() -> void:
	_players.active[2] = 1
	_players.team[2] = 0
	var site: int = _spawn(&"shipyard", 0, _dir(100.0), 0.0, true)
	assert_int(_place(&"outpost", 300.0)).is_equal(Build.Reject.PREREQ)            # a site is not a Shipyard
	var _en: int = _spawn(&"shipyard", 1, _dir(5000.0), 0.0)
	assert_int(_place(&"outpost", 300.0)).is_equal(Build.Reject.PREREQ)            # an enemy Shipyard is not ours
	var mate: int = _spawn(&"shipyard", 0, _dir(150.0), 0.0)
	_store.owner[mate] = 2                                                         # owned by a teammate
	assert_int(_place(&"outpost", 300.0)).is_not_equal(Build.Reject.PREREQ)        # team-wide
	var _freed: bool = _store.free_slot(mate, 0)
	assert_int(_place(&"outpost", 300.0)).is_equal(Build.Reject.PREREQ)            # dead again
	_store.flags[site] &= ~EntityStore.F_BUILDING
	assert_int(_place(&"outpost", 300.0)).is_not_equal(Build.Reject.PREREQ)        # finished


func test_prereq_unbuildable_def() -> void:
	assert_int(_place(&"core", 300.0)).is_equal(Build.Reject.PREREQ)


func test_cap_structure_cap_and_max_per_player() -> void:
	_rules.caps.structures = 1
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.CAP)
	_rules.caps.structures = 60
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.OK)
	var def: StructureDef = _defs.base.structure(_def(&"relay_pylon"))
	for i: int in def.max_per_player:
		var _p: int = _spawn(&"relay_pylon", 0, _dir(100.0 + float(i)), 0.0)
	_rules.caps.structures = 1000
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.CAP)


func test_occupied() -> void:
	_b.grid.occupy(_b.footprint_cells(_def(&"relay_pylon"), _cell(300.0), 0))
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.OCCUPIED)


func test_slope_over_15_degrees() -> void:
	_b.grid.set_slope_deg(_cell(300.0), 15.5)
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.SLOPE)
	_b.grid.set_slope_deg(_cell(300.0), 15.0)
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.OK)


func test_node_blocks_and_cold_trap_admits_extractor() -> void:
	var _r: int = _spawn(&"refinery", 0, _dir(100.0), 0.0)
	_b.grid.mark_node(_cell(300.0), false)
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.NODE)
	assert_int(_place(&"ice_extractor", 300.0)).is_equal(Build.Reject.NODE)
	_b.grid.mark_node(_cell(400.0), true)
	assert_int(_place(&"ice_extractor", 400.0)).is_equal(Build.Reject.OK)
	assert_int(_place(&"relay_pylon", 400.0)).is_equal(Build.Reject.NODE)
	assert_int(_place(&"ice_extractor", 500.0)).is_equal(Build.Reject.NODE)


func test_not_visible() -> void:
	assert_int(_place(&"relay_pylon", 3000.0)).is_equal(Build.Reject.NOT_VISIBLE)


func test_enemy_radius() -> void:
	var _e: int = _spawn(&"relay_pylon", 1, _dir(400.0), 0.0)
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.ENEMY_RADIUS)


func test_not_visible_wins_over_enemy_radius() -> void:
	var _e: int = _spawn(&"relay_pylon", 1, _dir(3000.0), 0.0)
	assert_int(_place(&"relay_pylon", 3000.0)).is_equal(Build.Reject.NOT_VISIBLE)


func test_ice_extractor_on_cold_trap_rejects_overlapping_ore_node() -> void:
	var _r: int = _spawn(&"refinery", 0, _dir(100.0), 0.0)
	var cell: int = _cell(400.0)
	_b.grid.mark_node(cell, true)
	_b.grid.mark_node(Sphere.neighbour_cell(cell, N, Sphere.DIR_POS_U), false)
	assert_int(_b.can_place(0, _def(&"ice_extractor"), cell, 0)).is_equal(Build.Reject.NODE)


func test_no_radius() -> void:
	assert_int(_place(&"relay_pylon", 1000.0)).is_equal(Build.Reject.NO_RADIUS)


func test_outpost_presence_and_spacing() -> void:
	var _y: int = _spawn(&"shipyard", 0, _dir(-200.0), 0.0)
	assert_int(_place(&"outpost", 1000.0)).is_equal(Build.Reject.NO_PRESENCE)
	var d: int = _spawn(&"dart", 0, _dir(1000.0), 100.0)
	assert_int(_place(&"outpost", 1000.0)).is_equal(Build.Reject.OK)
	_store.pos[d] = _dir(1000.0) * (R + 350.0)
	assert_int(_place(&"outpost", 1000.0)).is_equal(Build.Reject.NO_PRESENCE)
	_store.pos[d] = _dir(700.0) * (R + 50.0)
	assert_int(_place(&"outpost", 700.0)).is_equal(Build.Reject.SPACING)   # < 800 m from the friendly Core


func test_outpost_enemy_spacing() -> void:
	var _y: int = _spawn(&"shipyard", 0, _dir(-200.0), 0.0)
	var _d: int = _spawn(&"dart", 0, _dir(1000.0), 100.0)
	var eo: int = _spawn(&"outpost", 1, _dir(2400.0), 0.0)
	assert_int(_place(&"outpost", 1000.0)).is_equal(Build.Reject.SPACING)   # 1,400 m < 1,500 m
	_store.pos[eo] = _dir(2600.0) * R
	assert_int(_place(&"outpost", 1000.0)).is_equal(Build.Reject.OK)         # 1,600 m


func test_funds() -> void:
	_players.team_ore[0] = 10
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.FUNDS)


func test_spend_locked_until_two_minutes() -> void:
	_players.active[2] = 1
	_players.team[2] = 0
	var _r: int = _spawn(&"core", 0, _dir(100.0), 0.0)
	var cost: int = _defs.base.structure(_def(&"relay_pylon")).cost_ore
	_b.spent_ore[0] = 800 - cost + 1
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.SPEND_LOCKED)
	_b.delivered_ore[0] = 1
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.OK)
	_b.delivered_ore[0] = 0
	_b.set_clock(int(_defs.economy.early_share_lock_s) * _rules.tick_hz)
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.OK)


func test_footprint_across_face_edge_accepted() -> void:
	var edge: int = (0 * N + 512) * N + (N - 1)   # face 0, last column: the +u cube edge
	var _c: int = _spawn(&"core", 0, Sphere.cell_center_dir(edge, N), 0.0)
	var cells: PackedInt32Array = _b.footprint_cells(_def(&"solar_array"), edge, 0)
	assert_int(cells.size()).is_equal(16)
	var faces: Dictionary = {}
	for c: int in cells:
		faces[Sphere.cell_face(c, N)] = true
	assert_int(faces.size()).is_equal(2)
	assert_int(_b.can_place(0, _def(&"solar_array"), edge, 0)).is_equal(Build.Reject.OK)
	var big: PackedInt32Array = _b.footprint_cells(_def(&"shipyard"), edge, 1)
	assert_int(big.size()).is_equal(48)
	_assert_compact(big, 9.5 * 9.0)


func test_footprint_at_cube_corner() -> void:
	var corner: int = (0 * N + (N - 1)) * N + (N - 1)
	var cells: PackedInt32Array = _b.footprint_cells(_def(&"solar_array"), corner, 0)
	assert_int(cells.size()).is_equal(15)
	var faces: Dictionary = {}
	for c: int in cells:
		faces[Sphere.cell_face(c, N)] = true
	assert_int(faces.size()).is_equal(3)
	_assert_compact(cells, 9.5 * 5.0)


func _assert_compact(cells: PackedInt32Array, max_m: float) -> void:
	var seen: Dictionary = {}
	var d0: Vector3 = Sphere.cell_center_dir(cells[0], N)
	for c: int in cells:
		assert_bool(seen.has(c)).is_false()
		seen[c] = true
		assert_float(Sphere.great_circle(d0, Sphere.cell_center_dir(c, N))).is_less(max_m)


func test_rotation_swaps_extents() -> void:
	var c: int = _cell(300.0)
	var sy: int = _def(&"shipyard")
	var r0: PackedInt32Array = _b.footprint_cells(sy, c, 0).duplicate()
	var r1: PackedInt32Array = _b.footprint_cells(sy, c, 1).duplicate()
	var r2: PackedInt32Array = _b.footprint_cells(sy, c, 2).duplicate()
	assert_int(r0.size()).is_equal(48)
	assert_int(r1.size()).is_equal(48)
	assert_bool(r0 == r1).is_false()
	assert_int(_span(r0, true)).is_equal(8)
	assert_int(_span(r0, false)).is_equal(6)
	assert_int(_span(r1, true)).is_equal(6)
	assert_int(_span(r1, false)).is_equal(8)
	assert_int(_span(r2, true)).is_equal(8)


func _span(cells: PackedInt32Array, use_i: bool) -> int:
	var lo: int = 1 << 30
	var hi: int = -1
	for c: int in cells:
		var v: int = Sphere.cell_i(c, N) if use_i else Sphere.cell_j(c, N)
		lo = mini(lo, v)
		hi = maxi(hi, v)
	return hi - lo + 1


func test_deterministic() -> void:
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	for m: float in [-300.0, 100.0, 300.0, 450.0, 1000.0, 3000.0]:
		var _x: bool = a.push_back(_place(&"relay_pylon", m))
	var first: Build = _b
	before_test()   # a second, independent store / grid / Build
	assert_bool(first != _b).is_true()
	for m: float in [-300.0, 100.0, 300.0, 450.0, 1000.0, 3000.0]:
		var _y: bool = b.push_back(_place(&"relay_pylon", m))
	assert_bool(a == b).is_true()


func test_place_reserves_footprint() -> void:
	var id: int = _b.place(0, _def(&"relay_pylon"), _cell(300.0), 0)
	assert_bool(id != 0).is_true()
	assert_int(_place(&"relay_pylon", 300.0)).is_equal(Build.Reject.OCCUPIED)
	assert_int(_b.place(0, _def(&"relay_pylon"), _cell(300.0), 0)).is_equal(0)
