class_name DockLawRig extends RefCounted
## Auto-dock harness for AI-05: the TA-30 spike's L4-L6 law (SfAutopilot.dock_step: TRANSITION, HOVER-DESCENT,
## FLARE and the 05 s5.5 position law) driving FlightController.track_thrust_vector instead of the spike's
## attitude loop, on the flat datum, with the R0 B.5 touchdown rule (Collision.landing_band) on a stub pad.
## Not a contract: AI-09's LandingController replaces the law; this rig only proves the controller lands.

enum Phase { TRANSITION, HOVER, FLARE }
enum Outcome { LANDED, DAMAGED, CRASHED, OFF_PAD, TIMEOUT }

var phase: Phase = Phase.TRANSITION
var pad_n: Vector3
var pad_p: Vector3
var def: ShipDef
var common: FlightCommonDef
var rules: RulesDef
var g: FlightGains
var touchdown: Vector4 = Vector4.ZERO   ## sink, horizontal speed, tilt deg, offset m at contact
var ticks: int = 0
var scrapes: int = 0                    ## off-pad terrain contact episodes below terrain_damage_speed this run
var _l: Dictionary
var _flat: Terrain = Terrain.new()


func _init(ship: ShipDef, flight_common: FlightCommonDef, rules_def: RulesDef) -> void:
	def = ship
	common = flight_common
	rules = rules_def
	g = Ai05Kit.gains(def, rules)
	_l = Ai05Kit.block("landing")
	pad_n = Ai05Kit.geo(_n("pad_lat_deg"), _n("pad_lon_deg"))
	pad_p = pad_n * Sphere.PLANET_RADIUS


func _n(k: String) -> float:
	return Ai05Kit.num(_l, k)


## One tick of the law (05 s5.5 L4-L6, spike values): writes `out` through track_thrust_vector.
func law(s: ShipState, out: PilotInput) -> void:
	var rel: Vector3 = pad_p - s.p
	var e: Vector3 = rel - pad_n * rel.dot(pad_n)
	var w: Vector3 = s.v - pad_n * s.v.dot(pad_n)
	var h: float = -rel.dot(pad_n) - def.bounding_radius
	var vz: float = s.v.dot(pad_n)
	if phase == Phase.TRANSITION and w.length() < _n("transition_exit_hspeed_mps") \
			and e.length() < _n("transition_exit_dist_m"):
		phase = Phase.HOVER
	var centred: float = clampf(1.0 - e.length() / _n("pad_radius_m"), 0.0, 1.0)
	if phase == Phase.HOVER and h < _n("flare_agl_m") and centred > 0.5:
		phase = Phase.FLARE
	var vz_cmd: float = 0.0
	var tan_lim: float = tan(deg_to_rad(_n("max_tilt_deg")))
	if phase == Phase.TRANSITION:
		tan_lim = tan(deg_to_rad(_n("transition_max_tilt_deg")))
	elif phase == Phase.HOVER:
		vz_cmd = -clampf(_n("sink_gain") * h, _n("sink_min_mps"), _n("sink_max_mps")) * centred
		if centred <= 0.5 and h < _n("flare_agl_m"):
			vz_cmd = minf(_n("sink_gain") * (_n("flare_agl_m") - h), _n("sink_min_mps"))
	else:
		vz_cmd = -_n("touch_vz_mps") * centred
		tan_lim = tan(deg_to_rad(_n("flare_tilt_deg")))
	var w_cmd: Vector3 = (e * (_n("kp_pos") / _n("kd_pos"))).limit_length(_n("transition_speed_cap_mps"))
	var a_h: Vector3 = (w_cmd - w) * _n("kd_pos")
	var a_v: float = _n("kp_vz") * (vz_cmd - vz) + rules.gravity
	var t: Vector3 = a_h.limit_length(maxf(a_v, 0.0) * tan_lim) + pad_n * a_v
	var alt: float = s.p.length() - Sphere.PLANET_RADIUS
	var eff: float = Kinematics.thrust_efficiency(s.v.dot(s.fwd), def.v_cruise, common.eff_fade_start) \
		* Kinematics.ceiling_efficiency(alt, rules)
	var mag01: float = t.length() / maxf(def.a_thrust * eff, 0.001)
	FlightController.track_thrust_vector(Ai05Kit.basis(s), t, mag01, s.p.normalized(), g, out)
	out.buttons = PilotInput.DOCK
	if phase == Phase.TRANSITION and s.fwd.dot(pad_n) < cos(deg_to_rad(_n("transition_nose_deg"))) \
			and s.v.dot(s.fwd) > 0.0:
		out.buttons |= PilotInput.BRAKE


