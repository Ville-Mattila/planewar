extends GdUnitTestSuite
## BUG-3 acceptance on cradle's baked terrain: slot 0's start-kit Harvester, driven by its autopilot (AI-16
## `HarvesterBrain`) through the real Pathing, GroundMotion and Harvest, completes a full mine-deliver cycle to the
## start-kit Refinery. Before BUG-3 the Refinery stood at the datum radius, ~335 m above the ground the Harvester drives
## on, out of the 3-D dock reach, so it never unloaded.

const HZ: int = Ai23Kit.HZ
const LIMIT_S: int = 240


func test_cradle_slot0_start_kit_harvester_mines_and_delivers() -> void:
	var w: SimWorld = Ai23Kit.world(3, &"cradle", false, &"vanguard", &"vanguard", true)
	var d: AiDriver = Ai14Kit.driver(w)
	Ai23Kit.add_economy(d, w, true)
	var cargo_ore: float = float(_harvester().cargo_ore)   # one full load
	var drops: int = 0
	var peak: float = 0.0
	var last: float = 0.0
	var hv: int = -1
	for s: int in w.store().ground:
		hv = s if w.store().def_id[s] == Ai23Kit.def(&"harvester") and w.store().owner[s] == 0 else hv
	assert_int(hv).is_greater_equal(0)
	for _k: int in LIMIT_S * HZ:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		var c: float = w.store().cargo[hv]
		peak = maxf(peak, c)
		drops += 1 if last >= cargo_ore and c == 0.0 else 0   # a full load unloaded at the Refinery (Harvest credits it)
		last = c
		if drops > 0:
			break
	assert_float(peak).override_failure_message("the Harvester never mined").is_greater(0.0)
	assert_int(drops).override_failure_message("no full load delivered in %d s (peak cargo %.0f)" % [LIMIT_S, peak]).is_greater_equal(1)


func _harvester() -> GroundUnitDef:
	for g: GroundUnitDef in Ai23Kit.content().ground_units:
		if g.id == &"harvester":
			return g
	return null
