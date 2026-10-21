extends GdUnitTestSuite
## NET-56: BaselineFrame.shown_levels is the one presentation rule (04 s5.6): a known blip shows its stored bucket
## levels, never dead-reckoned (a DYING flag does not bring gravity back); every other entry dead-reckons.

const G: float = 6.0
const DT: float = 1.0 / 30.0
const SLOT: int = 4


func _q() -> int:
	return Codec.quantize_pos(Sphere.from_lat_lon(0.2, 0.3, Sphere.PLANET_RADIUS + 300.0))


func test_dying_blip_rests_300_ticks_at_blip_pos() -> void:
	var f: BaselineFrame = BaselineFrame.new()
	var fine: int = DeadReckon.pack_fine(0, 0, 0)
	f.set_full_cached(SLOT, 10, _q(), 0, 0, fine, 255, Codec.FLAG_DYING, -1)
	f.set_blip(SLOT, 20, 0x0A1B2C)
	var at: Vector3i = Vector3i(Codec.pos_e(f.pos[SLOT]), Codec.pos_n(f.pos[SLOT]), Codec.pos_u(f.pos[SLOT]))
	for dt_ticks: int in [0, 1, 30, 111, 300]:
		assert_that(f.shown_levels(SLOT, 20 + dt_ticks, true, G, DT)).is_equal(at)
		assert_that(f.shown_levels(SLOT, 20 + dt_ticks, false, G, DT)).is_equal(at)
	# The old rule (dead-reckon with the DYING gravity term) drifts away: this is the bug.
	var old: Vector3i = DeadReckon.dr_levels(f.pos[SLOT], f.vel[SLOT], 300, true, G, DT)
	assert_that(old).is_not_equal(at)


func test_unknown_blip_still_dead_reckons() -> void:
	var f: BaselineFrame = BaselineFrame.new()
	var fine: int = DeadReckon.pack_fine(5 * DeadReckon.FINE_PER_MPS, 0, 0)
	f.set_full_cached(SLOT, 10, _q(), 0, 0, fine, 255, Codec.FLAG_DYING, -1)
	assert_that(f.shown_levels(SLOT, 70, false, G, DT)).is_equal(DeadReckon.dr_levels(f.pos[SLOT], fine, 60, true, G, DT))
	f.flags[SLOT] = 0
	assert_that(f.shown_levels(SLOT, 70, true, G, DT)).is_equal(DeadReckon.dr_levels(f.pos[SLOT], fine, 60, true, G, DT))
	assert_that(f.shown_levels(SLOT, 70, false, G, DT)).is_equal(DeadReckon.dr_levels(f.pos[SLOT], fine, 60, false, G, DT))
	assert_that(f.shown_levels(SLOT, 70, true, G, DT)).is_not_equal(f.shown_levels(SLOT, 70, false, G, DT))


func test_shown_blip_agrees_with_shown_levels() -> void:
	var f: BaselineFrame = BaselineFrame.new()
	var fine: int = DeadReckon.pack_fine(3 * DeadReckon.FINE_PER_MPS, 0, 0)
	f.set_full_cached(SLOT, 10, _q(), 0, 0, fine, 255, 0, -1)
	var lv: Vector3i = f.shown_levels(SLOT, 50, false, G, DT)
	var moved: int = Codec.pack_pos(Codec.pos_cell(f.pos[SLOT]), lv.x, lv.y, lv.z)
	assert_int(f.shown_blip(SLOT, 50, false, G, DT)).is_equal(DeadReckon.entry_blip(moved, 0, 0, 0, false, G, DT))
