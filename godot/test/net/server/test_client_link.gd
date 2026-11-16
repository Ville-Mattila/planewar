extends GdUnitTestSuite
## NET-14: ClientLink handshake and state machine (04 s2.2, s7): HELLO / WELCOME / REFUSE / LOADED, the 5 s HELLO and
## 60 s LOADED timeouts, queues, strikes and the kick rule (04 s11.3), HelloMsg and LinkLimits.


func test_hello_roundtrip_through_hello_msg() -> void:
	var tok: PackedByteArray = PackedByteArray([9, 8, 7])
	var b: PackedByteArray = SessionCodec.encode_hello(LinkRig.hash32(4), tok, 12, Protocol.Platform.WEB,
			Protocol.WireInputClass.TOUCH, Protocol.Role.SPECTATOR, 99, LinkRig.hash32(6).slice(0, 16))
	var m: HelloMsg = HelloMsg.decode(b)
	assert_object(m).is_not_null()
	assert_int(m.version).is_equal(Protocol.PROTOCOL_VERSION)
	assert_array(m.token).is_equal(tok)
	assert_array(m.content_hash).is_equal(LinkRig.hash32(4))
	assert_int(m.build).is_equal(12)
	assert_int(m.platform).is_equal(Protocol.Platform.WEB)
	assert_int(m.input_class).is_equal(Protocol.WireInputClass.TOUCH)
	assert_int(m.role).is_equal(Protocol.Role.SPECTATOR)
	assert_int(m.session_id).is_equal(99)
	assert_int(m.secret.size()).is_equal(Protocol.SECRET_BYTES)


func test_hello_decode_is_total() -> void:
	var good: PackedByteArray = LinkRig.hello()
	assert_object(HelloMsg.decode(good.slice(0, good.size() - 1))).is_null()
	var longer: PackedByteArray = good.duplicate()
	var _p: bool = longer.push_back(0)
	assert_object(HelloMsg.decode(longer)).is_null()
	var bad_role: PackedByteArray = good.duplicate()
	bad_role[bad_role.size() - 16 - 9] = 9
	assert_object(HelloMsg.decode(bad_role)).is_null()
	assert_object(HelloMsg.decode(PackedByteArray())).is_null()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 14
	for _i: int in 2000:
		var junk: PackedByteArray = good.duplicate()
		junk[rng.randi_range(0, junk.size() - 1)] = rng.randi_range(0, 255)
		var _m: HelloMsg = HelloMsg.decode(junk)


func test_handshake_happy_path() -> void:
	var l: ClientLink = LinkRig.new_link(1000)
	assert_int(l.state).is_equal(ClientLink.State.PRE_HELLO)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.hello(), 1010)).is_equal(ClientLink.Verdict.QUEUED)
	assert_object(l.hello).is_not_null()
	assert_bool(l.accept(LinkRig.welcome(), 1020)).is_true()
	assert_int(l.state).is_equal(ClientLink.State.LOADING)
	assert_int(l.slot).is_equal(2)
	assert_int(l.team).is_equal(1)
	assert_int(LinkRig.rig_of(l).ids_sent()[0]).is_equal(Protocol.WELCOME)
	assert_int(l.on_packet(Protocol.CH_CONTROL, SessionCodec.encode_loaded(LinkRig.hash32(9)), 2000)).is_equal(ClientLink.Verdict.QUEUED)
	assert_int(l.state).is_equal(ClientLink.State.LOADED)
	l.start_playing()
	assert_int(l.state).is_equal(ClientLink.State.PLAYING)


func test_accept_needs_a_hello_and_pre_hello_state() -> void:
	var l: ClientLink = LinkRig.new_link()
	assert_bool(l.accept(LinkRig.welcome(), 0)).is_false()
	assert_int(LinkRig.rig_of(l).sent.size()).is_equal(0)
	var m: ClientLink = LinkRig.loading_link()
	assert_bool(m.accept(LinkRig.welcome(), 5)).is_false()


func test_pre_hello_other_messages_dropped_without_strike() -> void:
	var l: ClientLink = LinkRig.new_link()
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.command(1), 0)).is_equal(ClientLink.Verdict.DROPPED_STATE)
	assert_int(l.on_packet(Protocol.CH_CONTROL, SessionCodec.encode_loaded(LinkRig.hash32(9)), 0)).is_equal(ClientLink.Verdict.DROPPED_STATE)
	assert_int(l.strikes).is_equal(0)
	assert_int(l.take_commands().size()).is_equal(0)


