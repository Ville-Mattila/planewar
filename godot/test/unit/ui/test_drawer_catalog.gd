extends GdUnitTestSuite
## DrawerCatalog (UX-22; docs/06 s7.5): which defs get a tile. Everything derives from the content defs
## (`buildable`, `produced_at`, `requires`), never from a hand-written class list (UX-20 review lesson).


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func test_sixteen_structure_tiles_and_seven_unit_tiles() -> void:
	assert_int(DrawerCatalog.structure_ids().size()).is_equal(16)
	assert_int(DrawerCatalog.unit_ids().size()).is_equal(7)


func test_structure_tiles_are_exactly_the_buildable_structures() -> void:
	var want: Array[StringName] = []
	for sd: StructureDef in ContentDB.structures:
		if sd.buildable:
			want.append(sd.id)
	assert_array(DrawerCatalog.structure_ids()).contains_exactly_in_any_order(want)
	for id: StringName in [&"core", &"relay_station"]:
		assert_bool(DrawerCatalog.structure_ids().has(id)).is_false()
	assert_bool(DrawerCatalog.structure_ids().has(&"rail_lance")).is_true()          # towers are build tiles too
	assert_bool(DrawerCatalog.structure_ids().has(&"shield_projector")).is_true()


func test_unit_tiles_are_every_def_with_a_factory() -> void:
	var want: Array[StringName] = []
	for sh: ShipDef in ContentDB.ships:
		if sh.produced_at != &"":
			want.append(sh.id)
	for g: GroundUnitDef in ContentDB.ground_units:
		if g.produced_at != &"":
			want.append(g.id)
	assert_array(DrawerCatalog.unit_ids()).contains_exactly_in_any_order(want)
	assert_array(DrawerCatalog.unit_ids().slice(0, 5)).contains_exactly([&"dart", &"lancer", &"bomber", &"scout", &"hauler"])


func test_factory_of_comes_from_produced_at_and_is_a_structure() -> void:
	for id: StringName in DrawerCatalog.unit_ids():
		var f: StringName = DrawerCatalog.factory_of(id)
		assert_bool(DrawerCatalog.is_factory(f)).is_true()
		for r: String in DrawerCatalog.requires(id):
			assert_bool(ContentDB.def_index(StringName(r)) >= DefRanges.STRUCTURE_BASE).is_true()   # tech is structures; the factory itself is checked separately
	assert_str(String(DrawerCatalog.factory_of(&"dart"))).is_equal("shipyard")
	assert_str(String(DrawerCatalog.factory_of(&"harvester"))).is_equal("vehicle_bay")
	assert_bool(DrawerCatalog.is_factory(&"hangar")).is_false()
	assert_str(String(DrawerCatalog.factory_of(&"refinery"))).is_equal("")


func test_cost_and_requires_read_the_defs() -> void:
	assert_vector(DrawerCatalog.cost(&"dart")).is_equal(Vector2i(150, 0))
	assert_vector(DrawerCatalog.cost(&"bomber")).is_equal(Vector2i(450, 50))
	assert_vector(DrawerCatalog.cost(&"rail_lance")).is_equal(Vector2i(900, 100))
	assert_array(DrawerCatalog.requires(&"hangar")).contains_exactly_in_any_order(["pad", "shipyard"])
	assert_int(DrawerCatalog.max_per_player(&"shipyard")).is_equal(3)
	assert_int(DrawerCatalog.max_per_player(&"dart")).is_equal(0)


func test_costs_follow_the_doctrine_resolved_defs() -> void:
	for d: DoctrineDef in ContentDB.doctrines:
		var rd: ResolvedDefs = ContentDB.resolve_for_doctrine(d.id)
		for id: StringName in DrawerCatalog.structure_ids() + DrawerCatalog.unit_ids():
			var di: int = ContentDB.def_index(id)
			var want: Vector2i = Vector2i(-1, -1)
			if rd.ship(di) != null:
				want = Vector2i(rd.ship(di).cost_ore, rd.ship(di).cost_ice)
			elif rd.ground_unit(di) != null:
				want = Vector2i(rd.ground_unit(di).cost_ore, rd.ground_unit(di).cost_ice)
			else:
				want = Vector2i(rd.structure(di).cost_ore, rd.structure(di).cost_ice)
			assert_vector(DrawerCatalog.cost(id, d.id)).is_equal(want)


func test_every_tile_has_an_english_name_key() -> void:
	for id: StringName in DrawerCatalog.structure_ids() + DrawerCatalog.unit_ids():
		var key: String = DrawerCatalog.name_key(id)
		assert_str(key).is_equal("ui.prod.def.%s" % id)
		assert_bool(JSON.parse_string(FileAccess.get_file_as_string("res://content/locale/en.json")).has(key)).is_true()
