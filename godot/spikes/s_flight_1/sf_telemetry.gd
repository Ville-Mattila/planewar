class_name SfTelemetry extends RefCounted
## Tester telemetry (03 s14.6 list) as CSV in user://s_flight_1/: landing attempts with vertical/horizontal
## speed, tilt, grade q and outcome; crashes; time to first successful landing per input class; flips; cruise
## AoA samples; targets hit; tuning changes. One file per session, rewritten every flush_s and on exit. On web,
## user:// is the browser's IndexedDB, so the panel offers a download.

const HEADER: String = "session,t_s,tick,event,input_class,assist,lift_model,alt_m,speed_mps,v_vert_mps,v_hor_mps,tilt_deg,offset_m,q,grade,outcome,aoa_deg,detail"
const DIR: String = "user://s_flight_1"

var path: String
var session: String
var lines: PackedStringArray = PackedStringArray([HEADER])
var input_class: String = "KBM"
var assist: String = "RAW"
var lift_model: String = ""
var attempts: int
var landed: int
var crashes: int
var _t0_ms: int
var _class_t0: Dictionary[String, float] = {}
var _first_landing: Dictionary[String, float] = {}
var _flush_t: float
var _aoa_t: float
var _p: Dictionary


func _init(params: Dictionary) -> void:
	_p = params
	_t0_ms = Time.get_ticks_msec()
	session = Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_").replace("-", "")
	var _e: Error = DirAccess.make_dir_recursive_absolute(DIR)
	path = "%s/flight_log_%s.csv" % [DIR, session]


func t_s() -> float:
	return float(Time.get_ticks_msec() - _t0_ms) * 0.001


func set_context(cls: String, tier: String, lift: String) -> void:
	if cls != input_class or tier != assist or lift != lift_model:
		input_class = cls
		assist = tier
		lift_model = lift
		if not _class_t0.has(cls):
			_class_t0[cls] = t_s()
		row(null, "context", "")


## One CSV row. `w` may be null (no ship columns).
func row(w: SfWorld, event: String, detail: String, td: SfTouchdown = null) -> void:
	var alt: String = ""
	var spd: String = ""
	var aoa: String = ""
	if w != null:
		alt = "%.1f" % w.altitude()
		spd = "%.2f" % w.s.v.length()
		aoa = "%.2f" % w.aoa_deg()
	var tdc: String = ",,,,,,"
	if td != null:
		tdc = "%.2f,%.2f,%.1f,%.2f,%.3f,%s,%s" % [td.v_vert, td.v_hor, td.tilt_deg, td.offset_m, td.q, td.grade_name(),
			td.outcome_name()]
	var _a: bool = lines.push_back("%s,%.2f,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s" % [session, t_s(), w.tick if w != null else 0,
		event, input_class, assist, lift_model, alt, spd, tdc, aoa, detail.replace(",", ";")])


## Feed one tick's events; also samples cruise AoA every aoa_sample_s.
func on_tick(w: SfWorld, evs: Array[SfEvent], dt: float) -> void:
	for e: SfEvent in evs:
		match e.kind:
			SfEvent.Kind.TOUCHDOWN:
				_touchdown(w, e)
			SfEvent.Kind.CRASH:
				if e.near_pad:
					attempts += 1
				crashes += 1
				row(w, "crash", "%s near_pad=%s" % [e.reason, e.near_pad], w.last_touchdown if e.reason == "crash" else null)
			SfEvent.Kind.TARGET_HIT, SfEvent.Kind.TARGET_DESTROYED:
				var dist: float = w.s.p.distance_to(e.pos)
				var dalt: float = (e.pos.length() - w.s.p.length())
				row(w, e.kind_name().to_lower(), "target=%d ground=%d dist_m=%.0f dalt_m=%.0f dmg=%.1f shots=%d hits=%d" % [
					e.a, w.arena.t_ground[e.a], dist, dalt, e.value, w.arena.shots, w.arena.slug_hits])
			_:
				row(w, e.kind_name().to_lower(), "a=%d v=%.1f" % [e.a, e.value])
	_aoa_t += dt
	if _aoa_t >= SfDefs.num(_p, "aoa_sample_s"):
		_aoa_t = 0.0
		_aoa_sample(w)
	_flush_t += dt
	if _flush_t >= SfDefs.num(_p, "flush_s"):
		_flush_t = 0.0
		flush()


func _touchdown(w: SfWorld, e: SfEvent) -> void:
	var td: SfTouchdown = e.touchdown
	if not e.near_pad:
		row(w, "contact", "off_pad", td)
		return
	attempts += 1
	var ok: bool = td.outcome == SfTouchdown.Outcome.LANDED or td.outcome == SfTouchdown.Outcome.HARD
	if ok:
		landed += 1
	row(w, "landing_attempt", "attempt=%d manual=%s" % [attempts, not w.assisted_final], td)
	if ok and not _first_landing.has(input_class):
		var since: float = t_s() - _class_t0.get(input_class, 0.0)
		_first_landing[input_class] = since
		row(w, "first_landing", "s_since_class_start=%.1f attempts=%d" % [since, attempts], td)


func _aoa_sample(w: SfWorld) -> void:
	if w.state != SfWorld.State.FLYING:
		return
	var n: Vector3 = w.s.p.normalized()
	var v_fwd: float = w.s.v.dot(w.s.fwd)
	if v_fwd < SfDefs.num(_p, "aoa_min_speed_frac") * w.d.ship.v_cruise:
		return
	if absf(w.s.v.dot(n)) > SfDefs.num(_p, "aoa_max_vz_mps"):
		return
	if rad_to_deg(w.s.rates.length()) > SfDefs.num(_p, "aoa_max_rate_dps"):
		return
	if rad_to_deg(asin(clampf(w.s.fwd.dot(n), -1.0, 1.0))) > SfDefs.num(_p, "aoa_max_pitch_deg"):
		return
	row(w, "aoa_sample", "v_fwd=%.1f" % v_fwd)


func summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for k: String in _first_landing:
		var _a: bool = parts.push_back("%s %.0fs" % [k, _first_landing[k]])
	return "attempts %d  landed %d  crashes %d  first landing: %s" % [attempts, landed, crashes,
		", ".join(parts) if parts.size() > 0 else "-"]


func text() -> String:
	return "\n".join(lines) + "\n"


func flush() -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var _ok: bool = f.store_string(text())
	f.close()
