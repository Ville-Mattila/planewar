extends SceneTree
## NET-06 micro-benchmark: the 400-entity SnapRig scene (A 40 / B 200 / C 160, 04 s4.5 proportions), one shared
## prepare_tick per tick, then encode + decode for one client with a 3-tick ack delay.
## godot --headless --path godot -s res://test/perf/bench_snapshot.gd
## Prints: BENCH_SNAPSHOT n=400 prepare_us=.. encode_us=.. decode_us=.. bytes_per_tick=.. (medians over TICKS)

const WARMUP: int = 60
const TICKS: int = 300


func _init() -> void:
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
	for t: int in WARMUP + TICKS:
		rig.tick += 1
		rig.frame.tick = rig.tick
		rig.step_motion()
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
		var _p: bool = acks.push_back(dec.store.newest_tick)
		if acks.size() > 3:
			store.ack(acks[acks.size() - 4])
		if t >= WARMUP:
			var _x: bool = prep.push_back(t1 - t0)
			var _y: bool = enc.push_back(t2 - t1)
			var _z: bool = dcd.push_back(t3 - t2)
	prep.sort()
	enc.sort()
	dcd.sort()
	var mid: int = TICKS >> 1
	var p95: int = floori(TICKS * 0.95)
	print("BENCH_SNAPSHOT n=400 prepare_us=%d encode_us=%d decode_us=%d bytes_per_tick=%d (p50 over %d ticks; p95 %d/%d/%d)" % [
		prep[mid], enc[mid], dcd[mid], roundi(bytes / float(TICKS)), TICKS, prep[p95], enc[p95], dcd[p95]])
	quit(0)
