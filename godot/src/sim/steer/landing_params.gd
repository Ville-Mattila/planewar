class_name LandingParams extends RefCounted
## Parameter struct of LandingController (05 s5.5, AI-09): the autopilot def's `landing` block plus the profile's
## `cruise_alt_agl_m`, the guidance gains of the velocity phases and rules.gravity. One instance per autopilot
## profile, read-only to the controller. No numeric defaults live here (ADR-09): build it with `from_dict`.
## Angles are stored as radians and as the tangent / cosine the laws use.

## Keys `from_dict` requires (05 s4.4 `landing` block, the 05 s5.5 prose numbers and the AI-09 additions listed in
## sim/steer/MODULE.md).
const KEYS: PackedStringArray = ["cruise_alt_agl_m", "gate_dist_m", "glide_deg", "glide_tol_m", "transition_dist_m",
	"approach_min_speed_mps", "approach_lookahead_m", "approach_capture_deg", "kp_alt", "vz_max_mps", "turn_cmd_max_deg",
	"hold_radius_m", "hold_agl_m", "hold_speed_mps", "goaround_agl_m", "goaround_extend_m", "max_attempts",
	"kp_pos", "kd_pos", "kp_vz", "max_tilt_deg", "transition_max_tilt_deg", "transition_nose_deg",
	"transition_exit_hspeed_mps", "transition_exit_dist_m", "transition_speed_cap_mps", "floor_agl_m", "kp_floor",
	"floor_tilt_deg", "sink_gain", "sink_min_mps", "sink_max_mps", "flare_agl_m", "flare_tilt_deg", "touch_vz_mps",
	"abort_horiz_err_m", "abort_horiz_agl_m", "abort_vz_mps", "abort_vz_agl_m", "abort_tti_s",
	"bearing_count", "bearing_samples", "bearing_clear_m", "bearing_terrain_weight"]

var gravity: float = 0.0               ## rules.gravity (m/s^2), never hard-coded (05 s5.5)
var cruise_alt_agl_m: float = 0.0      ## L1 TRANSIT altitude above the terrain under the ship
var gate_dist_m: float = 0.0           ## L1 -> L2 great-circle distance to the pad
var tan_glide: float = 0.0             ## tan(glide_deg): L2 target height h(d) = d tan(glide) above the pad
var glide_tol_m: float = 0.0           ## L2 -> L4 needs |h - h(d)| <= this at transition_dist_m, else L3
var transition_dist_m: float = 0.0     ## L2 -> L4 distance
var approach_min_speed: float = 0.0    ## L2 speed schedule floor (at transition_dist_m)
var approach_lookahead_m: float = 0.0  ## L2 pure-pursuit lookahead along the approach line
var tan_capture: float = 0.0           ## L2 flies to the gate fix while |cross track| > along track * this
var kp_alt: float = 0.0                ## 1/s: vertical speed per m of height error (velocity phases)
var vz_max: float = 0.0                ## m/s: vertical speed command clamp (velocity phases)
var turn_cmd_max: float = 0.0           ## rad: guidance direction limit off the current track (velocity phases)
var hold_radius_m: float = 0.0         ## L2b orbit radius about the pad
var hold_agl_m: float = 0.0            ## L2b orbit height
var hold_speed: float = 0.0            ## L2b orbit speed
var goaround_agl_m: float = 0.0        ## L3 climb target
var goaround_extend_m: float = 0.0     ## L3 leg length before re-entering L2
var max_attempts: int = 0              ## L3 count above which the caller selects a different pad
var kp_pos: float = 0.0                ## 1/s^2: L4-L6 position gain
var kd_pos: float = 0.0                ## 1/s: L4-L6 horizontal velocity gain
var kp_vz: float = 0.0                 ## 1/s: L4-L6 vertical speed gain
var tan_tilt: float = 0.0              ## L5 thrust-axis tilt limit from the pad normal (max_tilt_deg)
var tan_transition_tilt: float = 0.0   ## L4 tilt limit (A-34 transition_max_tilt_deg)
var cos_transition_nose: float = 0.0   ## L4 brakes while the nose is further than this from the pad normal
var transition_exit_hspeed: float = 0.0   ## L4 -> L5 horizontal speed
var transition_exit_dist_m: float = 0.0   ## L4 -> L5 horizontal distance to the pad centre
var transition_speed_cap: float = 0.0  ## L4-L6 horizontal speed command cap
var floor_agl_m: float = 0.0           ## L4-L5 height floor while not over the pad (AI-09: no scrapes)
var kp_floor: float = 0.0              ## 1/s: climb rate per m below the floor
var tan_floor_tilt: float = 0.0        ## tilt limit while below the floor (vertical authority first)
var sink_gain: float = 0.0             ## L5 sink = clamp(sink_gain * h, sink_min, sink_max)
var sink_min: float = 0.0
var sink_max: float = 0.0
var flare_agl_m: float = 0.0           ## L5 -> L6 height
var tan_flare_tilt: float = 0.0        ## L6 tilt limit (thrust axis within 10 degrees, SC-02)
var touch_vz: float = 0.0              ## L6 sink
var abort_horiz_err_m: float = 0.0     ## abort: horizontal error above this ...
var abort_horiz_agl_m: float = 0.0     ## ... below this height (L5-L6)
var abort_vz: float = 0.0              ## abort: sink above this ...
var abort_vz_agl_m: float = 0.0        ## ... below this height (L4-L6)
var abort_tti_s: float = 0.0           ## abort: TerrainProbe TTI below this with an impact point off the pad
var bearing_count: int = 0             ## choose_bearing candidates (05: 8, 45 degree steps)
var bearing_samples: int = 0           ## terrain samples per candidate line
var bearing_clear_m: float = 0.0       ## clearance the approach line needs above the terrain (SC-05: 60 m)
var bearing_terrain_weight: float = 0.0   ## score per m of clearance shortfall


