extends Node
## S-FLIGHT-1 headless measurements (TA-30 REPORT s3). A scene, not a -s script, so the autoloads exist. Run:
##   godot --headless --path godot res://spikes/s_flight_1/harness/sf_harness.tscn -- [--csv-dir=<abs dir>] [--quick]
## Prints `MEAS <name> <value>` lines; with --csv-dir writes autoland_runs.csv and dock_runs.csv there.

var _d: SfDefs
var _csv_dir: String = ""
var _quick: bool
var _trace: int = -1
var _trace_dock: bool
var _fast: bool


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--csv-dir="):
			_csv_dir = a.substr("--csv-dir=".length())
		elif a == "--quick":
			_quick = true
		elif a.begins_with("--trace-dock="):
			_trace = a.substr("--trace-dock=".length()).to_int()
			_trace_dock = true
		elif a.begins_with("--trace-fast="):
			_trace = a.substr("--trace-fast=".length()).to_int()
			_trace_dock = true
			_fast = true
		elif a.begins_with("--trace-land="):
			_trace = a.substr("--trace-land=".length()).to_int()
	_d = SfDefs.load_all()
	print("MEAS sources %s" % ",".join(_d.sources))
	if _trace >= 0:
		_autoland_runs(_trace_dock)
		get_tree().quit(0)
		return
	_aoa_runs()
	_gun_runs()
	_flip_run()
	_hover_runs()
	_interp_run()
	_autoland_runs(false)
	_autoland_runs(true)
	_fast = true
	_autoland_runs(true)
	_fast = false
	_tick_cost()
	get_tree().quit(0)


# Steady level-flight angle of attack under both lift models (03 s5.3 lift law check; 14.6 AoA <= 6 deg).
func _aoa_runs() -> void:
	var hb: Dictionary = _d.harness
	var lift0: StringName = _d.rules.lift_model
	for model: StringName in [RulesDef.LIFT_SPEED_SCALED, RulesDef.LIFT_DAMPING_ONLY]:
		_d.rules.lift_model = model
		for sid: StringName in [&"dart", &"bomber"]:
			for fv: Variant in SfDefs.arr(hb, "aoa_speed_fracs"):
				var frac: float = fv
				var r: Vector3 = _aoa_one(_d.ships[sid], frac)
				print("MEAS aoa_deg %s %s v=%.2fxcruise mean=%.2f alt_err_max=%.2f thrust=%.3f" % [model, sid, frac,
					r.x, r.y, r.z])
	_d.rules.lift_model = lift0


func _aoa_one(def: ShipDef, frac: float) -> Vector3:
	var hb: Dictionary = _d.harness
	var ship0: ShipDef = _d.ship
	_d.ship = def
	var w: SfWorld = SfWorld.new(_d, 1)
	var h0: float = SfDefs.num(hb, "aoa_alt_m")
	var n: Vector3 = w.pad_n
	var east: Vector3 = Sphere.tangent_frame(w.pad_p).x
	w.place(n * (Sphere.PLANET_RADIUS + h0 + def.bounding_radius), east, n, east * def.v_cruise * frac)
	var inp: PilotInput = PilotInput.new()
	var ap: SfAutopilot = SfAutopilot.new(_d)
	var settle: int = int(SfDefs.num(hb, "aoa_settle_s") * _d.rules.tick_hz)
	var meas: int = int(SfDefs.num(hb, "aoa_measure_s") * _d.rules.tick_hz)
	var aoa_sum: float = 0.0
	var err: float = 0.0
	var thr: float = 0.0
	for i: int in settle + meas:
		ap.hold(w.s, def, h0, def.v_cruise * frac, Vector3.ZERO, inp)
		w.step(inp)
		if i >= settle:
			aoa_sum += w.aoa_deg()
			err = maxf(err, absf(w.altitude() - h0))
			thr += inp.thrust
	_d.ship = ship0
	return Vector3(aoa_sum / float(meas), err, thr / float(meas))


