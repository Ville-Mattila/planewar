extends SceneTree
## Replay writer benchmark (NET-25): the replay part of 03 s4.2 row 12 ("events + interest + encode + replay", 4.0 ms
## p95, R0 B.7, A-62) on the NET-49 / NET-08 canonical scene: 940 entities (A 40 / B 200 / C 700; 24 / 70 / 300
## moving), 4 falling bombs. The scene is advanced and prepare_tick runs untimed (the live clients pay for it, the
## writer reads the same cache); ReplayWriter.record_tick is timed for every tick. Replay cost per tick is the mean
## over all ticks (2 of 3 do nothing), `written` is p50 / p95 / p99 over the ticks that write a frame.
## godot --headless --path godot -s res://test/perf/bench_replay.gd [-- --ticks=N]
## Prints BENCH_REPLAY with us per tick, KB/s raw and gzip (no events, no chat) and the file size extrapolated to
## 30 minutes (ADR-10 target <= 20 MB).

const WARMUP: int = 60

var _ticks: int = 1800


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			_ticks = maxi(int(arg.trim_prefix("--ticks=")), 60)
	var rig: ReplayRig = ReplayRig.new()
	rig.build(Vector3i(40, 200, 700), Vector3i(24, 70, 300), 4, 17)
	var w: ReplayWriter = rig.writer
	var _e: int = w.open_memory(rig.header)
	var none: Array[SimEvent] = []
	var all: PackedInt32Array = PackedInt32Array()
	var written: PackedInt32Array = PackedInt32Array()
	var total_us: int = 0
	var frames_before: int = 0
	for t: int in WARMUP + _ticks:
		rig.snap.step()
		var t0: int = Time.get_ticks_usec()
		w.record_tick(rig.snap.codec, rig.snap.tick, rig.slots, rig.snap.roster, none)
		var dt: int = Time.get_ticks_usec() - t0
		if t < WARMUP:
			frames_before = w.frames_written
			continue
		total_us += dt
		if w.frames_written != frames_before:
			var _p: bool = written.push_back(dt)
			frames_before = w.frames_written
	var raw_start: int = w.raw_bytes
	var file: PackedByteArray = w.finish(PackedByteArray(), rig.snap.tick)
	var secs: float = float(WARMUP + _ticks) / SnapRig.HZ
	var gz_kbs: float = file.size() / secs / 1000.0
	print(("BENCH_REPLAY n=%d ticks=%d us_per_tick_mean=%d written_frames=%d written_us_p50=%d p95=%d p99=%d "
			+ "raw_kb_per_s=%.1f gzip_kb_per_s=%.1f ratio=%.1f mb_per_30min=%.1f keyframes=%d deferred=%d budget_us=4000 split_us_per_written_frame meta=%d encode=%d io=%d") % [
		rig.snap.frame.count, _ticks, total_us / _ticks, written.size(), _pct(written, 0.5), _pct(written, 0.95),
		_pct(written, 0.99), raw_start / secs / 1000.0, gz_kbs, float(raw_start) / maxf(file.size(), 1.0),
		gz_kbs * 1800.0 / 1000.0, w.keyframes, w.deferred, w.meta_us / maxi(written.size() + WARMUP / 3, 1), w.encode_us / maxi(written.size() + WARMUP / 3, 1), w.io_us / maxi(written.size() + WARMUP / 3, 1)])
	quit(0)


static func _pct(a: PackedInt32Array, q: float) -> int:
	if a.is_empty():
		return 0
	var s: PackedInt32Array = a.duplicate()
	s.sort()
	return s[mini(floori(q * s.size()), s.size() - 1)]
