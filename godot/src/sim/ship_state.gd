class_name ShipState extends RefCounted
## Kinematic state of one ship: the reused scratch `Kinematics.step_ship` reads and writes (03 s5.2, R0 B.8 A-7).
## The server copies a slot's fields in, steps, and copies them back; client prediction runs the same function.
## Spawners set `flip_time = -flip_cooldown_s` and `boost_time = -boost_cooldown_s` so both are ready at once,
## `fuel = fuel_s`, and an orthonormal `fwd`/`up` pair.

var p: Vector3                    # world position (m), planet centre at the origin
var v: Vector3                    # world velocity (m/s)
var fwd: Vector3                  # body forward = thrust axis (unit)
var up: Vector3                   # body up (unit, orthogonal to fwd); right = fwd x up
var rates: Vector3                # body rates (rad/s): x pitch (+ nose up), y yaw (+ nose left), z roll (+ right wing down)
var boost_time: float             # > 0 boosting, <= 0 cooling down (clamped at -boost_cooldown_s)
var flip_time: float              # > 0 flipping, <= 0 cooling down (clamped at -flip_cooldown_s)
var fuel: float                   # seconds of full thrust left
var terrain_hit: bool             # this step: pushed out of the terrain (Collision classifies, 03 s6.1)
var hit_normal_speed: float       # this step: speed into the ground along the terrain normal when terrain_hit (m/s)
var ceiling_forced: bool          # this step: altitude at step start >= rules.ceiling_hard_m
var over_dive_excess: float       # this step: speed removed by the v_dive_max clamp (m/s); Combat applies overspeed_dps
