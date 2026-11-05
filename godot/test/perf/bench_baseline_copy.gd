extends SceneTree
## NET-59 microbench: BaselineFrame.copy_from / clear at several high-water marks vs the former full duplicate / fill.
## Run: godot --headless --path godot -s test/perf/bench_baseline_copy.gd

const REPS: int = 4000


func _init() -> void:
	for n: int in [0, 100, 940, 1536, 3584]:
		var src: BaselineFrame = BaselineFrame.new()
		for i: int in n:
			src.set_full(i, 1, 5, 0x1234, 3, 4, 5, 6)
		var dst: BaselineFrame = BaselineFrame.new()
		var t0: int = Time.get_ticks_usec()
		for r: int in REPS:
			dst.copy_from(src, r)
		var t1: int = Time.get_ticks_usec()
		for r: int in REPS:
			dst.copy_from(src, r)
			dst.clear(r)
		var t2: int = Time.get_ticks_usec()
		for r: int in REPS:
			dst.copy_from(src, r)
			dst.hi = 0 if n == 0 else dst.hi
			dst.base_tick = _old_clear(dst)
		var t3: int = Time.get_ticks_usec()
		for r: int in REPS:
			_old_copy(dst, src)
		var t4: int = Time.get_ticks_usec()
		print("BENCH hi=%d copy_us=%.2f oldcopy_us=%.2f clear_after_copy_us=%.2f oldfill_us=%.2f" % [n, float(t1 - t0) / REPS,
				float(t4 - t3) / REPS, float(t2 - t1) / REPS - float(t1 - t0) / REPS, float(t3 - t2) / REPS - float(t1 - t0) / REPS])
	quit(0)


func _old_clear(f: BaselineFrame) -> int:
	f.present.fill(0)
	f.pos.fill(0)
	f.ori.fill(0)
	f.ori_c.fill(0)
	f.vel.fill(0)
	f.hp.fill(0)
	f.flags.fill(0)
	f.ai.fill(0)
	f.blip.fill(DeadReckon.BLIP_UNKNOWN)
	f.etick.fill(0)
	return 0


func _old_copy(d: BaselineFrame, s: BaselineFrame) -> void:
	d.present = s.present.duplicate()
	d.pos = s.pos.duplicate()
	d.ori = s.ori.duplicate()
	d.ori_c = s.ori_c.duplicate()
	d.vel = s.vel.duplicate()
	d.hp = s.hp.duplicate()
	d.flags = s.flags.duplicate()
	d.ai = s.ai.duplicate()
	d.blip = s.blip.duplicate()
	d.etick = s.etick.duplicate()
