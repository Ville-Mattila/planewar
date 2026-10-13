extends GdUnitTestSuite
## NET-11: LocalTransport semantics, channel ordering and reliability, FaultModel determinism and fault windows.


func _model(lat: float, jit: float, loss: float, reo: float, dup: float, seed_arg: int = 7) -> FaultModel:
	var m: FaultModel = FaultModel.new()
	m.seed_value = seed_arg
	m.latency_ms = lat
	m.jitter_ms = jit
	m.loss = loss
	m.reorder = reo
	m.duplicate = dup
	return m


func test_kind_and_connect_events() -> void:
	var r: LocalRig = LocalRig.new()
	assert_str(String(r.server.kind())).is_equal("local")
	r.step()
	assert_array(r.client_events).is_equal(["connected"])
	assert_array(r.server_events).is_equal(["connected"])
	assert_int(r.server_conn).is_equal(1)
	assert_int(r.server.connection_count()).is_equal(1)


func test_zero_latency_delivers_on_next_poll_in_order() -> void:
	var r: LocalRig = LocalRig.new()
	for ch: int in Protocol.CHANNEL_COUNT:
		for i: int in 5:
			r.send_s2c(ch, ch * 100 + i)
	r.step()
	assert_int(r.at_client.size()).is_equal(20)
	var last: int = -1
	for row: Vector3i in r.at_client:
		if row.y == 0:
			assert_int(row.z).is_greater(last)
			last = row.z


func test_multiple_clients_get_distinct_conn_ids() -> void:
	var clock: LocalClock = LocalClock.new()
	var s: LocalTransport = LocalTransport.new_server(clock)
	var a: LocalTransport = s.connect_client(Protocol.Platform.WEB)
	var b: LocalTransport = s.connect_client()
	assert_bool(a.server_conn_of() != b.server_conn_of()).is_true()
	assert_int(s.platform_hint(a.server_conn_of())).is_equal(Protocol.Platform.WEB)
	assert_int(s.platform_hint(b.server_conn_of())).is_equal(Protocol.Platform.LINUX)


func test_latency_delays_delivery() -> void:
	var r: LocalRig = LocalRig.new(_model(110.0, 0.0, 0.0, 0.0, 0.0))
	r.send_s2c(Protocol.CH_SNAPSHOT, 1)
	r.run_ticks(3)
	assert_int(r.at_client.size()).is_equal(0)
	r.run_ticks(1)
	assert_int(r.at_client.size()).is_equal(1)       # 110 ms -> due at tick 4 (133 ms)
	assert_int(r.server.rtt_ms(r.server_conn)).is_equal(220)


func test_reliable_channels_never_lose_and_keep_order() -> void:
	var m: FaultModel = _model(80.0, 60.0, 0.5, 0.5, 0.3)
	var r: LocalRig = LocalRig.new(m)
	for i: int in 300:
		r.send_s2c(Protocol.CH_CONTROL, i)
		r.send_s2c(Protocol.CH_EVENTS, i)
		r.send_c2s(Protocol.CH_CONTROL, i)
		r.step()
	r.run_ticks(60)
	for ch: int in [Protocol.CH_CONTROL, Protocol.CH_EVENTS]:
		var seen: Array[int] = []
		for row: Vector3i in r.at_client:
			if row.y == ch:
				seen.append(row.z)
		assert_int(seen.size()).is_equal(300)
		for i: int in 300:
			assert_int(seen[i]).is_equal(i)
	var up: Array[int] = []
	for row: Vector3i in r.at_server:
		up.append(row.z)
	assert_int(up.size()).is_equal(300)
	for i: int in 300:
		assert_int(up[i]).is_equal(i)


func test_sequenced_channel_never_goes_backwards_and_no_duplicates() -> void:
	var r: LocalRig = LocalRig.new(_model(60.0, 50.0, 0.1, 0.3, 0.3))
	for i: int in 1000:
		r.send_s2c(Protocol.CH_SNAPSHOT, i)
		r.step()
	r.run_ticks(30)
	var last: int = -1
	for row: Vector3i in r.at_client:
		assert_int(row.z).is_greater(last)
		last = row.z
	assert_int(r.at_client.size()).is_less(1000)


func test_unreliable_input_channel_may_reorder_and_duplicate() -> void:
	var r: LocalRig = LocalRig.new(_model(60.0, 30.0, 0.0, 0.3, 0.3))
	for i: int in 1000:
		r.send_c2s(Protocol.CH_INPUT, i)
		r.step()
	r.run_ticks(30)
	var backwards: int = 0
	var seen: Dictionary[int, int] = {}
	var last: int = -1
	for row: Vector3i in r.at_server:
		if row.z < last:
			backwards += 1
		last = row.z
		seen[row.z] = seen.get(row.z, 0) + 1
	var dups: int = 0
	for k: int in seen:
		if seen[k] > 1:
			dups += 1
	assert_int(backwards).is_greater(0)
	assert_int(dups).is_greater(0)
	assert_int(seen.size()).is_equal(1000)            # no loss configured: every index arrives at least once