func test_malformed_hello_strikes_and_stays_pre_hello() -> void:
	var l: ClientLink = LinkRig.new_link()
	var h: PackedByteArray = LinkRig.hello()
	assert_int(l.on_packet(Protocol.CH_CONTROL, h.slice(0, 40), 0)).is_equal(ClientLink.Verdict.MALFORMED)
	assert_int(l.strikes).is_equal(1)
	assert_object(l.hello).is_null()
	assert_int(l.state).is_equal(ClientLink.State.PRE_HELLO)


func test_second_hello_is_dropped() -> void:
	var l: ClientLink = LinkRig.new_link()
	var _v: int = l.on_packet(Protocol.CH_CONTROL, LinkRig.hello(), 0)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.hello(), 1)).is_equal(ClientLink.Verdict.DROPPED_STATE)


func test_hello_timeout_5s() -> void:
	var l: ClientLink = LinkRig.new_link(1000)
	l.update(5999)
	assert_int(l.state).is_equal(ClientLink.State.PRE_HELLO)
	l.update(6000)
	assert_int(l.state).is_equal(ClientLink.State.CLOSED)
	assert_int(l.close_reason).is_equal(ClientLink.CloseReason.HELLO_TIMEOUT)
	assert_int(LinkRig.rig_of(l).closed.size()).is_equal(1)
	assert_int(LinkRig.rig_of(l).closed[0]).is_equal(7)


func test_hello_before_timeout_stops_the_hello_clock() -> void:
	var l: ClientLink = LinkRig.new_link(0)
	var _v: int = l.on_packet(Protocol.CH_CONTROL, LinkRig.hello(), 4000)
	assert_bool(l.accept(LinkRig.welcome(), 4100)).is_true()
	l.update(9000)
	assert_int(l.state).is_equal(ClientLink.State.LOADING)


func test_loaded_timeout_60s_from_welcome() -> void:
	var l: ClientLink = LinkRig.loading_link(2000)
	l.update(2000 + 59999)
	assert_int(l.state).is_equal(ClientLink.State.LOADING)
	l.update(2000 + 60000)
	assert_int(l.state).is_equal(ClientLink.State.CLOSED)
	assert_int(l.close_reason).is_equal(ClientLink.CloseReason.LOAD_TIMEOUT)
	assert_int(LinkRig.rig_of(l).closed.size()).is_equal(1)


func test_loaded_in_time_cancels_the_load_timeout() -> void:
	var l: ClientLink = LinkRig.loading_link(0)
	var _v: int = l.on_packet(Protocol.CH_CONTROL, SessionCodec.encode_loaded(LinkRig.hash32(9)), 59000)
	l.update(500000)
	assert_int(l.state).is_equal(ClientLink.State.LOADED)


func test_loaded_with_wrong_map_hash_strikes_and_waits() -> void:
	var l: ClientLink = LinkRig.loading_link()
	assert_int(l.on_packet(Protocol.CH_CONTROL, SessionCodec.encode_loaded(LinkRig.hash32(3)), 10)).is_equal(ClientLink.Verdict.MALFORMED)
	assert_int(l.state).is_equal(ClientLink.State.LOADING)
	assert_int(l.strikes).is_equal(1)


func test_refuse_sends_then_closes_after_500ms() -> void:
	var l: ClientLink = LinkRig.new_link(0)
	l.refuse(Protocol.RefuseReason.VERSION, Protocol.PROTOCOL_VERSION, "update required", 100)
	var out: PackedByteArray = LinkRig.rig_of(l).sent[0]
	var d: PackedInt64Array = PackedInt64Array()
	assert_bool(SessionCodec.decode_refuse(out, d)).is_true()
	assert_int(d[0]).is_equal(Protocol.RefuseReason.VERSION)
	assert_int(l.state).is_equal(ClientLink.State.CLOSING)
	l.update(599)
	assert_int(LinkRig.rig_of(l).closed.size()).is_equal(0)
	l.update(600)
	assert_int(l.state).is_equal(ClientLink.State.CLOSED)
	assert_int(l.close_reason).is_equal(ClientLink.CloseReason.REFUSED)
	assert_int(LinkRig.rig_of(l).closed.size()).is_equal(1)


func test_closing_link_ignores_packets() -> void:
	var l: ClientLink = LinkRig.new_link(0)
	l.refuse(Protocol.RefuseReason.MATCH_FULL, 1, "", 0)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.hello(), 1)).is_equal(ClientLink.Verdict.DROPPED_STATE)
	assert_object(l.hello).is_null()


