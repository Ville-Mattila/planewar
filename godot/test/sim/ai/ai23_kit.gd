class_name Ai23Kit extends RefCounted
## AI-23 fixtures: the shipped defs plus the AI-14 autopilots (`Ai14Kit`), `ai23_params.json` (the book constants until
## bot_profiles.json carries them) and `ai23_books.json` (six books on the R0 B.6 start kit, 3 doctrines x 2 variants,
## in the 05 s7.3 grammar; AI-24 ships the real ones), the cradle map's feature list, and a 1v1 world on cradle (slots 0
## and 2, 90 degrees apart, O-5; the cradle's baked terrain since BUG-3, its start slots, Ore Fields and Cold Traps) with both players' start kits and a Commander driver.

const PARAMS: String = "res://test/sim/ai/ai23_params.json"
const BOOKS: String = "res://test/sim/ai/ai23_books.json"
const SHIPPED: String = "res://content/defs/build_orders.json"   # AI-24: the books the game ships; SC-41 runs these
const MAPS: String = "res://content/maps/"
const HZ: int = 30

static var _params: BookParams = null
static var _books: Array[OpeningBook] = []
static var _raw_books: Array = []


static func content() -> ContentSet:
	return Ai14Kit.content()


static func def(id: StringName) -> int:
	return int(content().entity_index.get(id, -1))


static func params() -> BookParams:
	if _params == null:
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS))
		assert(v is Dictionary, "ai23_params.json must parse")
		_params = BookParams.from_dict(v)
		assert(_params != null, "ai23_params.json must carry every BookParams key")
	return _params


static func raw_books() -> Array:
	if _raw_books.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOKS))
		assert(v is Dictionary, "ai23_books.json must parse")
		var d: Dictionary = v
		_raw_books = d["build_orders"]
	return _raw_books


static func books() -> Array[OpeningBook]:
	if _books.is_empty():
		for e: Variant in raw_books():
			var errs: Array[String] = []
			var b: OpeningBook = OpeningBook.compile(e, content(), errs)
			assert(b != null, "book %s: %s" % [str((e as Dictionary).get("id", "?")), str(errs)])
			_books.append(b)
	return _books


## The shipped books (content/defs/build_orders.json, AI-24) compiled against the shipped defs.
static func shipped_books() -> Array[OpeningBook]:
	var out: Array[OpeningBook] = []
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED))
	assert(v is Dictionary, "build_orders.json must parse")
	for e: Variant in (v as Dictionary)["build_orders"]:
		var errs: Array[String] = []
		var b: OpeningBook = OpeningBook.compile(e, content(), errs)
		assert(b != null, "book %s: %s" % [str((e as Dictionary).get("id", "?")), str(errs)])
		out.append(b)
	return out


static func book(id: StringName) -> OpeningBook:
	for b: OpeningBook in books():
		if b.id == id:
			return b
	return null


static func features(map_id: StringName = &"cradle") -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAPS + String(map_id) + "/features.json"))
	assert(v is Dictionary, "features.json must parse")
	return v


static func sites(map_id: StringName = &"cradle") -> MapSites:
	var s: MapSites = MapSites.from_features(features(map_id))
	assert(s != null, "features.json must carry start_slots")
	return s


static func planner(map_id: StringName = &"cradle") -> BuildPlanner:
	return BuildPlanner.new(content(), params(), sites(map_id))


## Ground point under unit direction `d` (the terrain height; the planner's own clearance maths is height-free).
static func ground(w: SimWorld, d: Vector3) -> Vector3:
	return w.terrain().surface_point(d.normalized())


