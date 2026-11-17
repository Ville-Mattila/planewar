class_name RelayTestKit extends RefCounted
## Fixtures for the GD-23 tests (sim/relay/MODULE.md R1-R11): a WorldTestKit world (players 0 and 2 on team 0, 1 on team 1),
## a neutral Relay Station on the datum, Haulers docked on it, and enemy units hovering `east` metres from it. The relay
## pass is run alone (`pass_n`), so hovering units do not fall; the end-to-end tests step the world.

const DT: float = 1.0 / 30.0
const NEUTRAL: int = 255


static func world() -> SimWorld:
	var w: SimWorld = WorldTestKit.world()
	var _e: Array[SimEvent] = w.drain_events()
	return w


## A number of the Relay Station def (`capture_s`, `contest_radius_m`; structures.json, R0 B.30 A-148) or of scoring.json `relay`.
static func rule(key: String) -> float:
	var sd: StructureDef = WorldTestKit.content().structures[WorldTestKit.def_id(&"relay_station") - DefRanges.STRUCTURE_BASE]
	if sd.raw.has(key):
		return Def.num(sd.raw[key])
	return Def.num(WorldTestKit.content().scoring.relay.get(key, 0.0))


## A neutral Relay Station (owner and team 255) at the datum point of `east` metres.
static func relay(w: SimWorld, east: float = 0.0) -> int:
	return DockingTestKit.direct(w, &"relay_station", NEUTRAL, NEUTRAL, WorldTestKit.at(0.0, east))


static func capture(w: SimWorld) -> RelayCapture:
	return w.economy().relay


## A ship `def` of `owner` DOCKED on `pad` (the flags and the link a landing sets).
static func docked(w: SimWorld, def: StringName, owner: int, pad: int) -> int:
	var id: int = DockingTestKit.direct(w, def, owner, w._players.team[owner], DockingTestKit.far(w))
	DockingTestKit.dock(w, id, pad)
	return id


## A unit `def` of `owner` 20 m above the datum `east` metres along +Y (a ship hovers; the world is not stepped).
static func unit(w: SimWorld, def: StringName, owner: int, east: float) -> int:
	return DockingTestKit.direct(w, def, owner, w._players.team[owner], WorldTestKit.at(20.0, east))


static func pass_n(w: SimWorld, n: int) -> void:
	for _i: int in n:
		capture(w).step(DT)


static func seconds(s: float) -> int:
	return roundi(s / DT)


static func team_of(w: SimWorld, id: int) -> int:
	return w.store().team[EntityId.slot(id)]


## Capture progress in seconds: the relay's `timer_b` (A-149).
static func progress(w: SimWorld, id: int) -> float:
	return w.store().timer_b[EntityId.slot(id)]


## The pause flag: the relay's `timer_a` (A-149).
static func contested(w: SimWorld, id: int) -> bool:
	return w.store().timer_a[EntityId.slot(id)] > 0.0


## The capturer whose capture runs: the relay's `link` (A-149), 0 for none.
static func capturer(w: SimWorld, id: int) -> int:
	return w.store().link[EntityId.slot(id)]


static func of_kind(events: Array[SimEvent], kind: SimEvent.Kind, alert: int = -1) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.kind == kind and (alert < 0 or e.a == alert):
			out.append(e)
	return out