func test_transport_close_sets_closed() -> void:
	var l: ClientLink = LinkRig.loading_link()
	l.on_transport_closed()
	assert_bool(l.is_closed()).is_true()
	assert_int(l.close_reason).is_equal(ClientLink.CloseReason.TRANSPORT)


func test_commands_queue_in_order_with_slot_and_seqs() -> void:
	var l: ClientLink = LinkRig.loading_link()
	for s: int in [1, 2, 3]:
		assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.command(s, 4), 5)).is_equal(ClientLink.Verdict.QUEUED)
	var cmds: Array[Command] = l.take_commands()
	assert_int(cmds.size()).is_equal(3)
	assert_int(cmds[0].player).is_equal(2)
	assert_int(cmds[0].tick).is_equal(4)
	assert_array(l.taken_seqs).is_equal(PackedInt32Array([1, 2, 3]))
	assert_int(l.take_commands().size()).is_equal(0)


func test_duplicate_and_stale_seq_dropped_silently() -> void:
	var l: ClientLink = LinkRig.loading_link()
	var _a: int = l.on_packet(Protocol.CH_CONTROL, LinkRig.command(10), 0)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.command(10), 0)).is_equal(ClientLink.Verdict.DROPPED_STATE)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.command(9), 0)).is_equal(ClientLink.Verdict.DROPPED_STATE)
	assert_int(l.strikes).is_equal(0)
	assert_int(l.take_commands().size()).is_equal(1)
	var _b: int = l.on_packet(Protocol.CH_CONTROL, LinkRig.command(0xFFFF), 0)
	assert_int(l.on_packet(Protocol.CH_CONTROL, LinkRig.command(0), 0)).is_equal(ClientLink.Verdict.QUEUED)   # u16 wrap


func test_malformed_command_answered_and_struck() -> void:
	var l: ClientLink = LinkRig.loading_link()
	var bad: PackedByteArray = LinkRig.command(5)
	bad[bad.size() - 1] = 0
	var _p: bool = bad.push_back(1)               # length field no longer matches
	assert_int(l.on_packet(Protocol.CH_CONTROL, bad, 0)).is_equal(ClientLink.Verdict.MALFORMED)
	assert_int(l.strikes).is_equal(1)
	var r: PackedByteArray = LinkRig.rig_of(l).sent[LinkRig.rig_of(l).sent.size() - 1]
	assert_int(r[0]).is_equal(Protocol.COMMAND_RESULT)
	assert_int(r.decode_u16(1)).is_equal(5)
	assert_int(r[3]).is_equal(Protocol.ResultCode.REJECTED_MALFORMED)


func test_control_and_input_queues_route_by_id() -> void:
	var l: ClientLink = LinkRig.loading_link()
	var _a: int = l.on_packet(Protocol.CH_CONTROL, PackedByteArray([Protocol.LEAVE, 0]), 0)
	var _b: int = l.on_packet(Protocol.CH_CONTROL, PackedByteArray([Protocol.DOCTRINE_PICK, 1, 0]), 0)
	var _c: int = l.on_packet(Protocol.CH_INPUT, SessionCodec.encode_ping(5), 0)
	var _d: int = l.on_packet(Protocol.CH_INPUT, SessionCodec.encode_snapshot_ack(3, 0), 0)
	assert_int(l.take_control().size()).is_equal(2)
	assert_int(l.take_inputs().size()).is_equal(2)
	assert_int(l.take_control().size()).is_equal(0)


func test_input_queue_is_bounded_dropping_oldest() -> void:
	var lim: LinkLimits = LinkLimits.new()
	lim.input_queue_max = 4
	lim.packet_burst = 1000.0
	var l: ClientLink = LinkRig.new_link(0, lim)
	for i: int in 10:
		var _v: int = l.on_packet(Protocol.CH_INPUT, SessionCodec.encode_ping(i), 0)
	var q: Array[PackedByteArray] = l.take_inputs()
	assert_int(q.size()).is_equal(4)
	assert_int(q[0].decode_u32(1)).is_equal(6)


