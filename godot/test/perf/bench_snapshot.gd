extends SceneTree
## Snapshot codec micro-benchmarks (NET-06, NET-49).
## godot --headless --path godot -s res://test/perf/bench_snapshot.gd [-- --history[=path] --ticks=N]
##
## canonical (R0 B.10 A-40, 04 s4.1 / s4.5): 940 entities (A 40 / B 200 / C 700; 24 / 70 / 300 moving), 8
## clients with ack delays 3 / 6 / 10 ticks, A every tick, B on (tick + k) % 2 == 0, C on (tick + k) % 15 == 0,
## plus 3 rolling-refresh FULLs per client per tick in section C. Per tick: one prepare_tick, then encode for
## each client (timed). No loss: every tick is complete, so client k's ack for tick t arrives at t + delay (no
## client decoders in the process, which would double the server's working set). The FULL / C-BLIP byte cache
## (NET-49) is on for even ticks and off (the pre-NET-49 path, same bytes) for odd ticks, so both see the same
## scene and the same machine noise; the 04 s4.1 schedule repeats every 30 ticks, so both halves get the same
## mix. Prints BENCH_SNAPSHOT mode=canonical .. prepare_us encode_sum_us total_us (p50 / p95, cache on),
## encode_sum_us_uncached, and per-client encode p50 / p95 for both. `--history` appends the cache-on row to
## perf/history.jsonl (03 s14 row shape {sha, runner, scenario, row, p50, p95, p99}).
##
## all-tiers (NET-06): the 400-entity scene encoding every entity for one client every tick (3-tick acks).
##
## interest (NET-08): the canonical scene and schedule with the lists from real Interest (InterestRig: client k
## possesses A mover 6 + k, chase camera, team-visible everything as in 04 s4.5) instead of the fixed tier split.
## Times prepare_tick, Interest.begin_tick + assign x 8, ENTITY_META / ROSTER_REMOVE encoding and encode x 8 (with
## the rig's rolling refresh); prints p50 / p95 per part and of the sum, mean A / B / C sizes, bytes and KB/s
## per client (payload + 38 B per packet). `--history` also appends this row (scenario bench_snapshot_interest_8c).

const WARMUP: int = 60
const CLIENTS: int = 8
const ACK_DELAYS: Array[int] = [3, 6, 10]
const BUDGET_US: int = 4000                 # 03 s4.2 row 12 "events + interest + encode + replay" (R0 B.7)

var _ticks: int = 600
var _history: String = ""


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			_ticks = maxi(int(arg.trim_prefix("--ticks=")), 20)
		elif arg == "--history":
			_history = ProjectSettings.globalize_path("res://").path_join("../perf/history.jsonl")
		elif arg.begins_with("--history="):
			_history = arg.trim_prefix("--history=")
	var m: Dictionary = _canonical()                      # first: the number the history row records
	_print_canonical(m)
	if _history != "":
		_append_history(m)
	_interest_mode()
	_all_tiers()
	quit(0)


func _interest_mode() -> void:
	var rig: InterestRig = InterestRig.new()
	rig.build(CLIENTS, Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	var parts: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(),
		PackedInt32Array(), PackedInt32Array()]                       # prepare, interest, meta, encode, total
	var sizes: Vector3 = Vector3.ZERO
	var bytes: int = 0
	var packets: int = 0
	for t: int in WARMUP + _ticks:
		rig.snap.tick += 1
		rig.snap.frame.tick = rig.snap.tick
		rig.snap.step_motion()
		var t0: int = Time.get_ticks_usec()
		rig.snap.codec.prepare_tick(rig.snap.frame)
		var t1: int = Time.get_ticks_usec()
		rig.run_interest()
		var t2: int = Time.get_ticks_usec()
		var reliable: Array[PackedByteArray] = []
		for k: int in CLIENTS:
			rig.roster_packets(k, reliable)
		var t3: int = Time.get_ticks_usec()
		var outs: Array[PackedByteArray] = []
		for k: int in CLIENTS:
			var _n: int = rig.encode(k, outs)
			rig.stores[k].ack(rig.snap.tick - ACK_DELAYS[k % ACK_DELAYS.size()])
		var t4: int = Time.get_ticks_usec()
		if t < WARMUP:
			continue
		for i: int in 5:
			var _p: bool = parts[i].push_back([t1 - t0, t2 - t1, t3 - t2, t4 - t3, t4 - t0][i])
		for cl: InterestClient in rig.clients:
			sizes += Vector3(cl.a.size(), cl.b.size(), cl.c.size())
		for p: PackedByteArray in outs + reliable:
			bytes += p.size()
			packets += 1
	var per_ct: float = float(_ticks * CLIENTS)
	var link_kbps: float = (bytes + packets * 38) * SnapRig.HZ / per_ct / 1000.0
	print(("BENCH_SNAPSHOT mode=interest clients=%d n=%d prepare_us=%d interest_us=%d meta_us=%d encode_sum_us=%d "
			+ "total_us=%d (p50 over %d ticks; p95 %d/%d/%d/%d/%d; budget_us=%d) lists_per_client_tick a=%.1f b=%.1f "
			+ "c=%.1f bytes_per_client_tick=%d kb_per_s_per_client=%.2f link_kb_per_s=%.2f") % [
		CLIENTS, rig.snap.frame.count, _pct(parts[0], 0.5), _pct(parts[1], 0.5), _pct(parts[2], 0.5),
		_pct(parts[3], 0.5), _pct(parts[4], 0.5), _ticks, _pct(parts[0], 0.95), _pct(parts[1], 0.95),
		_pct(parts[2], 0.95), _pct(parts[3], 0.95), _pct(parts[4], 0.95), BUDGET_US, sizes.x / per_ct,
		sizes.y / per_ct, sizes.z / per_ct, roundi(bytes / per_ct), bytes * SnapRig.HZ / per_ct / 1000.0, link_kbps])
	if _history != "":
		_append_row({"scenario": "bench_snapshot_interest_8c", "row": "row12_prepare_interest_encode_8c",
			"n": rig.snap.frame.count, "interest_us_p50": _pct(parts[1], 0.5), "interest_us_p95": _pct(parts[1], 0.95),
			"p50": _pct(parts[4], 0.5), "p95": _pct(parts[4], 0.95), "p99": _pct(parts[4], 0.99), "budget_us": BUDGET_US})


