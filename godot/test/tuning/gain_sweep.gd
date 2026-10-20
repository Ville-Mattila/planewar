class_name GainSweep extends Node
## Gain-tuning harness (AI-06; 05 s5): a headless sweep of FlightGains and LandingParams keys under both lift
## models, a CSV report and the best gain set per model.
##
##   godot --headless --path godot res://test/tuning/gain_sweep.tscn -- --out=DIR [options]
##   (tools/gain_sweep.py wraps this: import, run, summarise)
##
## Stages per model: `base` (the AI-05 / AI-09 anchors), `oat` (one key at a time, multipliers MULTS), `greedy`
## (the improving OAT moves combined one by one), `random` (seeded log-uniform jitter around the greedy best),
## `confirm` (baseline and best on the full seed count), `cross` (each model's best under
## the other model: does one set serve both lift laws). Every evaluation is one CSV row;
## the score (lower is better) is in the `score` column. Seeds are common random numbers across candidates.
##
## Options (after `--`): --out=DIR (required)  --models=speed_scaled,damping_only  --seeds=N (confirm landing seeds,
## default 200)  --dive-seeds=N (default 200)  --quick=N (landing and dive seeds in the search stages, default 24)
## --random=N (default 24)  --given=FILE (evaluate {model:{flight,landing}} at confirm size)  --seed=N (default 606)  --stages=base,oat,greedy,random,confirm,cross  --failures=N (max rows
## of landing_failures.csv per evaluation, default 12)
## Files: sweep.csv, landing_failures.csv, best_gains.json (recommended flight / landing overrides per model).

const MULTS: Array[float] = [0.6, 0.8, 1.25, 1.6]
const FLIGHT_KEYS: PackedStringArray = ["kp_path", "ki_path", "kp_att", "kp_yaw", "kp_turn_thrust", "kp_speed", "ki_speed",
	"t_trim", "brake_overspeed_mps", "lead_max_deg"]
const LANDING_KEYS: PackedStringArray = ["kp_pos", "kd_pos", "kp_vz", "approach_min_speed_mps", "glide_deg",
	"transition_dist_m", "transition_exit_hspeed_mps", "kp_alt", "sink_gain"]
const CLASSES: Array[StringName] = [&"dart", &"lancer", &"bomber", &"scout", &"hauler"]
## (heading step deg, pitch step deg) of the AI-05 acceptance (test_flight_controller.gd).
const STEPS: Array[Vector2] = [Vector2(30, 0), Vector2(-30, 0), Vector2(0, 15), Vector2(0, -15), Vector2(20, 10)]
const T_MAX_S: float = 2.0
const OVERSHOOT_MAX: float = 0.15
const T_MAX_DIVE_DAMPING_S: float = 2.6      ## R0 B.12 A-68: dive under damping_only
const OVERSHOOT_MAX_DIVE_DAMPING: float = 0.20
const CSV_COLS: PackedStringArray = ["model", "stage", "cand", "classes", "land_seeds", "dive_seeds", "score",
	"step_fail", "step_worst_t_s", "step_worst_overshoot", "dive_worst_t_s", "dive_worst_overshoot", "dive_hits",
	"dive_min_agl_m", "land_docked", "land_crashed", "land_other", "land_median_gate_dock_s", "land_max_go_arounds",
	"land_thrust_low_mean", "step_fail_detail", "wall_s", "flight_overrides", "landing_overrides"]

