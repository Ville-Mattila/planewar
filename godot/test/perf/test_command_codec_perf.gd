extends GdUnitTestSuite
## NET-04 perf note: encode/decode cost of the COMMAND codec per kind. Not a per-tick path (<= 10 commands/s per
## client, 04 s2.3 / 11.3). Prints microseconds per call; no absolute assertion (ADR-11, I11).


func test_codec_cost_per_kind() -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 32:
		ids.append(0x10000 + i)
	var pts: OrderSpec = OrderSpec.make(OrderSpec.Kind.PATROL)
	for i: int in 14:
		pts.points.append(Codec.dequantize_pos(Codec.quantize_pos(Vector3(1.0, 0.05 + 0.07 * float(i), 0.3).normalized() * 6400.0)))
	var here: Vector3 = Vector3(0.0, 6400.0, 10.0)
	var rows: Array = [
		["ORDER 32 ids x 14 pts", Command.order(1, ids, pts)],
		["ORDER MOVE 4 ids", Command.order(1, ids.slice(0, 4), OrderSpec.make(OrderSpec.Kind.MOVE, 0, here))],
		["ORDER ESCORT 32 ids", Command.order(1, ids, OrderSpec.make(OrderSpec.Kind.ESCORT, 3))],
		["SET_RALLY", Command.set_rally(1, 6, here)],
		["PRODUCE", Command.produce(1, 6, 8, 3)],
		["TOGGLE_AUTO_REPLENISH x8", Command.toggle_auto_replenish(1, 6, true, PackedInt32Array([1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8]))],
		["SET_ADJUTANT", Command.set_adjutant(1, true, 1, 3)],
	]
	var n: int = 2000
	for row: Array in rows:
		var cmd: Command = row[1]
		var out: PackedByteArray = PackedByteArray()
		var t0: int = Time.get_ticks_usec()
		for i: int in n:
			var _e: bool = CommandCodec.encode_payload(cmd, out)
		var t1: int = Time.get_ticks_usec()
		var wire: PackedByteArray = out.duplicate()
		for i: int in n:
			var _d: Command = CommandCodec.decode_payload(cmd.kind, cmd.target, wire)
		var t2: int = Time.get_ticks_usec()
		print("NET-04 perf %s: %d B wire, encode %.2f us, decode %.2f us" % [row[0], wire.size(), float(t1 - t0) / n, float(t2 - t1) / n])
		assert_int(wire.size()).is_greater(0)
