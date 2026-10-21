class_name DeadReckon
## Gravity-aware dead reckoning and C-BLIP geometry of the snapshot codec (04 s3.4, R0 C1-18), on quantised
## state. Server (per-client baseline mirror) and client run exactly this arithmetic, so both ends reach the
## same levels: scalar float64 math only (GDScript `float`), no Vector3 (float32) in the level path.
##   dr(t) = pos_b + vel_b * t - 0.5 * g * normalize(pos_b) * t^2   gravity-bearing (def gravity or baseline DYING)
##   dr(t) = pos_b + vel_b * t                                        everything else
## In the ENU frame of the baseline cell the radial vector of a point (e, n, u) is (e, n, R + u), because the
## cell centre lies on the datum sphere and `up` is radial there (ADR-03), so no basis is needed.

## C-BLIP (04 s3.4): e8 = e level >> 8 clamped to E8_MAX so that 0xFF after a gap always means a FULL record's
## mask byte; alt6 in 40 m steps from RELIEF_MIN; 2-bit state.
const BLIP_E8_MAX: int = 254
const BLIP_ALT_STEP: float = 40.0
const BLIP_ALT_MAX6: int = 63
enum BlipState { MOVING, STATIC, UNDER_FIRE, DYING }
const BLIP_UNKNOWN: int = -1

## Entry velocities are kept at 1/1024 m/s (internal to both baselines, never on the wire).
const FINE_PER_MPS: int = 1024
const _FINE_INV: float = 1.0 / FINE_PER_MPS
const _FINE_MASK: int = 0x1FFFFF
const _FINE_MAX: int = 0xFFFFF
const _EN_INV: float = 1.0 / Codec.POS_EN_QUANTUM
const _U_INV: float = 1.0 / Codec.POS_U_QUANTUM


static func _sext8(v: int) -> int:
	return ((v & 0xFF) ^ 0x80) - 0x80


## Dead-reckoned (e, n, u) levels in the baseline's cell, unclamped (the caller rejects values outside
## 0..65535). `fine` is the entry's fine velocity (see fine_from_bits); `dticks` = tick - the entry's tick;
## `dt` = 1 / tick_hz.
static func dr_levels(pos_q: int, fine: int, dticks: int, grav: bool, g: float, dt: float) -> Vector3i:
	var e0: int = Codec.pos_e(pos_q)
	var n0: int = Codec.pos_n(pos_q)
	var u0: int = Codec.pos_u(pos_q)
	if fine == 0 and not grav:
		return Vector3i(e0, n0, u0)
	var t: float = float(dticks) * dt
	var de: float = float(fine_axis(fine, 0)) * _FINE_INV * t
	var dn: float = float(fine_axis(fine, 1)) * _FINE_INV * t
	var du: float = float(fine_axis(fine, 2)) * _FINE_INV * t
	if grav and dticks != 0:
		var em: float = float(e0) * Codec.POS_EN_QUANTUM - Codec.POS_EN_HALF
		var nm: float = float(n0) * Codec.POS_EN_QUANTUM - Codec.POS_EN_HALF
		var rz: float = Sphere.PLANET_RADIUS + float(u0) * Codec.POS_U_QUANTUM + Codec.POS_U_MIN
		var k: float = 0.5 * g * t * t / sqrt(em * em + nm * nm + rz * rz)
		de -= k * em
		dn -= k * nm
		du -= k * rz
	return Vector3i(e0 + floori(de * _EN_INV + 0.5), n0 + floori(dn * _EN_INV + 0.5), u0 + floori(du * _U_INV + 0.5))


## Fine velocity after `dticks`: unchanged for the linear branch, fine - g * up_b * t (rounded to 1/1024 m/s)
## for the gravity branch. A record without VEL stores this, so re-basing a ballistic entity's position never
## re-quantises its velocity to the 2 m/s wire step.
static func dr_fine(pos_q: int, fine: int, dticks: int, grav: bool, g: float, dt: float) -> int:
	if not grav or dticks == 0:
		return fine
	var em: float = float(Codec.pos_e(pos_q)) * Codec.POS_EN_QUANTUM - Codec.POS_EN_HALF
	var nm: float = float(Codec.pos_n(pos_q)) * Codec.POS_EN_QUANTUM - Codec.POS_EN_HALF
	var rz: float = Sphere.PLANET_RADIUS + float(Codec.pos_u(pos_q)) * Codec.POS_U_QUANTUM + Codec.POS_U_MIN
	var k: float = g * float(dticks) * dt * float(FINE_PER_MPS) / sqrt(em * em + nm * nm + rz * rz)
	return pack_fine(fine_axis(fine, 0) - roundi(k * em), fine_axis(fine, 1) - roundi(k * nm),
			fine_axis(fine, 2) - roundi(k * rz))


## Entry velocity as three signed 21-bit axes (ENU of the entry's cell) in 1/FINE_PER_MPS m/s, packed in one int.
static func pack_fine(e: int, n: int, u: int) -> int:
	return (clampi(e, -_FINE_MAX, _FINE_MAX) & _FINE_MASK) | ((clampi(n, -_FINE_MAX, _FINE_MAX) & _FINE_MASK) << 21) 			| ((clampi(u, -_FINE_MAX, _FINE_MAX) & _FINE_MASK) << 42)


static func fine_axis(fine: int, axis: int) -> int:
	var v: int = (fine >> (21 * axis)) & _FINE_MASK
	return (v ^ 0x100000) - 0x100000


