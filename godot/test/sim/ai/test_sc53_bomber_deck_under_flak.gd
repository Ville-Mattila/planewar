extends GdUnitTestSuite
## SC-53 bomber_deck_under_flak (05 s11.2; R0 B.27 A-138; BUG-2): the Bomber analogue of SC-29. A Bomber ATTACK on a
## Refinery covered by one visible Flak and no Autocannon flies the Deck band (05 s6.3 R1): band DECK at R2, height over
## the Flak below `h_rel_min` while inside `range_m`, the Flak fires 0 shells, the stick is released. With one
## Autocannon added the band is LOW (250 m) and the Flak fires. Reuses GD-26's C06Rig on the shipped bands (rel_m 0);
## the C-06c control leg in test/sim/balance/ pins the same Deck behaviour with the first-seen distances.

const SEEDS: int = 10


func _flak_floor_m() -> float:
	for sd: StructureDef in Ai17Kit.content().structures:
		if sd.id == &"flak_battery":
			return float(sd.tower["h_rel_min"])
	return 0.0


func _run(seed_value: int, guns: int) -> C06Rig:
	var r: C06Rig = C06Rig.new()
	r.n_gun = guns
	r.build(seed_value, 1, 0.0)
	r.run()
	return r


func test_sc53_deck_band_under_a_lone_flak_the_flak_never_fires() -> void:
	for sd: int in range(1, SEEDS + 1):
		var r: C06Rig = _run(sd, 0)
		var what: String = "seed %d: band %d, rel %.0f, shells %d, released %s" % [sd, r.band_at_r2, r.rel_max_r2, r.flak_shells, r.released()]
		assert_int(r.band_at_r2).override_failure_message(what).is_equal(AttackRun.Band.DECK)
		assert_float(r.rel_max_r2).override_failure_message(what).is_less_equal(_flak_floor_m() + C06Rig.descent_slack_m())
		assert_float(r.rel_at_release).override_failure_message(what).is_less(_flak_floor_m())
		assert_int(r.flak_shells).override_failure_message(what).is_equal(0)
		assert_bool(r.released()).override_failure_message(what).is_true()


func test_sc53_variant_with_an_autocannon_the_band_is_low_and_the_flak_fires() -> void:
	var low_m: float = float(Ai14Kit.ap(&"bomber")["attack_run"]["band_low_agl_m"])
	assert_float(low_m).is_equal(250.0)
	for sd: int in range(1, SEEDS + 1):
		var r: C06Rig = _run(sd, 1)
		var what: String = "seed %d: band %d, rel %.0f, shells %d" % [sd, r.band_at_r2, r.rel_max_r2, r.flak_shells]
		assert_int(r.band_at_r2).override_failure_message(what).is_equal(AttackRun.Band.LOW)
		assert_float(r.rel_max_r2).override_failure_message(what).is_greater(_flak_floor_m())
		assert_int(r.flak_shells).override_failure_message(what).is_greater(0)


func test_sc53_is_deterministic() -> void:
	var a: C06Rig = _run(4, 0)
	var b: C06Rig = _run(4, 0)
	assert_bool(a.w.serialize() == b.w.serialize()).is_true()
