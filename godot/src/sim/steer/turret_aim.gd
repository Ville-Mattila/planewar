class_name TurretAim extends RefCounted
## Tower slew law (05 s6.8, R0 C2-09, B.23 A-118; AI-17, AI-44). Static and pure (S8, 03 s5.6): a function of its
## arguments only, so the same law serves the tower brain and any later prediction. A tower is an azimuth / elevation
## mount: `PilotInput.pitch` is the elevation rate (about the turret's right, +pitch raises the muzzle), `yaw` the azimuth
## rate (about the site normal `n`, +yaw turns the muzzle left), both fractions of `turret_turn_dps`, the pair clamped to
## unit norm (a diagonal command moves at the cap). The sim applies the commanded rate in full in the tick it is
## commanded (no rate lag), keeps `right` tangent (no roll) and truncates elevation at the pole. The command is the
## dead-beat rate: the elevation and azimuth errors (the azimuth is the angle about `n`, so it already carries the
## 1 / cos(elevation) compensation of a great-circle error) over one tick at the full rate, so a turret that applies
## the rate for one tick arrives and does not overshoot; a far target slews at the cap. Fire (`FIRE1`) is the caller's.


## Writes the slew rates that turn the muzzle of basis `b` (muzzle `-b.z`) at the site with unit normal `n` toward the
## unit direction `dir` into `out.pitch` / `out.yaw`; returns the angle between the muzzle and `dir` (rad). A zero
## `turn_rad_s` or `dt` commands no slew. At the pole (muzzle or target along `n`) no azimuth is defined: yaw is 0
## (guard: a horizontal part under about 0.18 deg of the pole). A target exactly behind (180 deg) turns left (+yaw).
static func slew(b: Basis, n: Vector3, dir: Vector3, turn_rad_s: float, dt: float, out: PilotInput) -> float:
	var fwd: Vector3 = -b.z
	var ang: float = atan2(fwd.cross(dir).length(), fwd.dot(dir))
	var step: float = turn_rad_s * dt
	if step <= 0.0:
		out.pitch = 0.0
		out.yaw = 0.0
		return ang
	var hf: Vector3 = fwd - n * fwd.dot(n)   # horizontal parts (tangent to the site)
	var hd: Vector3 = dir - n * dir.dot(n)
	var el_err: float = atan2(dir.dot(n), hd.length()) - atan2(fwd.dot(n), hf.length())
	var az_err: float = 0.0
	if not is_zero_approx(hf.length_squared()) and not is_zero_approx(hd.length_squared()):   # pole guard
		var side: float = n.dot(hf.cross(hd))
		var along: float = hf.dot(hd)
		az_err = PI if (along < 0.0 and is_zero_approx(side)) else atan2(side, along)   # exactly behind: turn left
	var p: float = el_err / step
	var y: float = az_err / step
	var m: float = sqrt(p * p + y * y)
	if m > 1.0:
		p /= m
		y /= m
	out.pitch = p
	out.yaw = y
	return ang
