class_name AssistDockRig extends DockLawRig
## AI-10 harness: DockLawRig's world and touchdown classification (flat datum, R0 B.5 rule on a stub pad), but the
## control comes from Assist.auto_dock fed a "human" input: DOCK held, a fixed forward stick, nothing else. The pad
## snapshot is free and valid; the start states lie inside the HORIZONTAL auto-dock radius (A-33).

var st: LandingState = LandingState.new()
var prm: LandingParams
var ship_snap: ShipSnapshot = ShipSnapshot.new()
var pad_snap: PadSnapshot = PadSnapshot.new()
var assist_ticks: int = 0
var radius_m: float
var latch_mult: float


func _init(ship: ShipDef, flight_common: FlightCommonDef, rules_def: RulesDef) -> void:
	super(ship, flight_common, rules_def)
	prm = Ai09Kit.landing(rules_def)
	radius_m = flight_common.auto_dock_radius_m
	latch_mult = flight_common.auto_dock_latch_mult
	pad_snap.p = pad_p
	pad_snap.n = pad_n
	pad_snap.radius_m = _n("pad_radius_m")
	pad_snap.valid = true


func law(s: ShipState, out: PilotInput) -> void:
	Ai09Kit.snapshot(s, def, common, rules, ship_snap)
	out.thrust = 0.6
	out.pitch = 0.0
	out.yaw = 0.0
	out.roll = 0.0
	out.buttons = PilotInput.DOCK
	if Assist.auto_dock(st, ship_snap, pad_snap, prm, g, radius_m, latch_mult, out):
		assist_ticks += 1


func run(s: ShipState) -> Outcome:
	st.reset()
	assist_ticks = 0
	return super.run(s)


## Inside `radius_m` horizontally of the pad, altitude 15-120 m, random bearing / heading, speed in [lo, hi].
func assist_start(rng: Rng, lo: float, hi: float) -> ShipState:
	var dr: Dictionary = Ai05Kit.block("dock_runs")
	var alt: float = rng.range_f(Ai05Kit.num(dr, "alt_min_m"), Ai05Kit.num(dr, "alt_max_m"))
	var dist: float = rng.range_f(0.0, radius_m * 0.95)   # arc length; the pad-frame distance grows with altitude
	var bearing: float = deg_to_rad(rng.range_f(0.0, 360.0))
	var f: Basis = Sphere.tangent_frame(pad_n)
	var dir: Vector3 = (f.y * cos(bearing) + f.x * sin(bearing)).normalized()
	var p_dir: Vector3 = pad_n.rotated(pad_n.cross(dir).normalized(), dist / Sphere.PLANET_RADIUS) \
		if dist > 0.0 else pad_n
	var p: Vector3 = p_dir * (Sphere.PLANET_RADIUS + alt + def.bounding_radius)
	var n: Vector3 = p.normalized()
	var heading: Vector3 = Sphere.tangent_frame(n).y.rotated(n, rng.range_f(-PI, PI))
	var speed: float = rng.range_f(lo, minf(hi, def.v_cruise))
	return FlightTestKit.spawn(def, p, heading, n, heading * speed)