## Flies `s` with DOCK held until the pad contact or the timeout. Inside the pad volume the contact is classified
## with Collision.landing_band (R0 B.5 limits). Off the pad, a terrain contact at or below terrain_damage_speed is
## a scrape (03 s6.1): counted per episode and flown on, as the spike's world did; a harder one is OFF_PAD.
func run(s: ShipState) -> Outcome:
	phase = Phase.TRANSITION
	scrapes = 0
	var in_contact: bool = false
	var inp: PilotInput = PilotInput.new()
	var limit: int = int(_n("timeout_s") * float(rules.tick_hz))
	for i: int in limit:
		ticks = i + 1
		law(s, inp)
		Ai05Kit.step(s, inp, def, common, rules, _flat)
		var rel: Vector3 = s.p - pad_p
		var hh: float = rel.dot(pad_n)
		var off: float = (rel - pad_n * hh).length()
		var in_vol: bool = off <= _n("pad_radius_m") and hh <= def.bounding_radius + _n("pad_contact_margin_m")
		if not (in_vol or s.terrain_hit):
			in_contact = in_contact and Ai05Kit.agl(s, _flat) - def.bounding_radius < _n("contact_release_m")
			continue
		var sink: float = s.hit_normal_speed if s.terrain_hit else -s.v.dot(pad_n)
		var v_hor: float = (s.v - pad_n * s.v.dot(pad_n)).length()
		var tilt: float = rad_to_deg(s.fwd.angle_to(pad_n))
		touchdown = Vector4(sink, v_hor, tilt, off)
		if not in_vol:
			if Collision.classify_terrain(sink, common) != Collision.T_SCRAPE:
				return Outcome.OFF_PAD
			if not in_contact:
				scrapes += 1
			in_contact = true
			continue
		var band: int = Collision.landing_band(sink, v_hor, tilt, common)
		if band == Collision.L_SAFE:
			return Outcome.LANDED
		return Outcome.DAMAGED if band == Collision.L_DAMAGE else Outcome.CRASHED
	return Outcome.TIMEOUT


## The spike harness start state (sf_harness _start_state, dock_only): inside auto_dock_radius_m in 3D, random
## bearing and heading, speed up to dock speed_max (or 40 m/s .. v_cruise when `fast`).
func start_state(rng: Rng, fast: bool) -> ShipState:
	var dr: Dictionary = Ai05Kit.block("dock_runs")
	var alt: float = rng.range_f(Ai05Kit.num(dr, "alt_min_m"), Ai05Kit.num(dr, "alt_max_m"))
	var d_max: float = Ai05Kit.num(dr, "dist_max_m")
	d_max = sqrt(maxf(d_max * d_max - alt * alt, 0.0))
	var dist: float = rng.range_f(0.0, d_max)
	var bearing: float = deg_to_rad(rng.range_f(0.0, 360.0))
	var f: Basis = Sphere.tangent_frame(pad_n)
	var dir: Vector3 = (f.y * cos(bearing) + f.x * sin(bearing)).normalized()   # north = y, east = x
	var p_dir: Vector3 = pad_n.rotated(pad_n.cross(dir).normalized(), dist / Sphere.PLANET_RADIUS) \
		if dist > 0.0 else pad_n
	var p: Vector3 = p_dir * (Sphere.PLANET_RADIUS + alt + def.bounding_radius)
	var n: Vector3 = p.normalized()
	var to_pad: Vector3 = pad_p - p
	to_pad = to_pad - n * to_pad.dot(n)
	to_pad = to_pad.normalized() if to_pad.length_squared() > 0.0 else Sphere.tangent_frame(n).y
	var spread: float = deg_to_rad(Ai05Kit.num(dr, "heading_spread_deg"))
	var heading: Vector3 = to_pad.rotated(n, rng.range_f(-spread, spread) * 0.5)
	var speed: float = rng.range_f(0.0, Ai05Kit.num(dr, "speed_max_mps"))
	if fast:
		speed = rng.range_f(Ai05Kit.num(dr, "speed_max_mps"), def.v_cruise)
	heading = heading.rotated(n, rng.range_f(-PI, PI))
	return FlightTestKit.spawn(def, p, heading, n, heading * speed)
