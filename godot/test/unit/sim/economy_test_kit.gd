class_name EconomyTestKit extends RefCounted
## Fixtures for the TA-19 tests: a world with one player per team (no early share lock) on the flat datum, with the
## C2-14 start kit laid out for player 0 around +X (Refinery toward +Y, Shipyard toward +Z), plus helpers to place
## sites by metres west of the Core and to run ticks collecting events.

const R: float = Sphere.PLANET_RADIUS


## Players 0 (team 0) and 1 (team 1), both human; `kit` lays out player 0's start kit.
static func solo_world(kit: bool = true, seed_value: int = 7, rules: MatchRules = null) -> SimWorld:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = &""
	var res: Result = w.load_map(map, seed_value, rules if rules != null else WorldTestKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, 1, &"", PlayerTable.KIND_HUMAN)
	if kit:
		assert(w.spawn_start_kit(0, Vector3.RIGHT, Vector3.UP))
	return w


## Build cell `metres` along the great circle toward -Y from the Core (west of it).
static func cell_west(metres: float) -> int:
	var a: float = metres / R
	return Sphere.cell_of(Vector3(cos(a), -sin(a), 0.0), Sphere.GRID_BUILD)


static func def(id: StringName) -> int:
	return WorldTestKit.def_id(id)


## First live structure slot of `def_id` owned by `owner`; -1 when none.
static func find(w: SimWorld, id: StringName, owner: int = 0) -> int:
	var d: int = def(id)
	for s: int in w.store().structures:
		if w.store().def_id[s] == d and w.store().owner[s] == owner:
			return s
	return -1


## Runs `n` ticks; returns every event of them, in order.
static func run(w: SimWorld, n: int) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for _i: int in n:
		w.step()
		out.append_array(w.drain_events())
	return out


static func count_kind(events: Array[SimEvent], kind: SimEvent.Kind) -> int:
	var n: int = 0
	for e: SimEvent in events:
		if e.kind == kind:
			n += 1
	return n


static func count_alert(events: Array[SimEvent], kind: AlertKind.Kind) -> int:
	var n: int = 0
	for e: SimEvent in events:
		if e.kind == SimEvent.Kind.ALERT and e.a == kind:
			n += 1
	return n


static func ore(w: SimWorld, team: int = 0) -> int:
	return w.economy().economy.stockpile(team).x


static func code(w: SimWorld, cmd: Command) -> int:
	return w.apply_command(cmd).code
