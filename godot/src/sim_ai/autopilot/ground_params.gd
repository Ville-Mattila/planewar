class_name GroundParams extends RefCounted
## The ground follower's numbers (05 s5.7, AI-16): the autopilot def's `follow` block plus the BRAKE hold of
## `ground_common` (R0 C2-09), read-only. Shared by every ground brain (Harvester now, Siege Crawler with AI-18).
## No numeric defaults (ADR-09): a missing or non-numeric key makes `from_dict` return null.

const KEYS: PackedStringArray = ["lookahead_m", "kp_yaw", "thrust_turn", "turn_slow_deg", "pivot_m", "arrive_m",
	"path_wait_ticks", "stuck_progress_m", "stuck_window_s", "deviate_m", "aim_every_ticks"]

var lookahead_m: float = 0.0       ## pure-pursuit lookahead (40 m)
var kp_yaw: float = 0.0            ## yaw = kp_yaw x heading error in radians, clamped to +-1 (2.0)
var thrust_turn: float = 0.0       ## thrust at a heading error of `turn_slow_rad` and beyond (0.4); 1.0 on a straight leg
var turn_slow_rad: float = 0.0     ## the heading error at which thrust has fallen to `thrust_turn` (45 degrees)
var pivot_m: float = 0.0           ## within this of the goal a unit with a heading error beyond `turn_slow_rad` turns on the spot
var arrive_m: float = 0.0          ## flat distance at which the goal is reached
var path_wait_ticks: int = 0       ## a ticket not answered in this many ticks is one stuck strike (30)
var stuck_progress_m: float = 0.0  ## less progress than this in a window is a strike (5 m)
var stuck_window_ticks: int = 0    ## the window (10 s)
var deviate_m: float = 0.0         ## farther than this from the route: repath (a possession, a push)
var aim_every_ticks: int = 1       ## the aim point is rescanned this often per unit (staggered by slot), cached between (4)
var brake_ticks: int = 0           ## BRAKE is held at most this many ticks in a row: one tick short of the sim's reverse hold


## `follow` = the autopilot's `follow` dictionary; null on a missing key or a non-positive value.
static func from_dict(follow: Dictionary, common: GroundCommonDef, tick_hz: int) -> GroundParams:
	for k: String in KEYS:
		if TargetParams.num(follow, k, 0.0) <= 0.0:
			return null
	var p: GroundParams = GroundParams.new()
	p.lookahead_m = TargetParams.num(follow, "lookahead_m", 0.0)
	p.kp_yaw = TargetParams.num(follow, "kp_yaw", 0.0)
	p.thrust_turn = TargetParams.num(follow, "thrust_turn", 0.0)
	p.turn_slow_rad = deg_to_rad(TargetParams.num(follow, "turn_slow_deg", 0.0))
	p.pivot_m = TargetParams.num(follow, "pivot_m", 0.0)
	p.arrive_m = TargetParams.num(follow, "arrive_m", 0.0)
	p.path_wait_ticks = roundi(TargetParams.num(follow, "path_wait_ticks", 0.0))
	p.stuck_progress_m = TargetParams.num(follow, "stuck_progress_m", 0.0)
	p.stuck_window_ticks = roundi(TargetParams.num(follow, "stuck_window_s", 0.0) * float(tick_hz))
	p.deviate_m = TargetParams.num(follow, "deviate_m", 0.0)
	p.aim_every_ticks = maxi(roundi(TargetParams.num(follow, "aim_every_ticks", 1.0)), 1)
	p.brake_ticks = maxi(ceili(common.ground_reverse_hold_s * float(tick_hz) - 0.5) - 1, 0)
	return p
