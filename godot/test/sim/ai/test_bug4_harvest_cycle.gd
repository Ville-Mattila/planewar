extends GdUnitTestSuite
## BUG-4 acceptance, driven THROUGH the AI-16 `HarvesterBrain` (no test driver): the real Pathing, GroundMotion and
## Harvest run; the brain only drives. GD-12's `test_harvest_cycle.gd` measures the sim with a stand-in driver; this one
## measures what a match gets.
## - The steady cycle (credit to credit) at d = 450 m and 600 m is within 5 % of 02 s8.2 `Economy.harvest_trip_time(d)`.
##   `d` is the one-way leg the formula prices: from the brain's dock stop (Refinery radius + `dock_frac` x
##   `salvage_deliver_m`) to its mining spot (`spot_frac` x the field radius from the centre, on the side it comes from).
##   No tick of the cycle reaches the sim's reverse hold (AI-16 BRAKE rule).
## - On cradle (slot 0, the R0 B.6 start kit, real terrain) the first start-kit delivery lands within 95 s.
## - The cradle run is deterministic and a save / restore mid-mining continues byte for byte.

const HZ: int = 30
const R: float = Sphere.PLANET_RADIUS
const FIRST_DELIVERY_S: float = 95.0


# --- the steady cycle on the flat datum -------------------------------------------------------------------------------

# Seconds between the 2nd and 3rd credit of one brain-driven Harvester whose leg is `d`; also checks the BRAKE rule.
func _brain_cycle_s(d: float) -> float:
	var w: SimWorld = Ai16Kit.world(11)
	var ref: int = Ai16Kit.put(w, &"refinery", 0, 0.0)
	var b: HarvesterBrain = Ai16Kit.brain()
	var dock_e: float = w.view().radius(ref) + b.prm.dock_frac * b.prm.deliver_m
	var _f: int = Ai16Kit.field(w, dock_e + d + b.prm.spot_frac * 150.0, 0.0, 100000, 0.0, 150.0, 4)
	var h: int = Ai16Kit.put(w, &"harvester", 0, dock_e)
	var _d: AiDriver = Ai16Kit.driver(w, b)
	var hold: float = WorldTestKit.content().ground_common.ground_reverse_hold_s
	var s: int = EntityId.slot(h)
	var last: float = 0.0
	var marks: Array[int] = []
	var worst_hold: float = 0.0
	for _i: int in 600 * HZ:
		Ai16Kit.step(w)
		worst_hold = maxf(worst_hold, w.store().timer_b[s])
		var c: float = w.store().cargo[s]
		if last > 0.0 and c == 0.0:   # the credit tick (H6; the ledger is not read: player 0's stockpile is at its cap)
			marks.append(w.tick())
		last = c
		if marks.size() >= 3:
			break
	assert_int(marks.size()).is_equal(3)
	if marks.size() < 3:
		return -1.0
	assert_float(worst_hold).override_failure_message("BRAKE held %.2f s" % worst_hold).is_less(hold - 0.5 / float(HZ))
	assert_int(b.stats_strikes).is_equal(0)
	return float(marks[2] - marks[1]) / float(HZ)


func test_the_brain_driven_cycle_at_450_m_is_within_5_percent_of_02_s8_2() -> void:
	var formula: float = Economy.harvest_trip_time(450.0, Ai16Kit.ground_def())
	assert_float(formula).is_equal_approx(108.5, 0.05)
	var t: float = _brain_cycle_s(450.0)
	assert_float(t).override_failure_message("cycle %.2f s vs %.2f s" % [t, formula]).is_equal_approx(formula, formula * 0.05)


func test_the_brain_driven_cycle_at_600_m_is_within_5_percent_of_02_s8_2() -> void:
	var formula: float = Economy.harvest_trip_time(600.0, Ai16Kit.ground_def())
	assert_float(formula).is_equal_approx(136.0, 0.05)
	var t: float = _brain_cycle_s(600.0)
	assert_float(t).override_failure_message("cycle %.2f s vs %.2f s" % [t, formula]).is_equal_approx(formula, formula * 0.05)


# --- the start kit on cradle ------------------------------------------------------------------------------------------

func _cradle(seed_value: int) -> SimWorld:
	var w: SimWorld = Ai23Kit.world(seed_value, &"cradle", false, &"vanguard", &"vanguard", true)
	var d: AiDriver = Ai14Kit.driver(w)
	Ai23Kit.add_economy(d, w, true)
	return w


static func _harvester(w: SimWorld) -> int:
	for s: int in w.store().ground:
		if w.store().def_id[s] == Ai23Kit.def(&"harvester") and w.store().owner[s] == 0:
			return s
	return -1


func test_the_first_start_kit_delivery_on_cradle_lands_within_95_s() -> void:
	var w: SimWorld = _cradle(3)
	var hv: int = _harvester(w)
	assert_int(hv).is_greater_equal(0)
	var cargo_ore: float = float(Ai16Kit.ground_def().cargo_ore)
	var last: float = 0.0
	var at: int = -1
	for _k: int in 150 * HZ:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		var c: float = w.store().cargo[hv]
		if last >= cargo_ore and c == 0.0:   # a full load unloaded at the Refinery (Harvest credits it)
			at = w.tick()
			break
		last = c
	assert_int(at).override_failure_message("no delivery in 150 s").is_greater(0)
	var t: float = float(at) / float(HZ)
	assert_float(t).override_failure_message("first delivery at %.1f s" % t).is_less_equal(FIRST_DELIVERY_S)


func test_the_cradle_start_kit_cycle_is_deterministic_and_restores_byte_for_byte() -> void:
	var a: SimWorld = _cradle(5)
	var b: SimWorld = _cradle(5)
	var _x: Array[SimEvent] = Ai23Kit.run(a, 10 * HZ)   # mid-mining (the first load takes 20 s)
	var _y: Array[SimEvent] = Ai23Kit.run(b, 10 * HZ)
	assert_bool(a.serialize() == b.serialize()).is_true()
	var bytes: PackedByteArray = a.serialize()
	var d2: AiDriver = Ai14Kit.make_driver(a.terrain())
	var w2: SimWorld = SimWorld.deserialize(bytes, Ai23Kit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	Ai23Kit.add_economy(d2, w2, false)
	assert_bool(w2.serialize() == bytes).is_true()
	var hv: int = _harvester(a)
	var drops: int = 0
	var last: float = a.store().cargo[hv]
	for k: int in 100 * HZ:   # through the first delivery and onto the next leg
		a.step()
		b.step()
		w2.step()
		var _e1: Array[SimEvent] = a.drain_events()
		var _e2: Array[SimEvent] = b.drain_events()
		var _e3: Array[SimEvent] = w2.drain_events()
		if k % (10 * HZ) == 0:
			assert_bool(w2.serialize() == a.serialize()).override_failure_message("restored run diverges at +%d" % k).is_true()
		drops += 1 if last > 0.0 and a.store().cargo[hv] == 0.0 else 0
		last = a.store().cargo[hv]
	assert_bool(a.serialize() == b.serialize()).is_true()
	assert_bool(w2.serialize() == a.serialize()).is_true()
	assert_int(drops).is_equal(1)   # the first load was delivered inside the compared window
