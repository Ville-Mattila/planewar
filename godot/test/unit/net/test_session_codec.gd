extends GdUnitTestSuite
## NET-17 SessionCodec (04 s2.2, s2.3): HELLO / LOADED / PING / SNAPSHOT_ACK layouts and sizes, WELCOME / REFUSE /
## MATCH_STATE / PONG / MATCH_END round trips and malformed tables, UTF-8 validation, and the N5 fuzz sweep: 100,000
## mutations per decoded message id, never an error; an accepted WELCOME / REFUSE / MATCH_STATE / PONG re-encodes to
## the identical bytes (the decoders are canonical), a rejected one writes nothing.


func _hash(v: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(Protocol.HASH_BYTES)
	b.fill(v)
	return b


func _welcome(players: int) -> WelcomeInfo:
	var w: WelcomeInfo = WelcomeInfo.new()
	w.conn_id = 0x1234
	w.slot = 3
	w.team = 1
	w.session_id = 0x0102030405060708
	var _r: int = w.secret.resize(Protocol.SECRET_BYTES)
	for k: int in Protocol.SECRET_BYTES:
		w.secret[k] = 0xA0 + k
	w.tick = 18042
	w.server_ms = 777
	w.map_id = "tiny_test"
	w.map_hash = _hash(0x5A)
	w.config = PackedByteArray([1, 2, 3, 4, 5])
	for k: int in players:
		w.add_player(k, k & 1, k % 3, Protocol.DOCTRINE_HIDDEN if k == 0 else k, k % 3, "pilot%dé" % k)
	return w


func _same_welcome(a: WelcomeInfo, b: WelcomeInfo) -> bool:
	return a.conn_id == b.conn_id and a.slot == b.slot and a.team == b.team and a.session_id == b.session_id \
			and a.secret == b.secret and a.tick == b.tick and a.server_ms == b.server_ms and a.map_id == b.map_id \
			and a.map_hash == b.map_hash and a.config == b.config and a.player_slot == b.player_slot \
			and a.player_team == b.player_team and a.player_kind == b.player_kind and a.player_doctrine == b.player_doctrine \
			and a.player_input == b.player_input and a.player_name == b.player_name


func test_client_messages_layout() -> void:
	var hello: PackedByteArray = SessionCodec.encode_hello(_hash(7), PackedByteArray([9, 8, 7]), 42, Protocol.Platform.WEB,
			Protocol.WireInputClass.TOUCH, Protocol.Role.PLAYER, 99, _hash(1).slice(0, 16))
	assert_int(hello.size()).is_equal(SessionCodec.HELLO_FIXED_BYTES + 3)
	assert_int(hello[0]).is_equal(Protocol.HELLO)
	assert_int(hello.decode_u16(1)).is_equal(Protocol.PROTOCOL_VERSION)
	assert_int(hello[35]).is_equal(3)
	assert_int(hello.decode_u32(39)).is_equal(42)
	assert_int(hello[43]).is_equal(Protocol.Platform.WEB)
	assert_int(hello.decode_s64(46)).is_equal(99)
	assert_int(hello.size()).is_less_equal(Protocol.max_bytes(Protocol.HELLO))
	var big: PackedByteArray = PackedByteArray()
	var _r: int = big.resize(SessionCodec.TOKEN_MAX)
	assert_int(SessionCodec.encode_hello(_hash(7), big, 0, 0, 0, 0).size()).is_equal(Protocol.max_bytes(Protocol.HELLO) - 3)
	var _r2: int = big.resize(SessionCodec.TOKEN_MAX + 1)
	assert_bool(SessionCodec.encode_hello(_hash(7), big, 0, 0, 0, 0).is_empty()).is_true()
	assert_bool(SessionCodec.encode_hello(PackedByteArray([1]), PackedByteArray(), 0, 0, 0, 0).is_empty()).is_true()
	assert_int(SessionCodec.encode_loaded(_hash(3)).size()).is_equal(Protocol.max_bytes(Protocol.LOADED))
	assert_bool(SessionCodec.encode_loaded(PackedByteArray([3])).is_empty()).is_true()
	var ping: PackedByteArray = SessionCodec.encode_ping(0x11223344)
	assert_array(Array(ping)).is_equal([Protocol.PING, 0x44, 0x33, 0x22, 0x11])
	var ack: PackedByteArray = SessionCodec.encode_snapshot_ack(18039, 5)
	assert_int(ack.size()).is_equal(Protocol.max_bytes(Protocol.SNAPSHOT_ACK))
	assert_int(ack.decode_u32(1)).is_equal(18039)
	assert_int(ack.decode_u16(5)).is_equal(5)


func test_server_messages_round_trip() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	assert_bool(SessionCodec.decode_pong(SessionCodec.encode_pong(1, 2, 3), out)).is_true()
	assert_array(Array(out)).is_equal([1, 2, 3])
	assert_bool(SessionCodec.decode_match_state(SessionCodec.encode_match_state(Protocol.SessionPhase.PLAYING, 900, 90, 0x0F), out)).is_true()
	assert_array(Array(out)).is_equal([Protocol.SessionPhase.PLAYING, 900, 90, 0x0F])
	var refuse: PackedByteArray = SessionCodec.encode_refuse(Protocol.RefuseReason.VERSION, 2, "update required")
	assert_bool(SessionCodec.decode_refuse(refuse, out)).is_true()
	assert_array(Array(out)).is_equal([Protocol.RefuseReason.VERSION, 2])
	assert_int(refuse.size()).is_less_equal(Protocol.max_bytes(Protocol.REFUSE))
	for n: int in [0, 1, 8]:
		var w: WelcomeInfo = _welcome(n)
		var b: PackedByteArray = SessionCodec.encode_welcome(w)
		assert_int(b.size()).is_less_equal(Protocol.max_bytes(Protocol.WELCOME))
		var got: WelcomeInfo = WelcomeInfo.new()
		assert_bool(SessionCodec.decode_welcome(b, got)).is_true()
		assert_bool(_same_welcome(w, got)).is_true()
	var end: PackedByteArray = PackedByteArray([Protocol.MATCH_END, 1, Protocol.MatchEndReason.SURRENDER, 0x10, 0, 0, 0])
	end.append_array(_hash(0))
	assert_bool(SessionCodec.decode_match_end_head(end, out)).is_true()
	assert_array(Array(out)).is_equal([1, Protocol.MatchEndReason.SURRENDER, 16])


func test_malformed_server_messages_are_rejected() -> void:
	var out: PackedInt64Array = PackedInt64Array([7])
	assert_bool(SessionCodec.decode_pong(SessionCodec.encode_pong(1, 2, 3).slice(0, 12), out)).is_false()
	assert_bool(SessionCodec.decode_match_state(SessionCodec.encode_match_state(Protocol.SessionPhase.size(), 1, 0, 0), out)).is_false()
	var refuse: PackedByteArray = SessionCodec.encode_refuse(Protocol.RefuseReason.size(), 1, "")
	assert_bool(SessionCodec.decode_refuse(refuse, out)).is_false()
	var text: PackedByteArray = SessionCodec.encode_refuse(0, 1, "abc")
	text[4] = 4
	assert_bool(SessionCodec.decode_refuse(text, out)).is_false()
	var end: PackedByteArray = PackedByteArray([Protocol.MATCH_END, 1, Protocol.MatchEndReason.size(), 0, 0, 0, 0])
	end.append_array(_hash(0))
	assert_bool(SessionCodec.decode_match_end_head(end, out)).is_false()
	assert_array(Array(out)).is_equal([7])
	var w: PackedByteArray = SessionCodec.encode_welcome(_welcome(2))
	var got: WelcomeInfo = WelcomeInfo.new()
	var cases: Array[PackedByteArray] = []
	cases.append(w.slice(0, w.size() - 1))
	var tail: PackedByteArray = w.duplicate()
	var _t: bool = tail.push_back(0)
	cases.append(tail)
	var slot: PackedByteArray = w.duplicate()
	slot[3] = 8
	cases.append(slot)
	var name_utf8: PackedByteArray = w.duplicate()
	name_utf8[w.size() - 1] = 0xFF
	cases.append(name_utf8)
	var map_len: PackedByteArray = w.duplicate()
	map_len[37] = 65
	cases.append(map_len)
	for c: PackedByteArray in cases:
		assert_bool(SessionCodec.decode_welcome(c, got)).is_false()
	assert_int(got.tick).is_equal(0)                                         # nothing written
	var spectator: WelcomeInfo = _welcome(1)
	spectator.slot = Protocol.SLOT_SPECTATOR
	assert_bool(SessionCodec.decode_welcome(SessionCodec.encode_welcome(spectator), got)).is_true()


func test_utf8_validation() -> void:
	var ok: Array[PackedByteArray] = ["abc".to_utf8_buffer(), "äé€😀".to_utf8_buffer(), PackedByteArray()]
	for b: PackedByteArray in ok:
		assert_bool(SessionCodec.utf8_ok(b, 0, b.size())).is_true()
	var bad: Array[PackedByteArray] = [PackedByteArray([0xC0, 0x80]), PackedByteArray([0xE0, 0x80, 0x80]),
			PackedByteArray([0xED, 0xA0, 0x80]), PackedByteArray([0xF4, 0x90, 0x80, 0x80]), PackedByteArray([0xE2, 0x82]),
			PackedByteArray([0x80]), PackedByteArray([0xF5, 0x80, 0x80, 0x80]), PackedByteArray([0x41, 0x00])]
	for b: PackedByteArray in bad:
		assert_bool(SessionCodec.utf8_ok(b, 0, b.size())).override_failure_message(str(b)).is_false()


func _fuzz(seeds: Array[PackedByteArray], seed_value: int, kind: int) -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: PackedInt64Array = PackedInt64Array()
	var w: WelcomeInfo = WelcomeInfo.new()
	var accepted: int = 0
	for i: int in NetFuzz.MUTATIONS:
		var m: PackedByteArray = NetFuzz.mutate(rng, seeds[i % seeds.size()], 40)
		var ok: bool = false
		var again: PackedByteArray = PackedByteArray()
		match kind:
			Protocol.WELCOME:
				ok = SessionCodec.decode_welcome(m, w)
				again = SessionCodec.encode_welcome(w) if ok else again
			Protocol.PONG:
				ok = SessionCodec.decode_pong(m, out)
				again = SessionCodec.encode_pong(out[0], out[1], out[2]) if ok else again
			Protocol.MATCH_STATE:
				ok = SessionCodec.decode_match_state(m, out)
				again = SessionCodec.encode_match_state(out[0], out[1], out[2], out[3]) if ok else again
			Protocol.REFUSE:
				ok = SessionCodec.decode_refuse(m, out)
				if ok:
					again = SessionCodec.encode_refuse(out[0], out[1], m.slice(5).get_string_from_utf8()) 							if SessionCodec.utf8_ok(m, 5, m.size()) else m
			_:
				ok = SessionCodec.decode_match_end_head(m, out)
				again = m
		if ok:
			accepted += 1
			if again != m:
				fail("id 0x%x mutation %d accepted but does not re-encode" % [kind, i])
				return -1
	return accepted


func test_fuzz_welcome_100000() -> void:
	var seeds: Array[PackedByteArray] = [SessionCodec.encode_welcome(_welcome(0)), SessionCodec.encode_welcome(_welcome(3))]
	assert_int(_fuzz(seeds, 0x80, Protocol.WELCOME)).is_greater(0)


func test_fuzz_refuse_match_state_pong_match_end_100000_each() -> void:
	var end: PackedByteArray = PackedByteArray([Protocol.MATCH_END, 0, 0, 1, 0, 0, 0])
	end.append_array(_hash(1))
	end.append_array(PackedByteArray([2, 0, 0, 0, 0]))
	assert_int(_fuzz([SessionCodec.encode_refuse(1, 1, "full")], 0x81, Protocol.REFUSE)).is_greater(0)
	assert_int(_fuzz([SessionCodec.encode_match_state(3, 10, 0, 1)], 0x82, Protocol.MATCH_STATE)).is_greater(0)
	assert_int(_fuzz([SessionCodec.encode_pong(5, 6, 7)], 0x8B, Protocol.PONG)).is_greater(0)
	assert_int(_fuzz([end], 0x8E, Protocol.MATCH_END)).is_greater(0)