## A cradle world with bots on slots 0 (team 0) and 2 (team 1), each with the start kit, Ice nodes marked in the build grid
## (the stand-in for the sim marking them, see the PR), and a driver running the four ship brains and the intel of
## teams 0 and 1; `with_enemy` false leaves slot 2 empty (SC-40). `on_terrain` loads the map's baked terrain (BUG-3: the
## start kit stands on the ground; the default since BUG-3); false keeps the flat datum with the map's own geometry.
static func world(seed_value: int = 7, map_id: StringName = &"cradle", with_enemy: bool = true, doctrine0: StringName = &"vanguard", doctrine2: StringName = &"vanguard", on_terrain: bool = true) -> SimWorld:
	var w: SimWorld = SimWorld.new(content())
	var map: MapDef = MapDef.new()
	map.id = map_id if on_terrain else &""
	var res: Result = w.load_map(map, seed_value, DartKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, doctrine0, PlayerTable.KIND_BOT)
	if with_enemy:
		w.add_player(2, 1, doctrine2, PlayerTable.KIND_BOT)
	var _fields: int = w.economy().harvest.fields.load_map_dir(MAPS + String(map_id))
	var _traps: int = w.economy().ice.nodes.load_map_dir(MAPS + String(map_id))
	var f: Dictionary = features(map_id)
	for slot: int in ([0, 2] if with_enemy else [0]):
		var dir: Vector3 = _vec(((f["start_slots"] as Array)[slot] as Dictionary)["dir"])
		var toward: Vector3 = Vector3.ZERO
		for n: Variant in f["nodes"]:
			var nd: Dictionary = n
			if nd["kind"] == "ore_field" and int(nd["slot"]) == slot and toward == Vector3.ZERO:
				toward = _vec(nd["dir"])
		assert(w.spawn_start_kit(slot, dir, toward), "start kit of slot %d" % slot)
	for n: Variant in f["nodes"]:
		var nd: Dictionary = n
		if nd["kind"] == "cold_trap":
			w.economy().build.grid.mark_node(Sphere.cell_of(_vec(nd["dir"]), Sphere.GRID_BUILD), true)
	return w


static func _vec(a: Variant) -> Vector3:
	var l: Array = a
	return Vector3(float(l[0]), float(l[1]), float(l[2])).normalized()


## The driver: Ai14Kit's ship brains and intel, the Harvester brain (the start kit's Harvester mines, so the bot has income),
## `cb` as the bot brain and the slots in `slots` scheduled at difficulty `tier`.
static func driver(w: SimWorld, cb: CommanderBrain, slots: Array[int], tier: int = 1) -> AiDriver:
	var d: AiDriver = Ai14Kit.driver(w)
	add_economy(d, w, true)
	d.set_brain(15, cb, true)
	for s: int in slots:
		d.schedule_bot(s, tier)
	return d


## The Harvester class (AI-16) on `d`, its fields bound from `w`; `register` the start kit's Harvesters (they spawned before
## the hook existed).
static func add_economy(d: AiDriver, w: SimWorld, register: bool) -> void:
	var c: ContentSet = Ai16Kit.content()
	var hb: HarvesterBrain = Ai16Kit.brain()
	hb.bind_fields(w.economy().harvest.fields)
	d.set_brain(Ai16Kit.cls(), hb)
	d.set_overlay_params(Ai16Kit.cls(), OverlayParams.for_ground(Ai16Kit.ap(), c.rules, c.rules.tick_hz))
	if register:
		var hid: int = DartKit.def_id(&"harvester")
		for s: int in w.store().ground:
			if w.store().def_id[s] == hid:
				var _r: bool = d.register(w.store().id_of(s), Ai16Kit.cls())


static func commander(map_id: StringName = &"cradle", only: Array[OpeningBook] = []) -> CommanderBrain:
	var cb: CommanderBrain = CommanderBrain.new(content(), params(), sites(map_id), content().rules.tick_hz)
	cb.set_books(only if not only.is_empty() else books())
	return cb


## Steps `n` ticks and drains events; returns them.
static func run(w: SimWorld, n: int) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for _i: int in n:
		w.step()
		out.append_array(w.drain_events())
	return out


## SC-41 (R0 B.33 A-163): step `i` is the `order move` of an Expansion pair (a `build outpost` to the same site follows)
## and its `when` waits on the clock at `ctx`.
static func expansion_waits_on_clock(book: OpeningBook, i: int, ctx: BookContext) -> bool:
	if book.kind_of(i) != OpeningBook.Do.ORDER or book.order_kind_of(i) != OrderSpec.Kind.MOVE or i + 1 >= book.n_steps:
		return false
	var nxt: SiteToken = book.token_of(i + 1)
	if book.kind_of(i + 1) != OpeningBook.Do.BUILD or nxt == null or book.token_of(i) == null or nxt.src != book.token_of(i).src:
		return false
	return book.when_of(i).waits_on_clock(ctx)
