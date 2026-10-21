class_name GestureIntents extends RefCounted
## Maps a Gesture to an RTS intent (06 s3.3 touch column). Pure. Returns {} (no intent) or
## {&"kind": StringName, &"payload": Dictionary}. Hit-testing (unit vs ground) belongs to the consumer: a tap is
## always SELECT at `pos`; the picking layer (UX-20) decides what is under it.


static func rts_intent(g: Gesture) -> Dictionary:
	match g.kind:
		Gesture.Kind.TAP:
			return _make(Intents.SELECT, {Intents.K_POS: g.pos, Intents.K_ADD: false})
		Gesture.Kind.DOUBLE_TAP:
			return _make(Intents.CAM_TIER_TOGGLE, {Intents.K_POS: g.pos})
		Gesture.Kind.LONG_PRESS:
			if g.phase == Gesture.Phase.END:
				return _make(Intents.SELECT, {Intents.K_POS: g.pos, Intents.K_ADD: true})
		Gesture.Kind.DRAG:
			return _drag(g)
		Gesture.Kind.FLING:
			return _make(Intents.CAM_PAN_VEL, {Intents.K_VEL: g.vel})
		Gesture.Kind.PINCH:
			if g.phase != Gesture.Phase.END:
				return _make(Intents.CAM_ZOOM, {Intents.K_LOG_DELTA: g.value, Intents.K_ANCHOR: g.pos})
		Gesture.Kind.TWIST:
			if g.phase != Gesture.Phase.END:
				return _make(Intents.CAM_ROTATE, {Intents.K_RAD: g.value, Intents.K_ANCHOR: g.pos})
		Gesture.Kind.TWO_FINGER_DRAG:
			if g.phase != Gesture.Phase.END:
				return _make(Intents.CAM_TILT, {Intents.K_VEC: g.delta, Intents.K_ANCHOR: g.pos})
	return {}


static func _drag(g: Gesture) -> Dictionary:
	var on: bool = g.phase != Gesture.Phase.END
	if g.held:
		var rect: Rect2 = Rect2(g.origin, Vector2.ZERO).expand(g.pos)
		return _make(Intents.SELECT_BOX, {Intents.K_RECT: rect, Intents.K_ADD: false, Intents.K_ON: on})
	return _make(Intents.CAM_PAN_GRAB, {Intents.K_FROM: g.origin, Intents.K_TO: g.pos, Intents.K_ON: on})


static func _make(kind: StringName, payload: Dictionary) -> Dictionary:
	return {&"kind": kind, &"payload": payload}