## Wire velocity bits (3 x i8 at 2 m/s) -> fine velocity, exactly.
static func fine_from_bits(bits: int) -> int:
	var step: int = roundi(Codec.VEL_UNIT * FINE_PER_MPS)
	return pack_fine(_sext8(bits) * step, _sext8(bits >> 8) * step, _sext8(bits >> 16) * step)


## Fine velocity -> wire bits, rounded half away from zero and clamped like Codec.quantize_vel.
static func bits_from_fine(fine: int) -> int:
	var e: int = _vel_step(float(fine_axis(fine, 0)) * _FINE_INV)
	var n: int = _vel_step(float(fine_axis(fine, 1)) * _FINE_INV)
	var u: int = _vel_step(float(fine_axis(fine, 2)) * _FINE_INV)
	return (e & 0xFF) | ((n & 0xFF) << 8) | ((u & 0xFF) << 16)


static func _vel_step(v: float) -> int:
	return clampi(roundi(v / Codec.VEL_UNIT), -Codec.VEL_MAX, Codec.VEL_MAX)


## True when two velocity bit sets differ by at most one 2 m/s step per axis. The encoder does not send VEL for a
## gravity-bearing entity whose quantised velocity is this close to the dead-reckoned one: a rounding-boundary
## flip would re-base the entry onto a velocity up to 1 m/s off and start position drift (decoder unaffected).
static func vel_close(a: int, b: int) -> bool:
	return absi(_sext8(a) - _sext8(b)) <= 1 and absi(_sext8(a >> 8) - _sext8(b >> 8)) <= 1 			and absi(_sext8(a >> 16) - _sext8(b >> 16)) <= 1


## True when every level is a valid u16.
static func levels_ok(l: Vector3i) -> bool:
	return l.x >= 0 and l.x < Codec.POS_LEVELS and l.y >= 0 and l.y < Codec.POS_LEVELS \
			and l.z >= 0 and l.z < Codec.POS_LEVELS


## Blip u24 = e8 | n8 << 8 | (alt6 | state << 6) << 16 from a quantised position and its altitude above datum.
static func make_blip(pos_q: int, alt_m: float, state: int) -> int:
	var e8: int = mini(Codec.pos_e(pos_q) >> 8, BLIP_E8_MAX)
	var n8: int = Codec.pos_n(pos_q) >> 8
	var alt6: int = clampi(floori((alt_m - Sphere.RELIEF_MIN) / BLIP_ALT_STEP), 0, BLIP_ALT_MAX6)
	return e8 | (n8 << 8) | ((alt6 | ((state & 3) << 6)) << 16)


## Quantised position a blip stands for in `cell`: the centre of its e8/n8 bucket at the centre of its
## 40 m altitude band.
static func blip_pos(cell: int, blip: int) -> int:
	var e: int = ((blip & 0xFF) << 8) | 0x80
	var n: int = (((blip >> 8) & 0xFF) << 8) | 0x80
	var alt: float = Sphere.RELIEF_MIN + (float((blip >> 16) & 0x3F) + 0.5) * BLIP_ALT_STEP
	var em: float = float(e) * Codec.POS_EN_QUANTUM - Codec.POS_EN_HALF
	var nm: float = float(n) * Codec.POS_EN_QUANTUM - Codec.POS_EN_HALF
	var rr: float = Sphere.PLANET_RADIUS + alt
	var u: float = sqrt(maxf(rr * rr - em * em - nm * nm, 0.0)) - Sphere.PLANET_RADIUS
	var ul: int = clampi(floori((u - Codec.POS_U_MIN) * _U_INV + 0.5), 0, Codec.POS_LEVELS - 1)
	return Codec.pack_pos(cell, e, n, ul)


static func blip_state(blip: int) -> int:
	return (blip >> 22) & 3


## The blip an entry shows `dticks` after its tick (NET-54, server only): make_blip of its dead-reckoned levels
## (dr_levels, the position a client displays; `grav` as in the encoder's DELTA rule) at their float64 altitude above
## datum, state DYING (flags), STATIC (zero velocity or DOCKED) or MOVING; never UNDER_FIRE (server-only state).
## BLIP_UNKNOWN when the levels leave the cell. The tier-C encoder skips a C-BLIP for an entry with an unknown blip
## while this equals the true blip, so the client's dead-reckoned entry stays in the true blip's bucket.
static func entry_blip(pos_q: int, flag_b: int, fine: int, dticks: int, grav: bool, g: float, dt: float) -> int:
	var lv: Vector3i = dr_levels(pos_q, fine, dticks, grav, g, dt)
	if not levels_ok(lv):
		return BLIP_UNKNOWN
	var st: int = BlipState.MOVING
	if flag_b & Codec.FLAG_DYING:
		st = BlipState.DYING
	elif fine == 0 or (flag_b & Codec.FLAG_DOCKED) != 0:
		st = BlipState.STATIC
	var em: float = float(lv.x) * Codec.POS_EN_QUANTUM - Codec.POS_EN_HALF
	var nm: float = float(lv.y) * Codec.POS_EN_QUANTUM - Codec.POS_EN_HALF
	var rz: float = Sphere.PLANET_RADIUS + float(lv.z) * Codec.POS_U_QUANTUM + Codec.POS_U_MIN
	var q: int = Codec.pack_pos(Codec.pos_cell(pos_q), lv.x, lv.y, lv.z)
	return make_blip(q, sqrt(em * em + nm * nm + rz * rz) - Sphere.PLANET_RADIUS, st)