func _all_tiers() -> void:
	var rig: SnapRig = SnapRig.new()
	rig.build(Vector3i(40, 200, 160), Vector3i(24, 70, 60), 4, 17)
	var store: BaselineStore = BaselineStore.new(0)
	var dec: SnapshotDecoder = rig.new_decoder(0)
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	var c: PackedInt32Array = PackedInt32Array()
	var prep: PackedInt32Array = PackedInt32Array()
	var enc: PackedInt32Array = PackedInt32Array()
	var dcd: PackedInt32Array = PackedInt32Array()
	var bytes: int = 0
	var acks: PackedInt32Array = PackedInt32Array()
	for t: int in WARMUP + _ticks:
		rig.tick += 1
		rig.frame.tick = rig.tick
		rig.step_motion()
		var on: int = 1 if t % 2 == 0 else 0
		rig.codec.cache_bytes = on == 1
		var t0: int = Time.get_ticks_usec()
		rig.codec.prepare_tick(rig.frame)
		var t1: int = Time.get_ticks_usec()
		rig.lists(0, a, b, c)
		var out: Array[PackedByteArray] = []
		var _n: int = rig.codec.encode(store, rig.tick, a, b, c, null, out)
		var t2: int = Time.get_ticks_usec()
		for p: PackedByteArray in out:
			var _s: int = dec.decode(p)
			if t >= WARMUP:
				bytes += p.size()
		var t3: int = Time.get_ticks_usec()
		var _p: bool = acks.push_back(dec.store.complete_tick)
		if acks.size() > 3:
			store.ack(acks[acks.size() - 4])
		if t >= WARMUP:
			var _x: bool = prep.push_back(t1 - t0)
			var _y: bool = enc.push_back(t2 - t1)
			var _z: bool = dcd.push_back(t3 - t2)
	print("BENCH_SNAPSHOT mode=all_tiers n=400 prepare_us=%d encode_us=%d decode_us=%d bytes_per_tick=%d (p50 over %d ticks; p95 %d/%d/%d)" % [
		_pct(prep, 0.5), _pct(enc, 0.5), _pct(dcd, 0.5), roundi(bytes / float(_ticks)), _ticks,
		_pct(prep, 0.95), _pct(enc, 0.95), _pct(dcd, 0.95)])


func _canonical() -> Dictionary:
	var rig: SnapRig = SnapRig.new()
	rig.build(Vector3i(40, 200, 700), Vector3i(24, 70, 300), 6, 17)
	var stores: Array[BaselineStore] = []
	for k: int in CLIENTS:
		stores.append(BaselineStore.new(k % 3))
	var a: PackedInt32Array = PackedInt32Array()
	var b: PackedInt32Array = PackedInt32Array()
	var c: PackedInt32Array = PackedInt32Array()
	var r: PackedInt32Array = PackedInt32Array()
	var prep: PackedInt32Array = PackedInt32Array()
	var esum: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]   # [uncached, cached]
	var tot: PackedInt32Array = PackedInt32Array()
	var per: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
	var bytes: int = 0
	var full0: int = 0
	var blip0: int = 0
	var delta0: int = 0
	var digest: HashingContext = HashingContext.new()
	var _d: int = digest.start(HashingContext.HASH_SHA256)
	for t: int in WARMUP + _ticks:
		if t == WARMUP:
			full0 = rig.codec.n_full
			blip0 = rig.codec.n_blip
			delta0 = rig.codec.n_delta
		rig.tick += 1
		rig.frame.tick = rig.tick
		rig.step_motion()
		var on: int = 1 if t % 2 == 0 else 0
		rig.codec.cache_bytes = on == 1
		var t0: int = Time.get_ticks_usec()
		rig.codec.prepare_tick(rig.frame)
		var t1: int = Time.get_ticks_usec()
		var enc: int = 0
		for k: int in CLIENTS:
			rig.canonical_lists(k, a, b, c, r)
			var out: Array[PackedByteArray] = []
			var e0: int = Time.get_ticks_usec()
			var _n: int = rig.codec.encode(stores[k], rig.tick, a, b, c, null, out, r)
			var e1: int = Time.get_ticks_usec()
			enc += e1 - e0
			if t >= WARMUP:
				var _q: bool = per[on].push_back(e1 - e0)
			for p: PackedByteArray in out:
				var _u: int = digest.update(p)
				bytes += p.size() if t >= WARMUP else 0
			stores[k].ack(rig.tick - ACK_DELAYS[k % ACK_DELAYS.size()])
		if t >= WARMUP:
			var _x: bool = prep.push_back(t1 - t0)
			var _y: bool = esum[on].push_back(enc)
			if on == 1:
				var _z: bool = tot.push_back(t1 - t0 + enc)
	var ticks: float = float(_ticks)
	return {"n": rig.frame.count, "prepare": prep, "encode_sum": esum[1], "encode_sum_uncached": esum[0],
		"total": tot, "per_client": per[1], "per_client_uncached": per[0],
		"bytes_per_client_tick": roundi(bytes / (ticks * CLIENTS)),
		"records_per_client_tick": Vector3((rig.codec.n_full - full0) / (ticks * CLIENTS),
				(rig.codec.n_delta - delta0) / (ticks * CLIENTS), (rig.codec.n_blip - blip0) / (ticks * CLIENTS)),
		"digest": digest.finish().hex_encode().substr(0, 16)}


