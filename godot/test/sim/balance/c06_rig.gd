class_name C06Rig extends RefCounted
## GD-26 / C-06 rig (02 s18.3, R0 B.25 A-128): the real `BomberBrain` ATTACK order on a Refinery of team FOE guarded by
## none, one or two finished, powered and supplied `flak_battery` towers driven by the real `TowerBrain`, on the flat
## datum. One run = one seed: the seed feeds the world's roll stream (flak spread) and the Bomber's lateral start offset.
## The Bomber starts `START_M` west of the Refinery; the Flak stand `FLAK_AHEAD_M` before the Refinery, `FLAK_ABEAM_M`
## off the approach line (inside the Refinery's 500 m supply pipe). A team 0 Sensor Mast shows the Refinery to the Bomber
## (an ATTACK needs its target seen) and the defender's Core stands far from the approach line, so the first sight of the
## Bomber is the Flak's own sensor.

const START_M: float = 2200.0
const FLAK_AHEAD_M: float = 300.0
const FLAK_ABEAM_M: float = 60.0
const MAX_S: float = 140.0
const SEE_MIN_M: float = 1500.0        # A-128: first seen at >= 1,500 m from the Flak (sensor_radius 1,600)
const C0: Vector3 = Vector3(1, 0, 0)
const HZ: int = 30

var w: SimWorld
var driver: AiDriver
var bomber: int = 0
var refinery: int = 0
var flaks: PackedInt32Array = PackedInt32Array()
var bombs0: int = 0
var first_seen_m: float = INF          # Bomber-to-first-Flak distance on the tick the defenders first see it
var release_tick: int = -1             # first tick a bomb left the Bomber alive
var death_tick: int = -1
var rel_at_release: float = NAN        # the Bomber's height over the first Flak when it released
var ticks_run: int = 0
var rel_target_m: float = 0.0          # the forced band height (0 = the brain's own bands)
var rel_min_in_range: float = INF      # the Bomber's lowest height over the first Flak while inside flak_gun range_m
var rel_max_in_range: float = -INF
var band_at_r2: int = -1               # AttackRun band on the last tick the run is in RUN_IN (R2)
var rel_max_r2: float = -INF           # the Bomber's greatest height over the nearest Flak inside range_m during R2
var n_gun: int = 0                     # SC-53 variant (BUG-2): autocannon_turret towers added beside the Refinery
var flak_ammo0: int = 0
var flak_shells: int = 0               # shells the Flak spent (ammo drop) by the end of the run
var in_range_with_bombs: bool = false  # the Bomber was within flak_gun range_m of the Flak with its bombs aboard


## `rel_m` > 0 flies every attack band at that height (the C-06 setup, the Bomber 600 m over the Flak); 0 keeps the
## brain's own bands (05 s6.3: the DECK band, 60 m, once it knows a Flak covers the target).
## A-139: the tolerance on the held height is the altitude law's own saturation error, vz_max_mps / kp_alt of the Bomber's
## guidance block (the altitude error at which the climb command reaches its cap), not a free number.
static func rel_tol_m() -> float:
	var fl: Dictionary = Ai14Kit.ap(&"bomber")["guidance"]
	return float(fl["vz_max_mps"]) / float(fl["kp_alt"])


## Two ticks of the altitude law's vertical-speed cap: the slack on a height that is still settling when it enters range_m.
static func descent_slack_m() -> float:
	return 2.0 * float(Ai14Kit.ap(&"bomber")["guidance"]["vz_max_mps"]) / float(HZ)


static func _flak_tower() -> Dictionary:
	for sd: StructureDef in Ai17Kit.content().structures:
		if sd.id == &"flak_battery":
			return sd.tower
	return {}


static func _flak_sensor_m() -> float:
	for sd: StructureDef in Ai17Kit.content().structures:
		if sd.id == &"flak_battery":
			return sd.sensor_radius
	return 0.0


