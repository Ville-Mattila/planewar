class_name ShipReads extends RefCounted
## Ship-state reads of `LocalSimView` (A-73 extraction, GD-15): boost and flip timers, dock and service state.
## Static, allocation-free; `sd` is the ship's doctrine-resolved def or null (not a ship, dead).


## 0 ready, 1 boosting, 2 cooling down.
static func boost_state(store: EntityStore, sd: ShipDef, id: int) -> int:
	if sd == null:
		return 0
	var b: float = store.boost_time[EntityId.slot(id)]
	return 1 if b > 0.0 else (0 if b <= -sd.boost_cooldown_s else 2)


## Share of the flip cooldown still to run: 1 while flipping, 0 when FLIP is ready.
static func flip_cooldown01(store: EntityStore, sd: ShipDef, id: int) -> float:
	if sd == null or sd.flip_cooldown_s <= 0.0:
		return 0.0
	var f: float = store.flip_time[EntityId.slot(id)]
	return 1.0 if f > 0.0 else clampf(1.0 + f / sd.flip_cooldown_s, 0.0, 1.0)


## Dock state: FLYING (0) or DOCKED (2); LANDING_ASSIST and LAUNCHING arrive with the auto-dock wiring (AI-10 / NET-18)
## and the docked launch (GD-15 contract question).
static func dock_state(store: EntityStore, id: int) -> int:
	return 2 if store.alive(id) and (store.flags[EntityId.slot(id)] & EntityStore.F_DOCKED) != 0 else 0


## Service state: DOCKED 1, TOWING 2 (tethered), BUILDING 4 from the entity flags; CAPTURING arrives with Economy.
static func service_state(store: EntityStore, id: int) -> int:
	if not store.alive(id):
		return 0
	var f: int = store.flags[EntityId.slot(id)]
	if (f & EntityStore.F_BUILDING) != 0:
		return 4
	if (f & EntityStore.F_DOCKED) != 0:
		return 1
	return 2 if (f & EntityStore.F_TETHERED) != 0 else 0
