extends SceneTree
## TA-11 micro-benchmark: alloc then free of 2,000 entities and 2,000 projectiles per round.
## godot --headless --path godot -s res://test/perf/bench_stores.gd
## Prints: BENCH_STORES e_alloc_us=.. e_free_us=.. p_alloc_us=.. p_free_us=.. (per op, best of ROUNDS)
## Entity kinds cycle STRUCTURE/SHIP/GROUND/WRECK, so of 2,000 entity allocs 1,279 (main range)
## + 256 (wreck range) succeed and 465 take the full-range refusal path; frees of those are no-ops.

const ROUNDS: int = 20
const N: int = 2000


func _init() -> void:
	var best: PackedInt32Array = PackedInt32Array([1 << 30, 1 << 30, 1 << 30, 1 << 30])
	var tick: int = 0
	var es: EntityStore = EntityStore.new()
	var ps: ProjectileStore = ProjectileStore.new(N)
	var slots: PackedInt32Array = PackedInt32Array()
	var _r: int = slots.resize(N)
	for round_i: int in ROUNDS:
		tick += EntityStore.QUARANTINE_TICKS   # last round's frees leave quarantine
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			slots[i] = EntityId.slot(es.alloc(i & 3, tick))
		var t1: int = Time.get_ticks_usec()
		for i: int in N:
			var _ok: bool = es.free_slot(slots[i], tick)
		var t2: int = Time.get_ticks_usec()
		for i: int in N:
			slots[i] = ps.index_of(ps.alloc(i % 6, tick))
		var t3: int = Time.get_ticks_usec()
		for i: int in N:
			var _ok: bool = ps.free_slot(slots[i], tick)
		var t4: int = Time.get_ticks_usec()
		best[0] = mini(best[0], t1 - t0)
		best[1] = mini(best[1], t2 - t1)
		best[2] = mini(best[2], t3 - t2)
		best[3] = mini(best[3], t4 - t3)
	var n: float = float(N)
	print("BENCH_STORES e_alloc_us=%.3f e_free_us=%.3f p_alloc_us=%.3f p_free_us=%.3f e_alloc_total_us=%d e_free_total_us=%d p_alloc_total_us=%d p_free_total_us=%d" % [
		float(best[0]) / n, float(best[1]) / n, float(best[2]) / n, float(best[3]) / n,
		best[0], best[1], best[2], best[3]])
	quit(0)
