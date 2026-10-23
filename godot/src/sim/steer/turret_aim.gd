class_name TurretAim extends RefCounted
## Tower slew law (05 s6.8, R0 C2-09; AI-17). Static and pure (S8, 03 s5.6): a function of its arguments only, so the
## same law serves the tower brain and any later prediction. A tower's `PilotInput.pitch` / `yaw` are slew rates as a
## fraction of `turret_turn_dps` about the body right (`b.x`) and up (`b.y`) axes, the ship stick convention
## (`Kinematics._stick_tick`): positive pitch raises the muzzle, positive yaw turns it left, the muzzle is `-b.z`.
## The command is the dead-beat rate: the rotation error over one tick at the full turn rate, clamped to +-1, so a
## turret that applies the rate for one tick arrives and does not overshoot, and one that is further away slews at the
## cap. Fire (`FIRE1`) is the caller's.


## Writes the slew rates that turn the muzzle of basis `b` toward the unit direction `dir` into `out.pitch` / `out.yaw`;
## returns the angle between the muzzle and `dir` (rad). A zero `turn_rad_s` or `dt` commands no slew.
static func slew(b: Basis, dir: Vector3, turn_rad_s: float, dt: float, out: PilotInput) -> float:
	var fwd: Vector3 = -b.z
	var axis: Vector3 = fwd.cross(dir)
	var s: float = axis.length()
	var c: float = fwd.dot(dir)
	var ang: float = atan2(s, c)
	var step: float = turn_rad_s * dt
	if step <= 0.0:
		out.pitch = 0.0
		out.yaw = 0.0
		return ang
	var e: Vector3 = axis * (ang / s) if s > 0.0 else (b.y * PI if c < 0.0 else Vector3.ZERO)
	out.pitch = clampf(e.dot(b.x) / step, -1.0, 1.0)
	out.yaw = clampf(e.dot(b.y) / step, -1.0, 1.0)
	return ang