var _out_dir: String = ""
var _models: Array[StringName] = [RulesDef.LIFT_SPEED_SCALED, RulesDef.LIFT_DAMPING_ONLY]
var _confirm_seeds: int = 200
var _dive_seeds: int = 200
var _quick: int = 24
var _random_n: int = 24
var _seed: int = 606
var _stages: PackedStringArray = ["base", "oat", "greedy", "random", "confirm", "cross"]
var _max_fail_rows: int = 12
var _given: Dictionary = {}   ## --given=FILE: {model: {flight, landing}} evaluated at the confirm size (no search)
var _dive_deg: Vector2 = SweepScenarios.DIVE_DEG
var _dive_agl: Vector2 = SweepScenarios.DIVE_AGL
var _csv: PackedStringArray = PackedStringArray()
var _fail_csv: PackedStringArray = PackedStringArray()
var _best_out: Dictionary = {}
var _best_cand: Dictionary = {}   ## model -> Cand
var _cand_count: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		_parse(arg)
	if _out_dir.is_empty():
		push_error("gain_sweep: --out=DIR is required")
		get_tree().quit(2)
		return
	var t0: int = Time.get_ticks_msec()
	var _a: bool = _csv.push_back(",".join(CSV_COLS))
	var _b: bool = _fail_csv.push_back("model,cand,seed,eval_stage," + ",".join(SweepScenarios.LANDING_COLS))
	for m: StringName in _models:
		_sweep_model(m)
	if _stages.has("cross") and _models.size() > 1:
		_cross()
	_write()
	print("GAIN_SWEEP done in %.1f s, %d evaluations -> %s" % [float(Time.get_ticks_msec() - t0) / 1000.0, _cand_count,
		_out_dir])
	get_tree().quit(0)


func _parse(arg: String) -> void:
	if arg.begins_with("--out="):
		_out_dir = arg.substr(6)
	elif arg.begins_with("--models="):
		_models.clear()
		for m: String in arg.substr(9).split(","):
			_models.append(StringName(m))
	elif arg.begins_with("--seeds="):
		_confirm_seeds = int(arg.substr(8))
	elif arg.begins_with("--dive-seeds="):
		_dive_seeds = int(arg.substr(13))
	elif arg.begins_with("--quick="):
		_quick = int(arg.substr(8))
	elif arg.begins_with("--random="):
		_random_n = int(arg.substr(9))
	elif arg.begins_with("--seed="):
		_seed = int(arg.substr(7))
	elif arg.begins_with("--stages="):
		_stages = arg.substr(9).split(",")
	elif arg.begins_with("--given="):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(arg.substr(8)))
		if parsed is Dictionary:
			_given = parsed
	elif arg.begins_with("--dive-deg="):
		_dive_deg = _range(arg.substr(11))
	elif arg.begins_with("--dive-agl="):
		_dive_agl = _range(arg.substr(11))
	elif arg.begins_with("--failures="):
		_max_fail_rows = int(arg.substr(11))


static func _range(text: String) -> Vector2:
	var p: PackedStringArray = text.split(",")
	return Vector2(float(p[0]), float(p[1]))


# region search
class Cand extends RefCounted:
	var flight: Dictionary = {}
	var landing: Dictionary = {}
	var score: float = INF

	func copy() -> Cand:
		var c: Cand = Cand.new()
		c.flight = flight.duplicate()
		c.landing = landing.duplicate()
		c.score = score
		return c


func _sweep_model(model: StringName) -> void:
	var fl: Dictionary = Ai05Kit.block("flight")
	var ld: Dictionary = Ai09Kit.block("landing")
	var base: Cand = Cand.new()
	var best: Cand = base
	if _given.has(str(model)):
		var g: Dictionary = _given[str(model)]
		best = Cand.new()
		best.flight = (g.get("flight", {}) as Dictionary).duplicate()
		best.landing = (g.get("landing", {}) as Dictionary).duplicate()
		var _b0: float = _eval(model, "confirm", base, _confirm_seeds, _dive_seeds, true)
		best.score = _eval(model, "confirm", best, _confirm_seeds, _dive_seeds, true)
		_best_cand[model] = best
		_best_out[str(model)] = {"flight": best.flight, "landing": best.landing, "score": best.score}
		return
	base.score = _eval(model, "base", base, _quick, _quick, false)
	var gain: Dictionary = {}   # "f:key" or "l:key" -> [score, Cand]
	if _stages.has("oat") or _stages.has("greedy"):
		for k: String in FLIGHT_KEYS:
			_oat(model, base, true, k, float(fl[k]), gain)
		for k: String in LANDING_KEYS:
			_oat(model, base, false, k, float(ld[k]), gain)
	if _stages.has("greedy"):
		best = _greedy(model, base, gain)
	if _stages.has("random"):
		best = _random(model, best, fl, ld)
	if _stages.has("confirm"):
		var _s0: float = _eval(model, "confirm", base, _confirm_seeds, _dive_seeds, true)
		if best != base:
			best.score = _eval(model, "confirm", best, _confirm_seeds, _dive_seeds, true)
	_best_cand[model] = best
	_best_out[str(model)] = {"flight": best.flight, "landing": best.landing, "score": best.score}


