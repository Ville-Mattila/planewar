extends GdUnitTestSuite
## NET-11: per-preset statistics over N packets (04 s15.1 presets table), determinism, MOBILE_SWITCH and TAB_STALL.

const N: int = 6000                     # 200 s at 30 Hz, one snapshot-channel packet per tick per direction


## Sends N sequential snapshot-channel packets s2c (one per tick) and returns stats of what arrived.
func _measure(which: FaultModel.Preset, seed_arg: int) -> Dictionary:
	var r: LocalRig = LocalRig.new(FaultModel.preset(which, seed_arg), true, false)
	var sent_at: PackedFloat64Array = PackedFloat64Array()
	var ctrl_sent: int = 0
	for i: int in N:
		sent_at.append(r.clock.now_ms())
		r.send_s2c(Protocol.CH_INPUT, i)                  # unreliable, unsequenced: exposes loss/reorder/dup
		r.send_s2c(Protocol.CH_CONTROL, i)
		ctrl_sent += 1
		r.step()
	r.run_ticks(60)
	var got: int = 0
	var seen: Dictionary[int, bool] = {}
	var dups: int = 0
	var reorders: int = 0
	var last: int = -1
	var lat_sum: float = 0.0
	var lat: PackedFloat64Array = PackedFloat64Array()
	var ctrl_got: int = 0
	for row: Vector3i in r.at_client:
		if row.y == Protocol.CH_CONTROL:
			ctrl_got += 1
			continue
		got += 1
		if seen.has(row.z):
			dups += 1
			continue
		seen[row.z] = true
		if row.z < last:
			reorders += 1
		last = maxi(last, row.z)
		var l: float = FaultModel.tick_to_ms(row.x) - sent_at[row.z]
		lat.append(l)
		lat_sum += l
	return {
		"loss": 1.0 - float(seen.size()) / float(N), "reorder": float(reorders) / float(N),
		"dup": float(dups) / float(N), "lat_mean": lat_sum / maxf(float(lat.size()), 1.0),
		"ctrl_ok": ctrl_got == ctrl_sent,
	}


func test_lan_is_lossless_and_instant() -> void:
	var m: Dictionary = _measure(FaultModel.Preset.LAN, 3)
	assert_float(m["loss"]).is_equal(0.0)
	assert_float(m["reorder"]).is_equal(0.0)
	assert_float(m["dup"]).is_equal(0.0)
	assert_float(m["lat_mean"]).is_less(34.0)          # delivered on the next poll: one tick of quantisation
	assert_bool(m["ctrl_ok"]).is_true()


func test_good_preset_statistics() -> void:
	var m: Dictionary = _measure(FaultModel.Preset.GOOD, 3)
	assert_float(m["loss"]).is_between(0.002, 0.009)      # 0.5 %
	assert_float(m["lat_mean"]).is_between(40.0, 80.0)    # 40 ms + up to one tick of poll quantisation (avg 17)
	assert_float(m["reorder"]).is_less(0.01)
	assert_float(m["dup"]).is_equal(0.0)
	assert_bool(m["ctrl_ok"]).is_true()


func test_target_preset_statistics() -> void:
	var m: Dictionary = _measure(FaultModel.Preset.TARGET, 3)
	assert_float(m["loss"]).is_between(0.022, 0.038)      # 3 %
	assert_float(m["lat_mean"]).is_between(100.0, 135.0)
	assert_float(m["reorder"]).is_between(0.003, 0.03)    # 1 % explicit + jitter overlap
	assert_float(m["dup"]).is_equal(0.0)
	assert_bool(m["ctrl_ok"]).is_true()


func test_bad_preset_statistics() -> void:
	var m: Dictionary = _measure(FaultModel.Preset.BAD, 3)
	assert_float(m["loss"]).is_between(0.04, 0.062)       # 5 %
	assert_float(m["lat_mean"]).is_between(250.0, 290.0)
	assert_float(m["reorder"]).is_between(0.05, 0.25)    # 2 % explicit + jitter (40 ms) over a 33 ms send spacing
	assert_float(m["dup"]).is_between(0.002, 0.009)       # 0.5 %
	assert_bool(m["ctrl_ok"]).is_true()


