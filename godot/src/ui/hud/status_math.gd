class_name StatusMath extends RefCounted
## Pure maths of the Core shield timer, consumables and cooldown rings (docs/06 s6.4, s7.1; UX-18).

enum Boost { READY, ACTIVE, COOLING }   # SimView.boost_state: 0 ready, 1 boosting, 2 cooling down

## TeamStateView.flags bit CORE_SHIELD_UP (04 0x85 order); the name is not in the ui allow-list (deps.json), so the bit is mirrored
## here and a test pins it to the sim constant.
const CORE_SHIELD_UP: int = 4


## Seconds of opening Core shield left: `until_s` is match_rules `core_shield_until_s`, clock the match clock.
static func shield_remaining_s(until_s: float, clock_s: float) -> float:
	return maxf(until_s - clock_s, 0.0)


## Share of the opening shield window still to run, 0..1 (1 at the start of the match).
static func shield_ring01(until_s: float, clock_s: float) -> float:
	if until_s <= 0.0:
		return 0.0
	return clampf(shield_remaining_s(until_s, clock_s) / until_s, 0.0, 1.0)


## The clock badge and the Core ring show while TeamStateView.CORE_SHIELD_UP is set and time is left.
static func shield_visible(team_flags: int, until_s: float, clock_s: float) -> bool:
	return (team_flags & CORE_SHIELD_UP) != 0 and shield_remaining_s(until_s, clock_s) > 0.0


## Arc fill of a cooldown ring: 1 when ready, rising from 0 while cooling. `cooldown01` is the share still to run
## (SimView.flip_cooldown01: 1 right after use, 0 ready).
static func ring_fill(cooldown01: float) -> float:
	return 1.0 - clampf(cooldown01, 0.0, 1.0)


static func ring_ready(cooldown01: float) -> bool:
	return cooldown01 <= 0.0


## Boost has no fraction in SimView (needs sim: boost_cooldown01); the ring shows full while READY or ACTIVE and
## empty while COOLING.
static func boost_fill(state: int) -> float:
	return 0.0 if state == Boost.COOLING else 1.0


## Fraction of a consumable left against its capacity; 0 for a zero capacity.
static func share01(count: int, capacity: int) -> float:
	return clampf(float(count) / float(capacity), 0.0, 1.0) if capacity > 0 else 0.0