## Each model's best set under the other models (stage `cross`): does one set serve both lift laws (R0 B.12 A-68)?
func _cross() -> void:
	for src: StringName in _models:
		for dst: StringName in _models:
			if src != dst:
				var c: Cand = _best_cand[src]
				var sc: float = _eval(dst, "cross:" + str(src), c, _confirm_seeds, _dive_seeds, false)
				(_best_out[str(src)] as Dictionary)["score_under_" + str(dst)] = sc


func _oat(model: StringName, base: Cand, flight: bool, key: String, v0: float, gain: Dictionary) -> void:
	for m: float in MULTS:
		var c: Cand = base.copy()
		var d: Dictionary = c.flight if flight else c.landing
		d[key] = v0 * m
		c.score = _eval(model, "oat", c, _quick, _quick, false)
		var tag: String = ("f:" if flight else "l:") + key
		if c.score < base.score and (not gain.has(tag) or c.score < float((gain[tag] as Array)[0])):
			gain[tag] = [c.score, c]


func _greedy(model: StringName, base: Cand, gain: Dictionary) -> Cand:
	var tags: Array = gain.keys()
	tags.sort_custom(func(a: Variant, b: Variant) -> bool: return float((gain[a] as Array)[0]) < float((gain[b] as Array)[0]))
	var best: Cand = base
	for tag: Variant in tags:
		var src: Cand = (gain[tag] as Array)[1]
		var key: String = str(tag).substr(2)
		var flight: bool = str(tag).begins_with("f:")
		var c: Cand = best.copy()
		var d: Dictionary = c.flight if flight else c.landing
		d[key] = (src.flight if flight else src.landing)[key]
		c.score = _eval(model, "greedy", c, _quick, _quick, false)
		if c.score < best.score:
			best = c
	return best


func _random(model: StringName, start: Cand, fl: Dictionary, ld: Dictionary) -> Cand:
	var rng: Rng = Rng.new(_seed)
	var best: Cand = start
	var keys: Array[String] = []
	for k: String in FLIGHT_KEYS:
		keys.append("f:" + k)
	for k: String in LANDING_KEYS:
		keys.append("l:" + k)
	for i: int in _random_n:
		var c: Cand = best.copy()
		for j: int in 3:   # jitter three random keys (log-uniform +-30 %) around the best so far
			var tag: String = keys[rng.range_i(0, keys.size() - 1)]
			var d: Dictionary = c.flight if tag.begins_with("f:") else c.landing
			var src: Dictionary = fl if tag.begins_with("f:") else ld
			var key: String = tag.substr(2)
			d[key] = float(d.get(key, src[key])) * exp(rng.range_f(-0.3, 0.3))
		c.score = _eval(model, "random", c, _quick, _quick, false)
		if c.score < best.score:
			best = c
	return best
# endregion


