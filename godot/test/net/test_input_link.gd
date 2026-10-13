extends GdUnitTestSuite
## NET-03: INPUT over LocalTransport with the FaultModel presets. Redundancy recovers single and double loss
## (BAD preset), a dropped middle packet loses no inputs, silence raises LINK_BRIDGE once, determinism per seed.

var LEAD: int = 2                     # client lead in ticks: ceil(one-way latency / DT) + margin, set per run (04 s5.1)


func _input_for(tick: int) -> PilotInput:
	var p: PilotInput = PilotInput.new()
	p.thrust = float(tick % 200) / 200.0
	p.pitch = sin(float(tick) * 0.1)
	p.yaw = cos(float(tick) * 0.07)
	p.roll = 0.25
	p.buttons = PilotInput.FIRE1 if tick % 9 == 0 else 0
	return p


## Runs one client sending INPUT every `every` ticks for `ticks` ticks; returns the server-side buffer and a
## [missed, bridged] pair. Server consumes tick t at server time t; client sends input for tick t + LEAD at time t.
func _run(model: FaultModel, ticks: int, every: int = 1, silent_from: int = -1, silent_to: int = -1) -> Array:
	LEAD = ceili(model.latency_ms * 30.0 / 1000.0) + 4
	var rig: LocalRig = LocalRig.new(model, false, true)
	var buf: InputBuffer = InputBuffer.new()
	buf.begin_epoch(2)
	var snd: InputSender = InputSender.new()
	snd.reset(2)
	rig.server.packet.connect(func(_c: int, ch: int, bytes: PackedByteArray) -> void:
		if ch == Protocol.CH_INPUT and bytes.size() > 0 and bytes[0] == Protocol.INPUT:
			var _n: int = buf.submit(bytes, rig.clock.tick()))
	var missed: int = 0
	var wrong: int = 0
	var h: int = 17
	for t: int in ticks:
		var _q: PilotInput = snd.push(t + LEAD, _input_for(t + LEAD))
		var silent: bool = t >= silent_from and t < silent_to
		if t % every == 0 and not silent:
			rig.client.send(LocalTransport.CLIENT_CONN, Protocol.CH_INPUT, snd.build(t), false)
		rig.step()
		if t >= LEAD + 20:
			var p: PilotInput = buf.take(t)
			if buf.miss_run > 0:
				missed += 1
			else:
				var want: PilotInput = PilotWire.quantized(_input_for(t))
				if p.pitch != want.pitch or p.thrust != want.thrust or p.buttons != want.buttons:
					wrong += 1
			h = (h * 31 + int(p.pitch * 127.0) + int(p.thrust * 255.0) * 7 + (1 if buf.bridge else 0)) & 0x7FFFFFFF
	return [buf, missed, wrong, h]


func test_lan_delivers_every_input_exactly() -> void:
	var r: Array = _run(FaultModel.preset(FaultModel.Preset.LAN), 400)
	assert_int(r[1] as int).is_equal(0)
	assert_int(r[2] as int).is_equal(0)
	assert_int((r[0] as InputBuffer).bridge_raised).is_equal(0)


func test_bad_preset_redundancy_recovers_single_and_double_loss() -> void:
	var m: FaultModel = FaultModel.preset(FaultModel.Preset.BAD, 11)
	var r: Array = _run(m, 1500)
	var buf: InputBuffer = r[0]
	# BAD drops 5 %: without redundancy ~75 of 1,500 ticks would miss; with 3x almost none (loss^3 plus reorder)
	assert_int(r[1] as int).is_less_equal(3)
	assert_int(r[2] as int).is_equal(0)           # every consumed input equals what the client sent, bit exact
	assert_int(buf.bridge_raised).is_equal(0)
	assert_int(buf.duplicates).is_greater(0)      # redundancy overlap and 0.5 % network duplicates are ignored
	assert_int(buf.rejected_window).is_less(buf.accepted)


func test_without_redundancy_bad_preset_would_miss() -> void:
	# control: a sender that only keeps one tick per packet (count 1) loses inputs under the same model
	LEAD = ceili(250.0 * 30.0 / 1000.0) + 4
	var rig: LocalRig = LocalRig.new(FaultModel.preset(FaultModel.Preset.BAD, 11), false, true)
	var buf: InputBuffer = InputBuffer.new()
	buf.begin_epoch(2)
	rig.server.packet.connect(func(_c: int, _ch: int, bytes: PackedByteArray) -> void:
		var _n: int = buf.submit(bytes, rig.clock.tick()))
	var missed: int = 0
	for t: int in 1500:
		var one: Array[PilotInput] = [_input_for(t + LEAD)]
		rig.client.send(LocalTransport.CLIENT_CONN, Protocol.CH_INPUT, InputCodec.encode(2, t + LEAD, 0, one, 1), false)
		rig.step()
		if t >= LEAD + 20:
			var _p: PilotInput = buf.take(t)
			if buf.miss_run > 0:
				missed += 1
	assert_int(missed).is_greater(30)


func test_dropped_middle_packet_loses_no_inputs() -> void:
	var buf: InputBuffer = InputBuffer.new()
	buf.begin_epoch(2)
	var snd: InputSender = InputSender.new()
	snd.reset(2)
	var packets: Array[PackedByteArray] = []
	for t: int in 40:
		var _q: PilotInput = snd.push(t, _input_for(t))
		packets.append(snd.build(0))
	for t: int in 40:
		if t == 20 or (t >= 30 and t <= 31):          # single and double loss
			continue
		var _n: int = buf.submit(packets[t], t)
	for t: int in range(2, 40):
		var p: PilotInput = buf.take(t)
		assert_int(buf.miss_run).is_equal(0)
		assert_float(p.pitch).is_equal(PilotWire.quantized(_input_for(t)).pitch)
	# triple loss does lose the middle tick
	var b2: InputBuffer = InputBuffer.new()
	b2.begin_epoch(2)
	for t: int in 40:
		if t >= 20 and t <= 22:
			continue
		var _n: int = b2.submit(packets[t], t)
	var lost: int = 0
	for t: int in range(2, 40):
		var _p: PilotInput = b2.take(t)
		if b2.miss_run > 0:
			lost += 1
	assert_int(lost).is_equal(1)


func test_silence_decays_then_bridges_once_then_recovers() -> void:
	var r: Array = _run(FaultModel.preset(FaultModel.Preset.LAN), 400, 1, 200, 260)
	var buf: InputBuffer = r[0]
	assert_int(buf.bridge_raised).is_equal(1)
	assert_bool(buf.bridge).is_false()            # fresh input resumed at 260
	assert_int(r[1] as int).is_greater(40)


func test_slow_client_every_other_tick_still_covers_every_tick() -> void:
	var r: Array = _run(FaultModel.preset(FaultModel.Preset.GOOD, 5), 600, 2)
	assert_int(r[1] as int).is_less_equal(2)
	assert_int(r[2] as int).is_equal(0)


func test_determinism_per_seed() -> void:
	var a: Array = _run(FaultModel.preset(FaultModel.Preset.BAD, 21), 800)
	var b: Array = _run(FaultModel.preset(FaultModel.Preset.BAD, 21), 800)
	var c: Array = _run(FaultModel.preset(FaultModel.Preset.BAD, 22), 800)
	assert_int(a[3] as int).is_equal(b[3] as int)
	assert_int((a[0] as InputBuffer).accepted).is_equal((b[0] as InputBuffer).accepted)
	assert_int((a[0] as InputBuffer).duplicates).is_equal((b[0] as InputBuffer).duplicates)
	assert_int(a[2] as int).is_equal(0)
	assert_int(c[2] as int).is_equal(0)
