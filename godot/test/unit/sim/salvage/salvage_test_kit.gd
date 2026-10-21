class_name SalvageTestKit extends RefCounted
## Fixtures for the GD-19 tests: the EconomyTestKit world (players 0 and 2 team 0, 1 team 1, no start kit, flat datum)
## plus a Foundry player in slot 3 (team 0), structures and ships spawned through the applier, kills through the
## deferred death list (the same path Combat uses), and wrecks / tow orders written the way the tick reads them.

const R: float = Sphere.PLANET_RADIUS
const FOUNDRY_SLOT: int = 3


## Team 0 = players 0, 2 and 3 (3 flies the Foundry doctrine), team 1 = player 1; `cap` > 0 sets caps.wrecks.
static func world(cap: int = 0) -> SimWorld:
	var r: MatchRules = WorldTestKit.rules()
	if cap > 0:
		r.caps.wrecks = cap
	var w: SimWorld = EconomyTestKit.solo_world(false, 7, r)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	w.add_player(FOUNDRY_SLOT, 0, &"foundry", PlayerTable.KIND_HUMAN)
	return w


## `alt` metres above the datum, `east` metres of arc along +Y from +X (WorldTestKit.at is a flat offset, not on the sphere).
static func at(alt: float, east: float = 0.0) -> Vector3:
	return Vector3(R, east, 0.0).normalized() * (R + alt)


## Spawns through the applier (DEBUG_SPAWN is rate limited per player); no tick passes. The entity slot, -1 if refused.
static func put(w: SimWorld, def: StringName, owner: int, team: int, alt: float, east: float = 0.0) -> int:
	var s: int = w._applier.spawn(WorldTestKit.def_id(def), owner, team, at(alt, east), Vector3.ZERO, Vector3(0, 1, 0), w.tick())
	assert(s > 0)
	return s


## Marks `s` dying and runs one tick: step 9 spawns the wrecks. Returns that tick's events.
static func kill(w: SimWorld, s: int) -> Array[SimEvent]:
	w._applier.kill(s)
	w.step()
	return w.drain_events()


static func of_kind(events: Array[SimEvent], kind: SimEvent.Kind) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.kind == kind:
			out.append(e)
	return out


## Live wreck slots now (ascending).
static func wrecks(w: SimWorld) -> PackedInt32Array:
	return w.store().wrecks.duplicate()


## A wreck of `def` worth `ore` written straight into the store at `p` (no death needed); returns its slot.
static func wreck_at(w: SimWorld, def: StringName, ore: float, p: Vector3) -> int:
	var st: EntityStore = w.store()
	var id: int = st.alloc(EntityStore.K_WRECK, w.tick())
	var s: int = EntityId.slot(id)
	st.def_id[s] = WorldTestKit.def_id(def)
	st.pos[s] = p
	st.up[s] = p.normalized()
	st.hp[s] = ore
	return s


## Standing HAUL order of `h` with `mode` aimed at EntityId `target`.
static func haul(w: SimWorld, h: int, mode: OrderSpec.HaulMode, target: int) -> void:
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.HAUL, target)
	spec.haul_mode = mode
	var _r: OrderQueue.Push = w._orders.push(h, OrderQueue.STANDING, spec)


static func tethered(w: SimWorld, s: int) -> bool:
	return (w.store().flags[s] & EntityStore.F_TETHERED) != 0


static func steps(w: SimWorld, n: int) -> Array[SimEvent]:
	return EconomyTestKit.run(w, n)


static func ore(w: SimWorld, team: int = 0) -> int:
	return EconomyTestKit.ore(w, team)