func test_same_seed_same_delivery_order_different_seed_differs() -> void:
	var prints: Array[int] = []
	for seed_arg: int in [11, 11, 12]:
		var r: LocalRig = LocalRig.new(_model(80.0, 40.0, 0.1, 0.1, 0.1, seed_arg))
		for i: int in 600:
			r.send_s2c(Protocol.CH_SNAPSHOT, i)
			r.send_s2c(Protocol.CH_CONTROL, i)
			r.send_c2s(Protocol.CH_INPUT, i)
			r.step()
		r.run_ticks(30)
		prints.append(LocalRig.fingerprint(r.at_client) ^ (LocalRig.fingerprint(r.at_server) << 1))
	assert_int(prints[0]).is_equal(prints[1])
	assert_int(prints[0]).is_not_equal(prints[2])


func test_directions_are_independent() -> void:
	var r: LocalRig = LocalRig.new(_model(0.0, 0.0, 1.0, 0.0, 0.0), true, false)   # s2c loses everything
	for i: int in 50:
		r.send_s2c(Protocol.CH_SNAPSHOT, i)
		r.send_c2s(Protocol.CH_INPUT, i)
	r.step()
	assert_int(r.at_client.size()).is_equal(0)
	assert_int(r.at_server.size()).is_equal(50)
	assert_float(r.server.stats(r.server_conn).loss_estimate).is_equal(1.0)


func test_bandwidth_limit_queues_then_drops_unreliable() -> void:
	var m: FaultModel = _model(0.0, 0.0, 0.0, 0.0, 0.0)
	m.bandwidth_kbps = 80.0                 # 10 B/ms: a 1,000 B packet takes 100 ms
	var r: LocalRig = LocalRig.new(m)
	for i: int in 10:
		r.send_s2c(Protocol.CH_SNAPSHOT, i, 1000)
		r.send_s2c(Protocol.CH_CONTROL, i, 1000)
	r.run_ticks(200)
	var snaps: int = 0
	var ctrl: int = 0
	for row: Vector3i in r.at_client:
		if row.y == Protocol.CH_SNAPSHOT:
			snaps += 1
		else:
			ctrl += 1
	assert_int(ctrl).is_equal(10)           # reliable queues, never drops
	assert_int(snaps).is_less(10)           # queue beyond 250 ms dropped
	assert_int(snaps).is_greater(0)


func test_burst_loss_drops_unreliable_and_delays_reliable() -> void:
	var m: FaultModel = _model(0.0, 0.0, 0.0, 0.0, 0.0)
	m.burst_loss.append(Vector2i(10, 20))
	var r: LocalRig = LocalRig.new(m)
	for t: int in 40:
		r.send_s2c(Protocol.CH_SNAPSHOT, t)
		r.send_s2c(Protocol.CH_CONTROL, t)
		r.step()
	r.run_ticks(10)
	for row: Vector3i in r.at_client:
		if row.y == Protocol.CH_SNAPSHOT:
			assert_bool(row.z < 10 or row.z >= 20).is_true()
	var reliable_in_window: int = 0
	for row: Vector3i in r.at_client:
		if row.y == Protocol.CH_CONTROL and row.z >= 10 and row.z < 20:
			reliable_in_window += 1
			assert_int(row.x).is_greater_equal(20)             # held until the window ends
	assert_int(reliable_in_window).is_equal(10)


func test_stall_holds_everything_then_releases_in_order() -> void:
	var m: FaultModel = _model(0.0, 0.0, 0.0, 0.0, 0.0)
	m.stall_at(10, 1000.0)                  # 30 ticks
	var r: LocalRig = LocalRig.new(m)
	for t: int in 60:
		r.send_s2c(Protocol.CH_SNAPSHOT, t)
		r.send_s2c(Protocol.CH_EVENTS, t)
		r.step()
	r.run_ticks(5)
	var first_in_stall: int = -1
	for row: Vector3i in r.at_client:
		if row.z >= 10 and row.z < 40:
			assert_int(row.x).is_greater_equal(40)
			first_in_stall = row.x
	assert_int(first_in_stall).is_greater(0)
	var order: Array[int] = []
	for row: Vector3i in r.at_client:
		if row.y == Protocol.CH_EVENTS:
			order.append(row.z)
	assert_int(order.size()).is_equal(60)
	for i: int in 60:
		assert_int(order[i]).is_equal(i)


func test_close_notifies_both_sides() -> void:
	var r: LocalRig = LocalRig.new()
	r.step()
	r.server.close(r.server_conn, Transport.DisconnectReason.LOCAL_CLOSE)
	r.step()
	assert_array(r.server_events).contains(["disc%d" % Transport.DisconnectReason.LOCAL_CLOSE])
	assert_array(r.client_events).contains(["disc%d" % Transport.DisconnectReason.REMOTE_CLOSE])
	assert_int(r.server.connection_count()).is_equal(0)
	r.send_s2c(Protocol.CH_CONTROL, 1)                # send on a closed conn is a no-op
	r.step()
	assert_int(r.at_client.size()).is_equal(0)


func test_stats_report_since_last_call() -> void:
	var r: LocalRig = LocalRig.new()
	r.send_s2c(Protocol.CH_CONTROL, 1, 100)
	r.send_s2c(Protocol.CH_SNAPSHOT, 2, 50)
	r.step()
	var s: TransportStats = r.server.stats(r.server_conn)
	assert_int(s.bytes_out).is_equal(150)
	assert_int(s.packets_out).is_equal(2)
	var c: TransportStats = r.client.stats(LocalTransport.CLIENT_CONN)
	assert_int(c.bytes_in).is_equal(150)
	assert_int(c.packets_in).is_equal(2)
	assert_int(r.server.stats(r.server_conn).bytes_out).is_equal(0)