func test_presets_table() -> void:
	var t: FaultModel = FaultModel.preset(FaultModel.Preset.TARGET)
	assert_float(t.latency_ms).is_equal(100.0)
	assert_float(t.jitter_ms).is_equal(15.0)
	assert_float(t.loss).is_equal(0.03)
	assert_float(t.reorder).is_equal(0.01)
	var b: FaultModel = FaultModel.preset(FaultModel.Preset.BAD)
	assert_float(b.latency_ms).is_equal(250.0)
	assert_float(b.duplicate).is_equal(0.005)
	var ms: FaultModel = FaultModel.preset(FaultModel.Preset.MOBILE_SWITCH)
	assert_float(ms.latency_ms).is_equal(100.0)
	assert_array(ms.burst_loss).is_equal([Vector2i(900, 1020)])
	var ts: FaultModel = FaultModel.preset(FaultModel.Preset.TAB_STALL)
	assert_float(ts.latency_ms).is_equal(40.0)
	assert_bool(ts.has_stall()).is_true()
	assert_float(ts.stall_adjust(FaultModel.tick_to_ms(1200), FaultModel.tick_to_ms(1200))).is_equal(
			FaultModel.tick_to_ms(1200) + 45000.0)
	assert_bool(FaultModel.preset(FaultModel.Preset.GOOD).has_stall()).is_false()
	assert_int(FaultModel.Preset.size()).is_equal(6)


func test_mobile_switch_burst_then_recovery() -> void:
	var r: LocalRig = LocalRig.new(FaultModel.preset(FaultModel.Preset.MOBILE_SWITCH, 5))
	var during: int = 0
	var after: int = 0
	var before: int = 0
	for t: int in 1400:
		r.send_s2c(Protocol.CH_SNAPSHOT, t)
		r.send_s2c(Protocol.CH_EVENTS, t)
		r.step()
	r.run_ticks(30)
	for row: Vector3i in r.at_client:
		if row.y != Protocol.CH_SNAPSHOT:
			continue
		if row.z >= 900 and row.z < 1020:
			during += 1
		elif row.z >= 1020:
			after += 1
		else:
			before += 1
	assert_int(during).is_equal(0)                          # 4 s of 100 % loss
	assert_int(before).is_greater(850)
	assert_int(after).is_greater(340)
	var events: PackedInt32Array = PackedInt32Array()
	var released: int = 0
	for row: Vector3i in r.at_client:
		if row.y == Protocol.CH_EVENTS:
			events.append(row.z)
			if row.z >= 900 and row.z < 1020:
				released = maxi(released, row.x)
	assert_int(events.size()).is_equal(1400)               # reliable: nothing lost
	for i: int in events.size():
		assert_int(events[i]).is_equal(i)
	assert_int(released).is_greater_equal(1020)             # held until the burst ends


func test_tab_stall_45s_burst_release() -> void:
	var r: LocalRig = LocalRig.new(FaultModel.preset(FaultModel.Preset.TAB_STALL, 5))
	var resume_tick: int = FaultModel.TAB_STALL_TICK + 45 * FaultModel.TICK_HZ
	for t: int in resume_tick + 60:
		r.send_s2c(Protocol.CH_SNAPSHOT, t)
		r.send_c2s(Protocol.CH_INPUT, t)
		r.send_s2c(Protocol.CH_EVENTS, t)
		r.step()
	r.run_ticks(10)
	var stalled_arrivals: int = 0
	var first_resume: int = 1 << 30
	for row: Vector3i in r.at_client:
		if row.y == Protocol.CH_EVENTS and row.z >= FaultModel.TAB_STALL_TICK and row.z < resume_tick:
			stalled_arrivals += 1
			first_resume = mini(first_resume, row.x)
			assert_int(row.x).is_greater_equal(resume_tick)
	assert_int(stalled_arrivals).is_equal(45 * FaultModel.TICK_HZ)    # every reliable packet survives
	assert_int(first_resume).is_less_equal(resume_tick + 2)
	# nothing crosses the link during the stall: the held snapshots arrive together, in order, at the end
	var snaps_in_window: int = 0
	for row: Vector3i in r.at_client:
		if row.y == Protocol.CH_SNAPSHOT and row.z >= FaultModel.TAB_STALL_TICK and row.z < resume_tick:
			snaps_in_window += 1
			assert_int(row.x).is_greater_equal(resume_tick)
	assert_int(snaps_in_window).is_greater(1300)
	assert_int(r.server.link_pipe(r.server_conn, true).stale_dropped).is_equal(0)