# Co-altitude straight-line gun (03 s5.4 test_slug_hits_coaltitude_target, through the spike's own arena).
func _gun_runs() -> void:
	var hb: Dictionary = _d.harness
	for dv: Variant in SfDefs.arr(hb, "gun_dists_m"):
		var dist: float = dv
		var w: SfWorld = SfWorld.new(_d, 7)
		w.arena.clear_targets()
		var alt: float = SfDefs.num(hb, "gun_alt_m")
		var p: Vector3 = w.pad_n * (Sphere.PLANET_RADIUS + alt)
		var tgt: Vector3 = SfArena.place(p, 90.0, dist * Sphere.PLANET_RADIUS / (Sphere.PLANET_RADIUS + alt), alt)   # dist = range at altitude
		var _k: int = w.arena.add_target(tgt, false)
		var los: Vector3 = (tgt - p).normalized()
		w.place(p, los, w.pad_n, los * _d.ship.v_cruise)
		var inp: PilotInput = PilotInput.new()
		inp.buttons = PilotInput.FIRE1
		inp.thrust = 0.5
		var burst: int = int(SfDefs.num(hb, "gun_burst_s") * _d.rules.tick_hz)
		for i: int in burst:
			_aim(w, tgt)                # a pilot holding the pipper on the target ("hit when aimed")
			w.step(inp)
			w.arena.t_hp[0] = 1.0e9    # keep the target alive: count every hit
		inp.buttons = 0
		for i: int in _d.rules.tick_hz * 2:
			w.step(inp)
		print("MEAS gun_coalt dist=%d shots=%d hits=%d rate=%.2f" % [int(dist), w.arena.shots, w.arena.slug_hits,
			float(w.arena.slug_hits) / maxf(float(w.arena.shots), 1.0)])


# Flip at cruise: speed kept and height change (03 s5.3 flip semantics: about 25 % speed loss).
func _flip_run() -> void:
	var w: SfWorld = SfWorld.new(_d, 3)
	var h0: float = 300.0
	var east: Vector3 = Sphere.tangent_frame(w.pad_p).x
	w.place(w.pad_n * (Sphere.PLANET_RADIUS + h0), east, w.pad_n, east * _d.ship.v_cruise)
	var inp: PilotInput = PilotInput.new()
	inp.thrust = 0.5
	inp.buttons = PilotInput.FLIP
	w.step(inp)
	inp.buttons = 0
	for i: int in int(_d.ship.flip_duration_s * _d.rules.tick_hz) + 1:
		w.step(inp)
	_flip_print(w, east, h0, "end")
	for i: int in _d.rules.tick_hz:
		w.step(inp)
	_flip_print(w, east, h0, "+1s")
	for i: int in _d.rules.tick_hz * 2:
		w.step(inp)
	_flip_print(w, east, h0, "+3s")


func _flip_print(w: SfWorld, east: Vector3, h0: float, at: String) -> void:
	var sp: float = w.s.v.length()
	print("MEAS flip %s speed=%.1f loss=%.0f%% dh=%.1f vel_dot_east=%.2f nose_dot_east=%.2f" % [at, sp,
		100.0 * (1.0 - sp / _d.ship.v_cruise), w.altitude() - h0, w.s.v.normalized().dot(east), w.s.fwd.dot(east)])


func _aim(w: SfWorld, tgt: Vector3) -> void:
	var los: Vector3 = (tgt - w.s.p).normalized()
	w.s.fwd = los
	w.s.up = (w.s.p.normalized() - los * w.s.p.normalized().dot(los)).normalized()
	w.s.rates = Vector3.ZERO


# Tail-down hover for Dart and Bomber: hover throttle and the tilt the controller can hold at 1 g vertical.
func _hover_runs() -> void:
	for sid: StringName in [&"dart", &"bomber"]:
		var def: ShipDef = _d.ships[sid]
		var hover: float = _d.rules.gravity / def.a_thrust
		var tilt_max: float = rad_to_deg(acos(minf(hover, 1.0)))
		print("MEAS hover %s a_thrust/g=%.2f hover_throttle=%.3f max_tilt_at_1g=%.1f" % [sid,
			def.a_thrust / _d.rules.gravity, hover, tilt_max])