func test_gates_channel_size_id() -> void:
	var l: ClientLink = LinkRig.loading_link()
	assert_int(l.on_packet(Protocol.CH_INPUT, LinkRig.command(1), 0)).is_equal(ClientLink.Verdict.DROPPED_CHANNEL)   # COMMAND is channel 0
	assert_int(l.on_packet(9, PackedByteArray([1]), 0)).is_equal(ClientLink.Verdict.DROPPED_CHANNEL)
	assert_int(l.on_packet(Protocol.CH_INPUT, PackedByteArray(), 0)).is_equal(ClientLink.Verdict.DROPPED_CHANNEL)
	var big: PackedByteArray = PackedByteArray()
	var _r: int = big.resize(65)
	big[0] = Protocol.PING
	assert_int(l.on_packet(Protocol.CH_INPUT, big, 0)).is_equal(ClientLink.Verdict.DROPPED_SIZE)    # ch1 hard cap 64 B
	assert_int(l.on_packet(Protocol.CH_CONTROL, PackedByteArray([Protocol.LEAVE, 0, 0]), 0)).is_equal(ClientLink.Verdict.DROPPED_SIZE)   # above the catalogue max
	assert_int(l.strikes).is_equal(0)
	assert_int(l.on_packet(Protocol.CH_CONTROL, PackedByteArray([0x20, 0]), 0)).is_equal(ClientLink.Verdict.VIOLATION)   # reserved id
	assert_int(l.on_packet(Protocol.CH_CONTROL, PackedByteArray([Protocol.WELCOME, 0]), 0)).is_equal(ClientLink.Verdict.VIOLATION)   # server-bound id
	assert_int(l.strikes).is_equal(2)


func test_twenty_strikes_in_a_minute_kick() -> void:
	var l: ClientLink = LinkRig.loading_link(0)
	for i: int in 19:
		l.add_strike(1, i * 1000)
	assert_int(l.state).is_equal(ClientLink.State.LOADING)
	l.add_strike(1, 19000)
	assert_int(l.state).is_equal(ClientLink.State.CLOSING)
	assert_int(l.close_reason).is_equal(ClientLink.CloseReason.KICKED)
	var last: PackedByteArray = LinkRig.rig_of(l).sent[LinkRig.rig_of(l).sent.size() - 1]
	assert_int(last[0]).is_equal(Protocol.ADMIN_NOTICE)
	assert_int(last[1]).is_equal(Protocol.AdminNotice.KICK)
	assert_int(last.size()).is_less_equal(Protocol.max_bytes(Protocol.ADMIN_NOTICE))
	l.update(19000 + 500)
	assert_bool(l.is_closed()).is_true()
	assert_int(LinkRig.rig_of(l).closed.size()).is_equal(1)


func test_strikes_spread_over_more_than_a_minute_do_not_kick() -> void:
	var l: ClientLink = LinkRig.loading_link(0)
	for i: int in 60:
		l.add_strike(1, i * 4000)                  # 15 per minute
	assert_int(l.state).is_equal(ClientLink.State.LOADING)
	assert_int(l.strikes).is_equal(60)
	assert_int(l.strikes_recent(59 * 4000)).is_less(20)


func test_limits_from_defs_take_rules_and_match_rules() -> void:
	var rules: RulesDef = RulesDef.new()
	rules.command_rate_per_s = 12
	rules.command_burst = 40
	var mr: MatchRulesDef = MatchRulesDef.new()
	mr.load_timeout_s = 45.0
	var lim: LinkLimits = LinkLimits.from_defs(rules, mr)
	assert_float(lim.command_per_s).is_equal(12.0)
	assert_float(lim.command_burst).is_equal(40.0)
	assert_int(lim.load_timeout_ms).is_equal(45000)
	var d: LinkLimits = LinkLimits.from_defs(null, null)
	assert_int(d.hello_timeout_ms).is_equal(5000)
	assert_int(d.load_timeout_ms).is_equal(60000)
	assert_int(LinkLimits.channel_cap(Protocol.CH_CONTROL)).is_equal(1024)
	assert_int(LinkLimits.channel_cap(Protocol.CH_INPUT)).is_equal(64)
	assert_int(LinkLimits.channel_cap(Protocol.CH_SNAPSHOT)).is_equal(2048)
	assert_int(LinkLimits.channel_cap(Protocol.CH_EVENTS)).is_equal(2048)
	assert_int(LinkLimits.channel_cap(4)).is_equal(0)


func test_shipped_defs_agree_with_link_defaults() -> void:
	assert_bool(ContentDB.load_all().ok).is_true()
	var lim: LinkLimits = LinkLimits.from_defs(ContentDB.rules, ContentDB.match_rules)
	assert_float(lim.command_per_s).is_equal(10.0)
	assert_float(lim.command_burst).is_equal(30.0)
	assert_int(lim.load_timeout_ms).is_equal(60000)