func _print_canonical(m: Dictionary) -> void:
	var prep: PackedInt32Array = m["prepare"]
	var esum: PackedInt32Array = m["encode_sum"]
	var esum0: PackedInt32Array = m["encode_sum_uncached"]
	var tot: PackedInt32Array = m["total"]
	var per: PackedInt32Array = m["per_client"]
	var per0: PackedInt32Array = m["per_client_uncached"]
	var rec: Vector3 = m["records_per_client_tick"]
	print(("BENCH_SNAPSHOT mode=canonical clients=%d n=%d prepare_us=%d encode_sum_us=%d total_us=%d " 			+ "encode_sum_us_uncached=%d (p50 over %d + %d ticks; p95 %d/%d/%d/%d; budget_us=%d) " 			+ "client_encode_us p50=%d p95=%d uncached p50=%d p95=%d bytes_per_client_tick=%d " 			+ "records_per_client_tick full=%.1f delta=%.1f blip=%.1f bytes_sha=%s") % [
		CLIENTS, int(m["n"]), _pct(prep, 0.5), _pct(esum, 0.5), _pct(tot, 0.5), _pct(esum0, 0.5), esum.size(),
		esum0.size(), _pct(prep, 0.95), _pct(esum, 0.95), _pct(tot, 0.95), _pct(esum0, 0.95), BUDGET_US,
		_pct(per, 0.5), _pct(per, 0.95), _pct(per0, 0.5), _pct(per0, 0.95), int(m["bytes_per_client_tick"]),
		rec.x, rec.y, rec.z, str(m["digest"])])


func _append_history(m: Dictionary) -> void:
	var tot: PackedInt32Array = m["total"]
	var prep: PackedInt32Array = m["prepare"]
	var esum: PackedInt32Array = m["encode_sum"]
	var per: PackedInt32Array = m["per_client"]
	var esum0: PackedInt32Array = m["encode_sum_uncached"]
	var row: Dictionary = {"scenario": "bench_snapshot_canonical_8c", "row": "snapshot_prepare_plus_encode_8c", "n": m["n"],
		"prepare_us_p50": _pct(prep, 0.5), "encode_sum_us_p50": _pct(esum, 0.5),
		"p50": _pct(tot, 0.5), "p95": _pct(tot, 0.95), "p99": _pct(tot, 0.99),
		"client_encode_us_p95": _pct(per, 0.95),
		"encode_sum_us_uncached_p50": _pct(esum0, 0.5), "budget_us": BUDGET_US}
	_append_row(row)


## Appends `row` (plus sha and runner) to perf/history.jsonl (03 s14 row shape).
func _append_row(row: Dictionary) -> void:
	var dir: String = _history.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var _mk: Error = DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(_history, FileAccess.READ_WRITE if FileAccess.file_exists(_history) else FileAccess.WRITE)
	if f == null:
		push_error("bench_snapshot: cannot open %s" % _history)
		return
	f.seek_end()
	row["sha"] = _env("GITHUB_SHA", "local")
	row["runner"] = _env("RUNNER_NAME", "local")
	var _ok: bool = f.store_line(JSON.stringify(row))
	f.close()
	print("BENCH_SNAPSHOT history appended to %s (%s)" % [_history, str(row["scenario"])])


static func _env(key: String, fallback: String) -> String:
	var v: String = OS.get_environment(key)
	return v if v != "" else fallback


static func _pct(values: PackedInt32Array, q: float) -> int:
	if values.is_empty():
		return 0
	var s: PackedInt32Array = values.duplicate()
	s.sort()
	return s[clampi(floori(float(s.size()) * q), 0, s.size() - 1)]
