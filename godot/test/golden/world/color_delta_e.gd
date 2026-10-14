class_name ColorDeltaE
extends RefCounted
## CIEDE2000 colour difference between two sRGB colours (D65), for the ART-14 biome acceptance
## ("rendered biome colours within dE00 <= 6 of 07 s2.1, day and night"). Test tooling, not shipped.

const _XN: float = 0.95047
const _YN: float = 1.0
const _ZN: float = 1.08883


## sRGB colour -> CIE Lab (D65), as Vector3(L, a, b).
static func to_lab(c: Color) -> Vector3:
	var l: Color = c.srgb_to_linear()
	var x: float = (0.4124564 * l.r + 0.3575761 * l.g + 0.1804375 * l.b) / _XN
	var y: float = (0.2126729 * l.r + 0.7151522 * l.g + 0.0721750 * l.b) / _YN
	var z: float = (0.0193339 * l.r + 0.1191920 * l.g + 0.9503041 * l.b) / _ZN
	var fx: float = _f(x)
	var fy: float = _f(y)
	var fz: float = _f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _f(t: float) -> float:
	var d: float = 6.0 / 29.0
	return pow(t, 1.0 / 3.0) if t > d * d * d else t / (3.0 * d * d) + 4.0 / 29.0


## CIEDE2000 (Sharma, Wu, Dalal 2005; kL = kC = kH = 1) between two sRGB colours.
static func de00(a: Color, b: Color) -> float:
	return de00_lab(to_lab(a), to_lab(b))


static func de00_lab(l1: Vector3, l2: Vector3) -> float:
	var c1: float = Vector2(l1.y, l1.z).length()
	var c2: float = Vector2(l2.y, l2.z).length()
	var cm7: float = pow((c1 + c2) * 0.5, 7.0)
	var g: float = 0.5 * (1.0 - sqrt(cm7 / (cm7 + pow(25.0, 7.0))))
	var a1: float = (1.0 + g) * l1.y
	var a2: float = (1.0 + g) * l2.y
	var cp1: float = Vector2(a1, l1.z).length()
	var cp2: float = Vector2(a2, l2.z).length()
	var h1: float = _hue(l1.z, a1)
	var h2: float = _hue(l2.z, a2)
	var dl: float = l2.x - l1.x
	var dc: float = cp2 - cp1
	var dh_deg: float = 0.0
	if cp1 * cp2 != 0.0:
		dh_deg = h2 - h1
		if dh_deg > 180.0:
			dh_deg -= 360.0
		elif dh_deg < -180.0:
			dh_deg += 360.0
	var dh: float = 2.0 * sqrt(cp1 * cp2) * sin(deg_to_rad(dh_deg) * 0.5)
	var lm: float = (l1.x + l2.x) * 0.5
	var cm: float = (cp1 + cp2) * 0.5
	var hm: float = h1 + h2
	if cp1 * cp2 != 0.0:
		if absf(h1 - h2) <= 180.0:
			hm = (h1 + h2) * 0.5
		elif h1 + h2 < 360.0:
			hm = (h1 + h2 + 360.0) * 0.5
		else:
			hm = (h1 + h2 - 360.0) * 0.5
	var t: float = 1.0 - 0.17 * cos(deg_to_rad(hm - 30.0)) + 0.24 * cos(deg_to_rad(2.0 * hm)) \
			+ 0.32 * cos(deg_to_rad(3.0 * hm + 6.0)) - 0.20 * cos(deg_to_rad(4.0 * hm - 63.0))
	var dtheta: float = 30.0 * exp(-pow((hm - 275.0) / 25.0, 2.0))
	var rc: float = 2.0 * sqrt(pow(cm, 7.0) / (pow(cm, 7.0) + pow(25.0, 7.0)))
	var lm50: float = (lm - 50.0) * (lm - 50.0)
	var sl: float = 1.0 + 0.015 * lm50 / sqrt(20.0 + lm50)
	var sc: float = 1.0 + 0.045 * cm
	var sh: float = 1.0 + 0.015 * cm * t
	var rt: float = -sin(deg_to_rad(2.0 * dtheta)) * rc
	var el: float = dl / sl
	var ec: float = dc / sc
	var eh: float = dh / sh
	return sqrt(el * el + ec * ec + eh * eh + rt * ec * eh)


static func _hue(b: float, a: float) -> float:
	if a == 0.0 and b == 0.0:
		return 0.0
	var h: float = rad_to_deg(atan2(b, a))
	return h + 360.0 if h < 0.0 else h