# Render interpolation at an exact 60 fps over the 30 Hz sim (03 s10.1 test: variance < 10 % of the mean).
func _interp_run() -> void:
	var w: SfWorld = SfWorld.new(_d, 5)
	var east: Vector3 = Sphere.tangent_frame(w.pad_p).x
	w.place(w.pad_n * (Sphere.PLANET_RADIUS + 300.0), east, w.pad_n, east * _d.ship.v_cruise)
	var ap: SfAutopilot = SfAutopilot.new(_d)
	var inp: PilotInput = PilotInput.new()
	var frames: int = 600
	var last: Vector3 = w.s.p
	var disp: PackedFloat64Array = PackedFloat64Array()
	var hz: float = float(_d.rules.tick_hz)
	var ticks_done: int = 0
	var per: int = roundi(60.0 / hz)          # frames per tick at 60 fps (2 at 30 Hz); integer clock, no float drift
	for f: int in frames:
		var target: int = floori(float(f + 1) / float(per))
		while ticks_done < target:
			ap.hold(w.s, _d.ship, 300.0, _d.ship.v_cruise, Vector3.ZERO, inp)
			w.step(inp)
			ticks_done += 1
		var alpha: float = float(posmod(f + 1, per)) / float(per)
		var p: Vector3 = w.prev_p.lerp(w.s.p, alpha)
		if f >= 60:   # skip the first second (spawn transient: prev == current pose on the first tick)
			var _a: bool = disp.push_back(p.distance_to(last))
		last = p
	var m: Vector2 = _mean_std(disp)
	print("MEAS interp60 mean_disp_m=%.3f std_m=%.4f cv=%.2f%%" % [m.x, m.y, 100.0 * m.y / m.x])
	# without interpolation (raw tick pose every frame) for comparison
	var raw: PackedFloat64Array = PackedFloat64Array()
	for f: int in frames:
		var _b: bool = raw.push_back(_d.ship.v_cruise / hz if f % 2 == 0 else 0.0)
	var r: Vector2 = _mean_std(raw)
	print("MEAS interp60_off mean_disp_m=%.3f std_m=%.4f cv=%.2f%%" % [r.x, r.y, 100.0 * r.y / r.x])


# Automated landings: the harness autopilot from random approach states (dock_only = false), or DOCK held from
# random states inside auto_dock_radius_m (dock_only = true; this is the human's auto-dock assist path).
func _autoland_runs(dock_only: bool) -> void:
	var hb: Dictionary = _d.harness
	var runs: int = int(SfDefs.num(hb, "dock_runs" if dock_only else "autoland_runs"))
	if _quick:
		runs = 20
	var rng: Rng = Rng.new(int(SfDefs.num(hb, "seed")) + (1 if dock_only else 0) + (1 if _fast else 0))
	var rows: PackedStringArray = PackedStringArray(["run,outcome,grade,q,v_vert,v_hor,tilt_deg,offset_m,time_s"])
	var ok: int = 0
	var hard: int = 0
	var crash: int = 0
	var timeout: int = 0
	var q_sum: float = 0.0
	var t_sum: float = 0.0
	for k: int in runs:
		var w: SfWorld = SfWorld.new(_d, 11 + k)
		_start_state(w, rng, dock_only)
		if _trace >= 0 and k != _trace:
			continue
		var res: String = _fly(w, dock_only)
		var td: SfTouchdown = w.last_touchdown
		var t_s: float = float(w.tick) / float(_d.rules.tick_hz)
		if res == "LANDED":
			ok += 1
			q_sum += td.q
			t_sum += t_s
		elif res == "HARD":
			hard += 1
		elif res == "CRASH":
			crash += 1
		else:
			timeout += 1
		if td != null:
			var _a: bool = rows.push_back("%d,%s,%s,%.3f,%.2f,%.2f,%.1f,%.2f,%.1f" % [k, res, td.grade_name(), td.q,
				td.v_vert, td.v_hor, td.tilt_deg, td.offset_m, t_s])
		else:
			var _b: bool = rows.push_back("%d,%s,-,0,0,0,0,0,%.1f" % [k, res, t_s])
	var name: String = ("dock_fast_runs" if _fast else "dock_runs") if dock_only else "autoland_runs"
	print("MEAS %s runs=%d landed=%d hard=%d crash=%d timeout=%d success=%.1f%% mean_q=%.3f mean_time_s=%.1f" % [
		name, runs, ok, hard, crash, timeout, 100.0 * float(ok) / float(runs), q_sum / maxf(float(ok), 1.0),
		t_sum / maxf(float(ok), 1.0)])
	if not _csv_dir.is_empty():
		var f: FileAccess = FileAccess.open(_csv_dir.path_join(name + ".csv"), FileAccess.WRITE)
		if f != null:
			var _ok: bool = f.store_string("\n".join(rows) + "\n")
			f.close()


