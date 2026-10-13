extends GdUnitTestSuite
## N2 def_id ranges and the A-1 per-file namespaces (weapon `bomb` and projectile `bomb` coexist).


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func test_kind_of_is_pure_range_arithmetic() -> void:
	assert_int(ContentDB.kind_of(0)).is_equal(ContentDB.K_SHIP)
	assert_int(ContentDB.kind_of(255)).is_equal(ContentDB.K_SHIP)
	assert_int(ContentDB.kind_of(256)).is_equal(ContentDB.K_GROUND)
	assert_int(ContentDB.kind_of(511)).is_equal(ContentDB.K_GROUND)
	assert_int(ContentDB.kind_of(512)).is_equal(ContentDB.K_STRUCTURE)
	assert_int(ContentDB.kind_of(1023)).is_equal(ContentDB.K_STRUCTURE)
	assert_int(ContentDB.kind_of(1024)).is_equal(ContentDB.K_WEAPON)
	assert_int(ContentDB.kind_of(1279)).is_equal(ContentDB.K_WEAPON)
	assert_int(ContentDB.kind_of(1280)).is_equal(ContentDB.K_PROJECTILE)
	assert_int(ContentDB.kind_of(1535)).is_equal(ContentDB.K_PROJECTILE)
	assert_int(ContentDB.kind_of(1536)).is_equal(DefRanges.K_NONE)
	assert_int(ContentDB.kind_of(-1)).is_equal(DefRanges.K_NONE)


func test_def_index_resolves_entity_ranges_in_file_order() -> void:
	assert_int(ContentDB.def_index(&"dart")).is_equal(0)
	assert_int(ContentDB.def_index(&"lancer")).is_equal(1)
	assert_int(ContentDB.def_index(&"harvester")).is_equal(256)
	assert_int(ContentDB.def_index(&"siege_crawler")).is_equal(257)
	assert_int(ContentDB.def_index(&"core")).is_equal(512)
	# towers continue after the 13 structures
	assert_int(ContentDB.def_index(&"autocannon_turret")).is_equal(512 + 13)
	assert_int(ContentDB.def_index(&"nope")).is_equal(-1)


func test_every_entity_id_round_trips_through_its_accessor() -> void:
	for s: ShipDef in ContentDB.ships:
		assert_int(ContentDB.kind_of(s.def_id)).is_equal(ContentDB.K_SHIP)
		assert_object(ContentDB.ship(ContentDB.def_index(s.id))).is_same(s)
	for g: GroundUnitDef in ContentDB.ground_units:
		assert_object(ContentDB.ground_unit(ContentDB.def_index(g.id))).is_same(g)
	for st: StructureDef in ContentDB.structures:
		assert_int(ContentDB.kind_of(st.def_id)).is_equal(ContentDB.K_STRUCTURE)
		assert_object(ContentDB.structure(ContentDB.def_index(st.id))).is_same(st)
	assert_object(ContentDB.ship(-1)).is_null()
	assert_object(ContentDB.ship(99)).is_null()
	assert_object(ContentDB.structure(ContentDB.def_index(&"dart"))).is_null()


func test_bomb_is_both_a_weapon_and_a_projectile() -> void:
	var w: int = ContentDB.weapon_index(&"bomb")
	var p: int = ContentDB.projectile_index(&"bomb")
	assert_int(ContentDB.kind_of(w)).is_equal(ContentDB.K_WEAPON)
	assert_int(ContentDB.kind_of(p)).is_equal(ContentDB.K_PROJECTILE)
	assert_str(String(ContentDB.weapon(w).id)).is_equal("bomb")
	assert_str(String(ContentDB.projectile(p).id)).is_equal("bomb")
	assert_str(String(ContentDB.weapon(w).projectile)).is_equal("bomb")
	# def_index searches the entity ranges only
	assert_int(ContentDB.def_index(&"bomb")).is_equal(-1)
	assert_int(ContentDB.weapon_index(&"slug_light")).is_equal(-1)
	assert_int(ContentDB.projectile_index(&"gun_dart")).is_equal(-1)


func test_weapon_projectile_links_resolve_through_projectile_index() -> void:
	for w: WeaponDef in ContentDB.weapons:
		assert_int(ContentDB.projectile_index(w.projectile)).is_greater_equal(DefRanges.PROJECTILE_BASE)


func test_tower_block_and_flags() -> void:
	var t: StructureDef = ContentDB.structure(ContentDB.def_index(&"autocannon_turret"))
	assert_bool(t.is_tower()).is_true()
	assert_str(String(t.tower["weapon"])).is_equal("gun_turret")
	assert_bool(ContentDB.structure(ContentDB.def_index(&"core")).is_tower()).is_false()
	assert_int(ContentDB.structure(ContentDB.def_index(&"core")).footprint[0]).is_equal(8)
