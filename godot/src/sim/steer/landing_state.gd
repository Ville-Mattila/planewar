class_name LandingState extends RefCounted
## Per-landing memory of LandingController (05 s5.5): the only state the controller reads and writes besides its
## output. The caller keeps the fields per entity (sim_ai AiState arrays, Assist's input slot) and copies them in
## and out of one reused instance, so the controller stays a pure function of its arguments (S8).

var phase: int = 0                     ## LandingController.Phase
var attempts: int = 0                  ## go-arounds flown on this pad (L3 count)
var abort_reason: int = 0              ## LandingController.Abort of the last abort; NONE after a reset
var bearing: Vector3 = Vector3.ZERO    ## approach bearing: unit tangent at the pad toward where L2 comes from; ZERO = unset
var mark: Vector3 = Vector3.ZERO       ## L3: unit direction over the planet where the go-around started
var ga_dir: Vector3 = Vector3.ZERO     ## L3: unit tangent at the pad along which the go-around extends
var integ: Vector2 = Vector2.ZERO      ## FlightController.track_velocity integrators (reset on a phase change)
var assist_off: bool = false           ## Assist.auto_dock gave up (pad lost or taken): off until DOCK is released
var assist_near: bool = false          ## Assist.auto_dock acted within auto_dock_radius_m of the pad: the landing is AUTO (05 s5.5)


## Back to L1 TRANSIT with no bearing, no attempts and no abort (a new RETURN or a new pad).
func reset() -> void:
	phase = 0
	attempts = 0
	abort_reason = 0
	bearing = Vector3.ZERO
	mark = Vector3.ZERO
	ga_dir = Vector3.ZERO
	integ = Vector2.ZERO
	assist_off = false
	assist_near = false


## DOCK released (or the latch lost): back to L1 and the assist re-armed, but `assist_near` survives so a manual
## finish after an assisted approach inside the grading radius still grades AUTO; `reset()` clears it per landing.
func release() -> void:
	phase = 0
	integ = Vector2.ZERO
	assist_off = false