func build(seed_value: int, n_flak: int, rel_m: float = 0.0) -> void:
	rel_target_m = rel_m
	w = Ai17Kit.world(seed_value)
	driver = Ai14Kit.make_driver(w.terrain(), true, 3, [false, false, true, false])
	driver.set_brain(Ai17Kit.tower_cls(), Ai17Kit.brain())
	w.set_ai_hook(driver)
	if rel_m > 0.0:
		var prm: DartParams = (Ai14Kit.brain_of(driver, &"bomber") as BomberBrain).prm
		prm.deck_agl = rel_m
		prm.band_low = rel_m
		prm.band_high = rel_m
	var fc: Vector3 = DartKit.offset(C0, 300.0, -2600.0)
	var _core: int = Ai14Kit.core(w, fc, DartKit.FOE)                               # the defender's power
	refinery = DartKit.spawn(w, &"refinery", DartKit.FOE, DartKit.above(w, C0, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	var mast_p: Vector3 = DartKit.above(w, DartKit.offset(C0, -800.0, 400.0), 0.0)
	var _mast: int = DartKit.spawn(w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, Vector3(0, 1, 0)))
	var side: float = -1.0
	for k: int in n_flak:
		var dir: Vector3 = DartKit.offset(C0, -FLAK_AHEAD_M - 160.0 * k, FLAK_ABEAM_M * side)
		flaks.append(Ai17Kit.tower(w, &"flak_battery", DartKit.FOE, dir, DartKit.offset(C0, -3000.0, 0.0)))
		side = -side
	for k: int in n_gun:
		var gdir: Vector3 = DartKit.offset(C0, -200.0 - 160.0 * k, 120.0)
		var _gun: int = Ai17Kit.tower(w, &"autocannon_turret", DartKit.FOE, gdir, DartKit.offset(C0, -3000.0, 0.0))
	var lat: float = float((seed_value * 37) % 301 - 150)                           # +-150 m of lateral start offset
	var alt: float = rel_m if rel_m > 0.0 else float(Ai14Kit.ap(&"bomber").get("cruise_alt_agl_m", 400.0))
	var p0: Vector3 = DartKit.above(w, DartKit.offset(C0, -START_M, lat), alt)
	var h: Vector3 = DartKit.heading(p0, DartKit.above(w, C0, 0.0))
	bomber = DartKit.spawn(w, &"bomber", 0, p0, h * Ai14Kit.ship(&"bomber").v_cruise, h)
	bombs0 = w.view().bombs(bomber)
	for f: int in flaks:
		flak_ammo0 += w.view().ammo(f)
	for _k: int in 3:
		var _x: Array[SimEvent] = Ai17Kit.step(w)
	DartKit.order(w, bomber, OrderSpec.make(OrderSpec.Kind.ATTACK, refinery))


## Preconditions of A-128 before the run: every Flak finished, powered and supplied with ammo; the Bomber loaded.
func preconditions() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var v: SimView = w.view()
	for f: int in flaks:
		if not v.alive(f):
			out.append("flak %d not alive" % f)
		if (v.flags(f) & EntityStore.F_BUILDING) != 0:
			out.append("flak %d still under construction" % f)
		if v.supply01(f) < 1.0:
			out.append("flak %d supply01 %.2f" % [f, v.supply01(f)])
		if v.ammo(f) <= 0:
			out.append("flak %d has no ammo" % f)
	var pb: Vector2 = v.power_balance(DartKit.FOE)
	if pb.y > pb.x:
		out.append("defender power: supply %.1f < demand %.1f" % [pb.x, pb.y])
	if not v.alive(bomber) or bombs0 <= 0:
		out.append("bomber missing or without bombs")
	return out


## Preconditions measured during the run: the defenders first saw the Bomber at >= SEE_MIN_M from the first Flak (by
## the Flak's own sensor: the Core and the Refinery cannot reach the approach line) and the Bomber was inside flak_gun's
## `range_m` of it with its bombs aboard.
func run_preconditions() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var tick_m: float = Ai14Kit.ship(&"bomber").v_boost / float(HZ)
	if first_seen_m < SEE_MIN_M or first_seen_m > _flak_sensor_m() + tick_m:
		out.append("the defenders first saw the Bomber at %.0f m (not in [%.0f, sensor %.0f + one tick])" % [first_seen_m, SEE_MIN_M, _flak_sensor_m()])
	if rel_target_m > 0.0:
		var tol: float = rel_tol_m()
		var tw: Dictionary = _flak_tower()
		if rel_min_in_range < rel_target_m - tol or rel_max_in_range > rel_target_m + tol:
			out.append("the Bomber flew %.0f..%.0f m over the Flak inside its range, not %.0f +- %.0f m" % [rel_min_in_range, rel_max_in_range, rel_target_m, tol])
		if rel_min_in_range < float(tw["h_rel_min"]) or rel_max_in_range > float(tw["h_rel_max"]):
			out.append("the Bomber left the Flak envelope [%s, %s] inside its range" % [tw["h_rel_min"], tw["h_rel_max"]])
		if not is_nan(rel_at_release) and absf(rel_at_release - rel_target_m) > tol:
			out.append("the Bomber released at %.0f m over the Flak, not %.0f m" % [rel_at_release, rel_target_m])
	if not in_range_with_bombs:
		out.append("the Bomber never entered flak_gun range_m with bombs aboard")
	return out


## Runs until the Bomber released, died, or MAX_S passes; fills the diagnostics.
func run() -> void:
	var v: SimView = w.view()
	var ref: int = flaks[0] if flaks.size() > 0 else refinery
	var range_m: float = _flak_range()
	for k: int in int(MAX_S) * HZ:
		var _e: Array[SimEvent] = Ai17Kit.step(w)
		ticks_run = k + 1
		if not v.alive(bomber):
			death_tick = k
			_count_shells()
			break
		var d: float = v.pos(bomber).distance_to(v.pos(ref))
		for f: int in flaks:
			d = minf(d, v.pos(bomber).distance_to(v.pos(f)))
		if first_seen_m == INF and v.visible_to(DartKit.FOE, bomber):
			first_seen_m = d
		var in_r2: bool = AttackRun.step_of(driver.state, EntityId.slot(bomber)) == AttackRun.Step.RUN_IN
		if in_r2:
			band_at_r2 = AttackRun.band_of(driver.state, EntityId.slot(bomber))
			if d < range_m:
				rel_max_r2 = maxf(rel_max_r2, v.pos(bomber).length() - v.pos(ref).length())
		if v.bombs(bomber) > 0 and d < range_m:
			in_range_with_bombs = true
			var rel_now: float = v.pos(bomber).length() - v.pos(ref).length()
			rel_min_in_range = minf(rel_min_in_range, rel_now)
			rel_max_in_range = maxf(rel_max_in_range, rel_now)
		if v.bombs(bomber) < bombs0:
			release_tick = k
			_count_shells()
			rel_at_release = v.pos(bomber).length() - v.pos(ref).length()
			break
	_count_shells()                                                                 # idempotent: also when the run times out (an aborted Bomber)


func _count_shells() -> void:
	var left: int = 0
	for f: int in flaks:
		left += w.view().ammo(f)
	flak_shells = flak_ammo0 - left


func _flak_range() -> float:
	for wd: WeaponDef in Ai17Kit.content().weapons:
		if wd.id == &"flak_gun":
			return wd.range_m
	return 0.0


func released() -> bool:
	return release_tick >= 0


## One sweep over seeds 1..`seeds`: {released, died, pre_fail (messages), rel_lo / rel_hi (height over the Flak at release), seen_lo / seen_hi}. Run preconditions are checked when `n_flak` > 0.
static func sweep(n_flak: int, seeds: int, rel_m: float) -> Dictionary:
	var released_n: int = 0
	var died_n: int = 0
	var pre_fail: PackedStringArray = PackedStringArray()
	var rel_lo: float = INF
	var rel_hi: float = -INF
	var seen_lo: float = INF
	var seen_hi: float = -INF
	for sd: int in range(1, seeds + 1):
		var r: C06Rig = C06Rig.new()
		r.build(sd, n_flak, rel_m)
		for m: String in r.preconditions():
			pre_fail.append("seed %d: %s" % [sd, m])
		r.run()
		if n_flak > 0:
			for m: String in r.run_preconditions():
				pre_fail.append("seed %d: %s" % [sd, m])
		if r.released():
			rel_lo = minf(rel_lo, r.rel_at_release)
			rel_hi = maxf(rel_hi, r.rel_at_release)
		seen_lo = minf(seen_lo, r.first_seen_m)
		seen_hi = maxf(seen_hi, r.first_seen_m)
		released_n += 1 if r.released() else 0
		died_n += 1 if r.death_tick >= 0 else 0
	return {"released": released_n, "died": died_n, "pre_fail": pre_fail, "rel_lo": rel_lo, "rel_hi": rel_hi, "seen_lo": seen_lo, "seen_hi": seen_hi}
