class_name MathX
## Static helpers that keep integer-division warning annotations out of sim code (03 s1.1).


## Floor division for ints (rounds toward negative infinity).
static func floori_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Non-negative modulo for ints: result in [0, |b|).
static func posmod_i(a: int, b: int) -> int:
	var r: int = a % b
	if r < 0:
		r += absi(b)
	return r


static func move_toward_v3(from: Vector3, to: Vector3, delta: float) -> Vector3:
	return from.move_toward(to, delta)


static func smoothstep01(e0: float, e1: float, x: float) -> float:
	if e1 == e0:
		return 0.0 if x < e0 else 1.0
	var t: float = clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
