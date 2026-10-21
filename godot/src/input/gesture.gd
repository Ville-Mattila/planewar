class_name Gesture extends RefCounted
## One recognised touch gesture (06 s2.3). Produced by GestureRecognizer, mapped to intents by GestureIntents.

enum Kind { TAP, DOUBLE_TAP, LONG_PRESS, DRAG, FLING, PINCH, TWIST, TWO_FINGER_DRAG, FLICK_UP, FIRE_HOLD }
## BEGIN/UPDATE/END apply to LONG_PRESS, DRAG, PINCH, TWIST, TWO_FINGER_DRAG and FIRE_HOLD; the rest are BEGIN.
enum Phase { BEGIN, UPDATE, END }

var kind: Kind = Kind.TAP
var phase: Phase = Phase.BEGIN
var pos: Vector2 = Vector2.ZERO      ## current finger position, or the centroid of a two-finger gesture
var origin: Vector2 = Vector2.ZERO   ## where the gesture started
var delta: Vector2 = Vector2.ZERO    ## movement since the previous event (DRAG, TWO_FINGER_DRAG)
var value: float = 0.0               ## PINCH: ln(distance / previous distance); TWIST: signed radians (clockwise +)
var vel: Vector2 = Vector2.ZERO      ## FLING: release velocity in du/s
var held: bool = false               ## DRAG that follows a LONG_PRESS


static func make(k: Kind, ph: Phase, p: Vector2, o: Vector2) -> Gesture:
	var g: Gesture = Gesture.new()
	g.kind = k
	g.phase = ph
	g.pos = p
	g.origin = o
	return g