## Builds the struct from the `landing` dictionary and rules.gravity. Returns null when a key of KEYS is missing
## or not a number (a broken def is a load error, not a default).
static func from_dict(landing: Dictionary, gravity_mps2: float) -> LandingParams:
	for k: String in KEYS:
		var x: Variant = landing.get(k)
		if not (x is float or x is int):
			return null
	var p: LandingParams = LandingParams.new()
	p.gravity = gravity_mps2
	p.cruise_alt_agl_m = _f(landing, "cruise_alt_agl_m")
	p.gate_dist_m = _f(landing, "gate_dist_m")
	p.tan_glide = tan(deg_to_rad(_f(landing, "glide_deg")))
	p.glide_tol_m = _f(landing, "glide_tol_m")
	p.transition_dist_m = _f(landing, "transition_dist_m")
	p.approach_min_speed = _f(landing, "approach_min_speed_mps")
	p.approach_lookahead_m = _f(landing, "approach_lookahead_m")
	p.tan_capture = tan(deg_to_rad(_f(landing, "approach_capture_deg")))
	p.kp_alt = _f(landing, "kp_alt")
	p.vz_max = _f(landing, "vz_max_mps")
	p.turn_cmd_max = deg_to_rad(_f(landing, "turn_cmd_max_deg"))
	p.hold_radius_m = _f(landing, "hold_radius_m")
	p.hold_agl_m = _f(landing, "hold_agl_m")
	p.hold_speed = _f(landing, "hold_speed_mps")
	p.goaround_agl_m = _f(landing, "goaround_agl_m")
	p.goaround_extend_m = _f(landing, "goaround_extend_m")
	p.max_attempts = int(_f(landing, "max_attempts"))
	p.kp_pos = _f(landing, "kp_pos")
	p.kd_pos = _f(landing, "kd_pos")
	p.kp_vz = _f(landing, "kp_vz")
	p.tan_tilt = tan(deg_to_rad(_f(landing, "max_tilt_deg")))
	p.tan_transition_tilt = tan(deg_to_rad(_f(landing, "transition_max_tilt_deg")))
	p.cos_transition_nose = cos(deg_to_rad(_f(landing, "transition_nose_deg")))
	p.transition_exit_hspeed = _f(landing, "transition_exit_hspeed_mps")
	p.transition_exit_dist_m = _f(landing, "transition_exit_dist_m")
	p.transition_speed_cap = _f(landing, "transition_speed_cap_mps")
	p.floor_agl_m = _f(landing, "floor_agl_m")
	p.kp_floor = _f(landing, "kp_floor")
	p.tan_floor_tilt = tan(deg_to_rad(_f(landing, "floor_tilt_deg")))
	p.sink_gain = _f(landing, "sink_gain")
	p.sink_min = _f(landing, "sink_min_mps")
	p.sink_max = _f(landing, "sink_max_mps")
	p.flare_agl_m = _f(landing, "flare_agl_m")
	p.tan_flare_tilt = tan(deg_to_rad(_f(landing, "flare_tilt_deg")))
	p.touch_vz = _f(landing, "touch_vz_mps")
	p.abort_horiz_err_m = _f(landing, "abort_horiz_err_m")
	p.abort_horiz_agl_m = _f(landing, "abort_horiz_agl_m")
	p.abort_vz = _f(landing, "abort_vz_mps")
	p.abort_vz_agl_m = _f(landing, "abort_vz_agl_m")
	p.abort_tti_s = _f(landing, "abort_tti_s")
	p.bearing_count = maxi(int(_f(landing, "bearing_count")), 1)
	p.bearing_samples = maxi(int(_f(landing, "bearing_samples")), 1)
	p.bearing_clear_m = _f(landing, "bearing_clear_m")
	p.bearing_terrain_weight = _f(landing, "bearing_terrain_weight")
	return p


static func _f(d: Dictionary, k: String) -> float:
	var x: Variant = d[k]
	if x is int:
		var i: int = x
		return float(i)
	var f: float = x
	return f