# region evaluation
## Evaluates `c`, appends the CSV row, returns the score. `full`: also the failure rows of landing_failures.csv.
func _eval(model: StringName, stage: String, c: Cand, land_n: int, dive_n: int, full: bool) -> float:
	var t0: int = Time.get_ticks_msec()
	_cand_count += 1
	var su: SweepScenarios.Setup = SweepScenarios.Setup.new()
	su.model = model
	su.flight = c.flight
	su.landing = c.landing
	var damping: bool = model == RulesDef.LIFT_DAMPING_ONLY
	# steps
	var step_fail: int = 0
	var fail_detail: PackedStringArray = PackedStringArray()
	var worst_t: float = 0.0
	var worst_os: float = 0.0
	var dive_t: float = 0.0
	var dive_os: float = 0.0
	var classes: Array[StringName] = CLASSES   # steps of every ship class (heavy classes limit the turn gains)
	for id: StringName in classes:
		for st: Vector2 in STEPS:
			var r: Vector2 = SweepScenarios.step_response(su, id, st.x, st.y)
			var dive: bool = st.y < 0.0
			var t_lim: float = T_MAX_DIVE_DAMPING_S if (dive and damping) else T_MAX_S
			var os_lim: float = OVERSHOOT_MAX_DIVE_DAMPING if (dive and damping) else OVERSHOOT_MAX
			if r.x < 0.0 or r.x > t_lim or r.y >= os_lim:
				step_fail += 1
				var _f: bool = fail_detail.push_back("%s:%d/%d=%.2fs/%.0f%%" % [id, int(st.x), int(st.y), r.x, r.y * 100.0])
			var t_eff: float = r.x if r.x >= 0.0 else float(SweepScenarios.STEP_TICKS) / 30.0
			worst_t = maxf(worst_t, t_eff)
			worst_os = maxf(worst_os, r.y)
			if dive:
				dive_t = maxf(dive_t, t_eff)
				dive_os = maxf(dive_os, r.y)
	# steep dives
	var hits: int = 0
	var min_agl: float = INF
	for k: int in dive_n:
		var d: Vector3 = SweepScenarios.steep_dive(su, _seed, k, _dive_deg, _dive_agl)
		hits += 1 if d.x > 0.0 else 0
		min_agl = minf(min_agl, d.y)
	# landings
	var docked: int = 0
	var crashed: int = 0
	var other: int = 0
	var times: PackedFloat32Array = PackedFloat32Array()
	var max_ga: int = 0
	var fail_rows: int = 0
	var low_sum: int = 0
	for k: int in land_n:
		var o: Dictionary = {}
		var ok: bool = SweepScenarios.landing(su, _seed, k, o)
		max_ga = maxi(max_ga, int(o["go_arounds"]))
		low_sum += int(o["thrust_low_ticks"])
		if ok:
			docked += 1
			var _t: bool = times.push_back(float(o["gate_to_dock_s"]))
			continue
		if o["outcome"] == "crashed" or o["outcome"] == "off_pad":
			crashed += 1
		else:
			other += 1
		if full and fail_rows < _max_fail_rows:
			fail_rows += 1
			_fail_row(model, _cand_count, k, stage, o)
	times.sort()
	var median: float = times[times.size() / 2] if not times.is_empty() else -1.0
	var land_fail: float = float(land_n - docked) / float(maxi(land_n, 1))
	var dive_fail: float = float(hits) / float(maxi(dive_n, 1))
	var score: float = 100.0 * land_fail + 50.0 * dive_fail + 5.0 * float(step_fail) + 0.1 * maxf(median, 0.0) \
		+ worst_os
	var row: Array[String] = [str(model), stage, str(_cand_count), str(classes.size()), str(land_n), str(dive_n),
		"%.3f" % score, str(step_fail), "%.2f" % worst_t, "%.3f" % worst_os, "%.2f" % dive_t, "%.3f" % dive_os,
		str(hits), "%.1f" % (min_agl if min_agl != INF else -1.0), str(docked), str(crashed), str(other),
		"%.1f" % median, str(max_ga),
		"%.0f" % (float(low_sum) / float(maxi(land_n, 1))), " ".join(fail_detail), "%.2f" % (float(Time.get_ticks_msec() - t0) / 1000.0),
		_q(JSON.stringify(c.flight)), _q(JSON.stringify(c.landing))]
	var _a: bool = _csv.push_back(",".join(row))
	return score


func _fail_row(model: StringName, cand: int, k: int, stage: String, o: Dictionary) -> void:
	var cols: Array[String] = [str(model), str(cand), str(k), stage]
	for name: String in SweepScenarios.LANDING_COLS:
		var x: Variant = o[name]
		cols.append("%.2f" % float(x) if x is float else str(x))
	var _a: bool = _fail_csv.push_back(",".join(cols))


static func _q(s: String) -> String:
	return "\"" + s.replace("\"", "\"\"") + "\""


func _write() -> void:
	var _d: Error = DirAccess.make_dir_recursive_absolute(_out_dir)
	_save("sweep.csv", "\n".join(_csv) + "\n")
	_save("landing_failures.csv", "\n".join(_fail_csv) + "\n")
	_save("best_gains.json", JSON.stringify(_best_out, "\t", true) + "\n")


func _save(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(_out_dir.path_join(file), FileAccess.WRITE)
	assert(f != null, "cannot write " + file)
	f.store_string(text)
# endregion
