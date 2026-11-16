extends GdUnitTestSuite
## NET-14 "validator_test rate rows": every row of the 04 s11.4 rate table as seen by one ClientLink, a positive
## (inside the bucket) and a negative (excess) case each, on the deterministic caller-supplied clock.


func _cmd_link() -> ClientLink:
	var lim: LinkLimits = LinkLimits.new()
	lim.packet_burst = 100000.0          # isolate the row under test from the packet / byte buckets
	lim.packets_per_s = 100000.0
	lim.byte_burst = 1.0e9
	lim.bytes_per_s = 1.0e9
	var l: ClientLink = ClientLink.new(3, LinkRig.new(), lim, 0)
	var _v: int = l.on_packet(Protocol.CH_CONTROL, LinkRig.hello(), 0)
	var _a: bool = l.accept(LinkRig.welcome(), 0)
	return l


func test_packets_per_link_120_per_second() -> void:
	var l: ClientLink = LinkRig.loading_link(0)
	var ok: int = 0
	for i: int in 200:
		if l.on_packet(Protocol.CH_INPUT, SessionCodec.encode_ping(i), 0) == ClientLink.Verdict.QUEUED:
			ok += 1
	assert_int(ok).is_equal(119)             # the burst of 120 minus the HELLO that opened the link
	assert_int(l.dropped_rate).is_equal(81)
	assert_int(l.strikes).is_equal(0)
	# a second later 120 more fit
	assert_int(l.on_packet(Protocol.CH_INPUT, SessionCodec.encode_ping(0), 1000)).is_equal(ClientLink.Verdict.QUEUED)


func test_steady_30hz_inputs_never_hit_the_packet_limit() -> void:
	var l: ClientLink = LinkRig.loading_link(0)
	for i: int in 300:
		assert_int(l.on_packet(Protocol.CH_INPUT, SessionCodec.encode_ping(i), i * 33)).is_equal(ClientLink.Verdict.QUEUED)
		var _q: Array[PackedByteArray] = l.take_inputs()


func test_bytes_per_link_8kb_per_second() -> void:
	var lim: LinkLimits = LinkLimits.new()
	lim.chat_burst = 1000.0               # isolate the byte bucket: CHAT is the largest catalogue-legal channel-0 packet here
	var l: ClientLink = ClientLink.new(3, LinkRig.new(), lim, 0)
	var _v: int = l.on_packet(Protocol.CH_CONTROL, LinkRig.hello(), 0)
	var _a: bool = l.accept(LinkRig.welcome(), 0)
	var chat: PackedByteArray = LinkRig.chat()
	var _p: int = chat.resize(210)
	var accepted: int = 0
	for _i: int in 60:
		if l.on_packet(Protocol.CH_CONTROL, chat, 0) == ClientLink.Verdict.QUEUED:
			accepted += 1
		var _x: Array[PackedByteArray] = l.take_control()
	assert_int(accepted * 210).is_less_equal(8192)
	assert_int(accepted).is_greater_equal(38)
	assert_int(l.dropped_rate).is_equal(60 - accepted)


func test_command_10_per_s_burst_30() -> void:
	var l: ClientLink = _cmd_link()
	var ok: int = 0
	for s: int in 40:
		if l.on_packet(Protocol.CH_CONTROL, LinkRig.command(s + 1), 0) == ClientLink.Verdict.QUEUED:
			ok += 1
	assert_int(ok).is_equal(30)
	assert_int(l.take_commands().size()).is_equal(30)
	# 10 refused with REJECTED_RATE, each naming its seq, and no strike
	var rate_results: int = 0
	for b: PackedByteArray in LinkRig.rig_of(l).sent:
		if b[0] == Protocol.COMMAND_RESULT and b[3] == Protocol.ResultCode.REJECTED_RATE:
			rate_results += 1
	assert_int(rate_results).is_equal(10)
	assert_int(l.strikes).is_equal(0)
	# one second later: 10 sustained
	var again: int = 0
	for s: int in 20:
		if l.on_packet(Protocol.CH_CONTROL, LinkRig.command(100 + s), 1000) == ClientLink.Verdict.QUEUED:
			again += 1
	assert_int(again).is_equal(10)


func test_command_sustained_rate_is_accepted() -> void:
	var l: ClientLink = _cmd_link()
	for s: int in 100:
		assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.command(s + 1), s * 100)).is_equal(ClientLink.Verdict.QUEUED)   # 10/s


func test_chat_2_per_s_burst_5() -> void:
	var l: ClientLink = _cmd_link()
	var ok: int = 0
	for _i: int in 9:
		if l.on_packet(Protocol.CH_CONTROL, LinkRig.chat(), 0) == ClientLink.Verdict.QUEUED:
			ok += 1
	assert_int(ok).is_equal(5)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.chat(), 500)).is_equal(ClientLink.Verdict.QUEUED)     # 1 token back
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.chat(), 500)).is_equal(ClientLink.Verdict.DROPPED_RATE)


func test_quick_ping_1_per_s_burst_3() -> void:
	var l: ClientLink = _cmd_link()
	var ok: int = 0
	for _i: int in 6:
		if l.on_packet(Protocol.CH_CONTROL, LinkRig.quick_ping(), 0) == ClientLink.Verdict.QUEUED:
			ok += 1
	assert_int(ok).is_equal(3)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.quick_ping(), 1000)).is_equal(ClientLink.Verdict.QUEUED)


func test_request_keyframe_one_per_5s() -> void:
	var l: ClientLink = _cmd_link()
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.keyframe_request(), 0)).is_equal(ClientLink.Verdict.QUEUED)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.keyframe_request(), 4900)).is_equal(ClientLink.Verdict.DROPPED_RATE)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.keyframe_request(), 5000)).is_equal(ClientLink.Verdict.QUEUED)


func test_max_message_size_per_channel_before_parsing() -> void:
	var l: ClientLink = _cmd_link()
	var ch0: PackedByteArray = PackedByteArray()
	var _a: int = ch0.resize(1025)
	assert_int(l.on_packet(Protocol.CH_CONTROL, ch0, 0)).is_equal(ClientLink.Verdict.DROPPED_SIZE)
	var ch2: PackedByteArray = PackedByteArray()
	var _b: int = ch2.resize(2049)
	assert_int(l.on_packet(Protocol.CH_SNAPSHOT, ch2, 0)).is_equal(ClientLink.Verdict.DROPPED_SIZE)
	assert_int(l.on_packet(Protocol.CH_EVENTS, ch2, 0)).is_equal(ClientLink.Verdict.DROPPED_SIZE)
	assert_int(l.strikes).is_equal(0)


func test_rate_limits_follow_the_defs() -> void:
	var lim: LinkLimits = LinkLimits.new()
	lim.command_per_s = 2.0
	lim.command_burst = 3.0
	var l: ClientLink = ClientLink.new(3, LinkRig.new(), lim, 0)
	var _v: int = l.on_packet(Protocol.CH_CONTROL, LinkRig.hello(), 0)
	var _a: bool = l.accept(LinkRig.welcome(), 0)
	var ok: int = 0
	for s: int in 6:
		if l.on_packet(Protocol.CH_CONTROL, LinkRig.command(s + 1), 0) == ClientLink.Verdict.QUEUED:
			ok += 1
	assert_int(ok).is_equal(3)
