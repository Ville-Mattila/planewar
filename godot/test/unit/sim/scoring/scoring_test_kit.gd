class_name ScoringTestKit extends RefCounted
## Shared fixtures for the GD-27 score tests: the WorldTestKit world (players 0 and 2 on team 0, 1 on team 1), entities
## parked high above the datum, kills through the real `DamageSink` (so the HIT, the attacker stamp and the deferred
## death follow the tick), crafted LANDING events, and the score read back through `SimView.player_score`. Every number
## comes from the shipped `scoring.json`; the tests only scale it.

const MANUAL: int = 1        ## LANDING flags bit0 (04 s3.6 row 29)
const HOT: int = 2           ## bit1
const DEAD_STICK: int = 4    ## bit2 (R0 B.24 A-121)


static func def() -> ScoringDef:
	return WorldTestKit.content().scoring


static func world() -> SimWorld:
	var w: SimWorld = WorldTestKit.world()
	var _e: Array[SimEvent] = w.drain_events()
	return w


static func keeper(w: SimWorld) -> ScoreKeeper:
	return w.economy().score


static func hz() -> int:
	return WorldTestKit.content().rules.tick_hz


## A unit or structure of `def_id`, parked at its own point 1,000 m up (60 m apart per call).
static func spawn(w: SimWorld, def_id: StringName, owner: int, team: int) -> int:
	var id: int = WorldTestKit.spawn(w, def_id, owner, team, DockingTestKit.far(w))
	var _e: Array[SimEvent] = w.drain_events()
	return id


static func sink(w: SimWorld) -> DamageSink:
	return DamageSink.new(w.store(), w._events, w._applier, w._defs)


## `amount` damage from `attacker` to `victim` now (a HIT event; kills when it empties the hull); no step.
static func hit(w: SimWorld, victim: int, attacker: int, amount: float) -> void:
	var _d: bool = sink(w).damage(EntityId.slot(victim), amount, attacker, w.tick())


static func hp(w: SimWorld, id: int) -> float:
	return w.store().hp[EntityId.slot(id)]


## Empties `victim` with one hit from `killer`, then steps once (the death resolves in step 9 and is scored there).
static func kill(w: SimWorld, victim: int, killer: int) -> void:
	hit(w, victim, killer, hp(w, victim) + 1.0)
	w.step()
	var _e: Array[SimEvent] = w.drain_events()


static func score(w: SimWorld, slot: int) -> Vector2i:
	return w.view().player_score(slot)


## A LANDING event for `ship` as Touchdown writes it: extra = grade, round(q * 255), flags, v_vert, v_horiz; the keeper
## scans it at once (no step).
static func landing(w: SimWorld, ship: int, grade: int, flags: int) -> void:
	var s: int = EntityId.slot(ship)
	var e: SimEvent = w._events.emit(SimEvent.Kind.LANDING, ship, 0, w.store().pos[s], 0.9, w.store().team[s])
	e.extra = PackedByteArray([grade, 230, flags, 5, 5])
	keeper(w).scan()