func _start_state(w: SfWorld, rng: Rng, dock_only: bool) -> void:
	var hb: Dictionary = _d.harness
	var key: String = "dock" if dock_only else "autoland"
	var alt: float = rng.range_f(SfDefs.num(hb, key + "_alt_min_m"), SfDefs.num(hb, key + "_alt_max_m"))
	var d_max: float = SfDefs.num(hb, key + "_dist_max_m")
	if dock_only:   # inside auto_dock_radius_m in 3D (the assist's engagement test)
		d_max = sqrt(maxf(d_max * d_max - alt * alt, 0.0))
	var dist: float = rng.range_f(0.0 if dock_only else SfDefs.num(hb, "autoland_dist_min_m"), d_max)
	var bearing: float = rng.range_f(0.0, 360.0)
	var p: Vector3 = SfArena.place(w.pad_p, bearing, dist, alt + _d.ship.bounding_radius)
	var n: Vector3 = p.normalized()
	var to_pad: Vector3 = w.pad_p - p
	to_pad = (to_pad - n * to_pad.dot(n)).normalized()
	var spread: float = deg_to_rad(SfDefs.num(hb, "autoland_heading_spread_deg"))
	var heading: Vector3 = to_pad.rotated(n, rng.range_f(-spread, spread) * 0.5)
	var speed: float
	if dock_only:
		speed = rng.range_f(0.0, SfDefs.num(hb, "dock_speed_max_mps"))
		if _fast:   # DOCK pressed at flight speed (a novice's habit): 40 m/s .. v_cruise
			speed = rng.range_f(SfDefs.num(hb, "dock_speed_max_mps"), _d.ship.v_cruise)
		heading = heading.rotated(n, rng.range_f(-PI, PI))
	else:
		speed = _d.ship.v_cruise * rng.range_f(SfDefs.num(hb, "autoland_speed_min_frac"),
			SfDefs.num(hb, "autoland_speed_max_frac"))
	w.place(p, heading, n, heading * speed)


func _fly(w: SfWorld, dock_only: bool) -> String:
	var ap: SfAutopilot = SfAutopilot.new(_d)
	var inp: PilotInput = PilotInput.new()
	var limit: int = int(SfDefs.num(_d.approach, "timeout_s") * _d.rules.tick_hz)
	for i: int in limit:
		if dock_only:
			inp.thrust = 0.0
			inp.pitch = 0.0
			inp.yaw = 0.0
			inp.roll = 0.0
			inp.buttons = PilotInput.DOCK
		else:
			ap.approach_step(w.s, _d.ship, w.pad_p, w.pad_n, inp)
			inp.buttons &= ~PilotInput.DOCK
		w.step(inp)
		var _e: Array[SfEvent] = w.drain_events()
		if _trace >= 0:
			for e: SfEvent in _e:
				if e.kind == SfEvent.Kind.TOUCHDOWN:
					print("touchdown %s off=%.1f sink=%.1f hp=%.1f" % [e.touchdown.outcome_name(), e.touchdown.offset_m, e.touchdown.v_vert, w.hp])
		if _trace >= 0 and i % 10 == 0:
			var n: Vector3 = w.s.p.normalized()
			print("t=%.1f ph=%d dist=%.0f alt=%.1f vz=%.1f vh=%.1f nose_up=%.2f thr=%.2f p=%.2f y=%.2f r=%.2f btn=%d assist=%s" % [
				float(i) / 30.0, w.ap.phase, w.pad_distance(), w.altitude(), w.s.v.dot(n), (w.s.v - n * w.s.v.dot(n)).length(),
				w.s.fwd.dot(n), w.input.thrust, w.input.pitch, w.input.yaw, w.input.roll, w.input.buttons, w.assist_on])
		if w.state == SfWorld.State.DOCKED:
			return w.last_touchdown.outcome_name()
		if w.state == SfWorld.State.DEAD:
			if _trace >= 0:
				for e: SfEvent in _e:
					print("event %s %s hp=%.1f" % [e.kind_name(), e.reason, w.hp])
			return "CRASH"
	return "TIMEOUT"


func _tick_cost() -> void:
	var w: SfWorld = SfWorld.new(_d, 9)
	var east: Vector3 = Sphere.tangent_frame(w.pad_p).x
	w.place(w.pad_n * (Sphere.PLANET_RADIUS + 300.0), east, w.pad_n, east * _d.ship.v_cruise)
	var inp: PilotInput = PilotInput.new()
	inp.thrust = 0.6
	inp.buttons = PilotInput.FIRE1
	var n: int = 3000
	var t0: int = Time.get_ticks_usec()
	for i: int in n:
		w.step(inp)
		var _e: Array[SfEvent] = w.drain_events()
		if w.ammo < 10:
			w.ammo = _d.gun_ammo
	var us: float = float(Time.get_ticks_usec() - t0) / float(n)
	print("MEAS world_tick_us mean=%.1f (gun firing, %d targets)" % [us, w.arena.t_pos.size()])


static func _mean_std(a: PackedFloat64Array) -> Vector2:
	var m: float = 0.0
	for x: float in a:
		m += x
	m /= float(a.size())
	var v: float = 0.0
	for x: float in a:
		v += (x - m) * (x - m)
	return Vector2(m, sqrt(v / float(a.size())))
