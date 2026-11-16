class_name MatchFlowKit extends RefCounted
## GD-20 fixtures: a world run at 1 Hz (one tick = one second, so the real `pvp_1v1` / `pvp_team` timers of 1,200 /
## 1,800 and 1,800 / 2,400 ticks cost a few thousand cheap steps) with `per_team` humans on each of two teams. Every
## player owns a Core and a Refinery (DEBUG_SPAWN, finished); team 0 sits on +X, team 1 on -X.

const R: float = Sphere.PLANET_RADIUS
const MODES: PackedStringArray = ["pvp_1v1", "pvp_team"]


static func mode(id: StringName) -> ModeDef:
	for m: ModeDef in WorldTestKit.content().modes:
		if m.id == id:
			return m
	return null


static func rules(id: StringName) -> MatchRules:
	var c: ContentSet = WorldTestKit.content()
	var r: MatchRules = MatchRules.from_defs(mode(id), c.match_rules, c.rules, &"")
	r.tick_hz = 1
	r.debug_commands = true
	return r


## Players 0..per_team-1 on team 0, per_team..2 * per_team-1 on team 1; slot k's team is `k / per_team`.
static func world(id: StringName, per_team: int, kits: bool = true) -> SimWorld:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = &""
	var res: Result = w.load_map(map, 11, rules(id))
	assert(res.ok, res.message)
	for p: int in per_team * 2:
		w.add_player(p, team_of(p, per_team), &"", PlayerTable.KIND_HUMAN)
	if kits:
		for p: int in per_team * 2:
			var _c: int = WorldTestKit.spawn(w, &"core", p, team_of(p, per_team), site(p, 0, per_team))
			var _r: int = WorldTestKit.spawn(w, &"refinery", p, team_of(p, per_team), site(p, 1, per_team))
	return w


## Distinct, well separated points: team by side of the planet, slot and `k` along it.
static func site(p: int, k: int, per_team: int) -> Vector3:
	var side: float = 1.0 if p < per_team else -1.0
	var a: float = (float(p % per_team) * 0.08 + float(k) * 0.02) * side
	return Vector3(cos(a), sin(a), 0.0) * R * side


static func structure(w: SimWorld, owner: int, id: StringName) -> int:
	var d: int = WorldTestKit.def_id(id)
	for s: int in w.store().structures:
		if w.store().def_id[s] == d and w.store().owner[s] == owner:
			return s
	return -1


## Kills the Core of `p` through the deferred-death path (DEBUG_SET SET_HP 0).
static func kill_core(w: SimWorld, p: int) -> void:
	var s: int = structure(w, p, &"core")
	var r: CommandResult = w.apply_command(CommandPayload.debug_set(0, w.store().id_of(s), CommandPayload.SET_HP, 0.0))
	assert(r.code == CommandResult.Code.ACCEPTED)


## Steps until the world clock is `tick`; every event on the way.
static func run_to(w: SimWorld, tick: int) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	while w.tick() < tick:
		w.step()
		out.append_array(w.drain_events())
	return out


static func of_kind(events: Array[SimEvent], kind: SimEvent.Kind) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.kind == kind:
			out.append(e)
	return out


static func surrender(w: SimWorld, p: int) -> CommandResult:
	return w.apply_command(CommandPayload.simple(p, Command.Kind.SURRENDER, 0))


static func team_of(p: int, per_team: int) -> int:
	return 0 if p < per_team else 1
