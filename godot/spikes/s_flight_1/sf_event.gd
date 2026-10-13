class_name SfEvent extends RefCounted
## One spike world event (the spike's stand-in for SimEvent; drained once per frame by view, HUD, telemetry).

enum Kind { LAUNCHED, TOUCHDOWN, CRASH, TARGET_HIT, TARGET_DESTROYED, BOMB_DROP, BOMB_IMPACT, FLIP, BOOST,
	CEILING_RELEASE, CEILING_RESTORED, RESPAWN, SERVICED, ASSIST_ON, ASSIST_OFF }

var kind: Kind
var tick: int
var a: int = -1                   # target index, etc.
var value: float                  # damage, etc.
var pos: Vector3
var touchdown: SfTouchdown        # TOUCHDOWN / CRASH from a contact; null otherwise
var near_pad: bool                # contact within landing.attempt_radius_m of the pad (a landing attempt)
var reason: String = ""


static func make(k: Kind, t: int, p: Vector3) -> SfEvent:
	var e: SfEvent = SfEvent.new()
	e.kind = k
	e.tick = t
	e.pos = p
	return e


func kind_name() -> String:
	var k: String = Kind.keys()[kind]
	return k
