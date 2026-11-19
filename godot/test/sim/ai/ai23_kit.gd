class_name Ai23Kit extends RefCounted
## AI-23 fixtures: the shipped defs plus the AI-14 autopilots (`Ai14Kit`), `ai23_params.json` (the book constants until
## bot_profiles.json carries them) and `ai23_books.json` (six books on the R0 B.6 start kit, 3 doctrines x 2 variants,
## in the 05 s7.3 grammar; AI-24 ships the real ones), the cradle map's feature list, and a 1v1 world on cradle (slots 0
## and 2, 90 degrees apart, O-5) with both players' start kits and a Commander driver.

const PARAMS: String = "res://test/sim/ai/ai23_params.json"
const BOOKS: String = "res://test/sim/ai/ai23_books.json"
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


## Ground point under unit direction `d` (datum height; the planner's own clearance maths is height-free).
static func ground(w: SimWorld, d: Vector3) -> Vector3:
	return w.terrain().surface_point(d.normalized())


## A cradle world with bots on slots 0 (team 0) and 2 (team 1), each with the start kit, Ice nodes marked in the build grid
## (the stand-in for the sim marking them, see the PR), and a driver running the four ship brains and the intel of
## teams 0 and 1; `with_enemy` false leaves slot 2 empty (SC-40).
static func world(seed_value: int = 7, map_id: StringName = &"cradle", with_enemy: bool = true, doctrine0: StringName = &"vanguard", doctrine2: StringName = &"vanguard") -> SimWorld:
	var w: SimWorld = SimWorld.new(content())
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, seed_value, DartKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, doctrine0, PlayerTable.KIND_BOT)
	if with_enemy:
		w.add_player(2, 1, doctrine2, PlayerTable.KIND_BOT)
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


## The driver: Ai14Kit's brains and intel plus a CommanderBrain for each slot in `slots` at difficulty `tier`.
static func driver(w: SimWorld, slots: Array[int], tier: int = 1, map_id: StringName = &"cradle", which: Array[StringName] = []) -> AiDriver:
	var d: AiDriver = Ai14Kit.driver(w)
	var cb: CommanderBrain = commander(map_id)
	d.set_brain(15, cb, true)
	for s: int in slots:
		d.schedule_bot(s, tier)
	return d


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
