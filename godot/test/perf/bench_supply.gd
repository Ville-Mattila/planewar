class_name BenchSupply
extends Node
## GD-18 benchmark: the supply network at the 02 s5.4 limit. 8 players (slots 0-3 team 0, 4-7 team 1), each with a Core,
## 6 Outposts and 30 Pylons in six chains (296 roots and links) plus towers up to 480 structures, all connected.
## godot --headless --path godot res://test/perf/bench_supply.tscn -- [--ticks=900]
## Prints BENCH_SUPPLY rebuild_us (one full rebuild, best/mean of 50), idle_step_us (SupplyNet.step with nothing
## changed, mean of 600) and ECONOMY_ROW p50/p95/max over a run that kills a Pylon every 6 ticks (frequent rebuilds).

const R: float = Sphere.PLANET_RADIUS


func _ready() -> void:
	var ticks: int = 900
	var kill_towers: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):
			ticks = int(arg.substr(8))
		elif arg == "--kill=tower":
			kill_towers = true
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(-1.0, -1.0, true))
	for s: int in range(3, 8):
		w.add_player(s, 0 if s < 4 else 1, &"", PlayerTable.KIND_BOT)
	var pylons: PackedInt32Array = PackedInt32Array()
	var towers: PackedInt32Array = PackedInt32Array()
	for p: int in 8:
		_base(w, p, pylons, towers)
	w.step()
	var net: SupplyNet = w.economy().supply
	var unsup: int = 0
	for s: int in w.store().structures:
		unsup += net.unsupplied[s]
	var st: EntityStore = w.store()
	net._cur = net._seen.duplicate()      # _rebuild and the phases below read the list of the last pass
	var best: int = 1 << 40
	var sum: int = 0
	for _i: int in 50:
		var t0: int = Time.get_ticks_usec()
		net._rebuild()
		var d: int = Time.get_ticks_usec() - t0
		best = mini(best, d)
		sum += d
	var ta: int = Time.get_ticks_usec()
	for _i: int in 50:
		net._collect_nodes()
	var tb: int = Time.get_ticks_usec()
	for _i: int in 50:
		net._link_pylons()
	var tc: int = Time.get_ticks_usec()
	for _i: int in 50:
		for s: int in net._cur:
			var _c: bool = net._covered(s)
	var td: int = Time.get_ticks_usec()
	print("BENCH_PHASES collect_us=%d link_us=%d covered_us=%d" % [(tb - ta) / 50, (tc - tb) / 50, (td - tc) / 50])
	var tu: int = Time.get_ticks_usec()
	for _i: int in 50:
		net._update()
	print("BENCH_UPDATE no_node_change_us=%d" % [(Time.get_ticks_usec() - tu) / 50])
	var idle: int = 0
	var hz_ticks: int = 600
	for i: int in hz_ticks:
		var t1: int = Time.get_ticks_usec()
		net.step(1000 + i, net._epoch)
		idle += Time.get_ticks_usec() - t1
	print("BENCH_SUPPLY structures=%d nodes=%d unsupplied=%d rebuild_best_us=%d rebuild_mean_us=%d idle_step_mean_us=%.1f" % [
		st.structures.size(), net._n_slot.size(), unsup, best, sum / 50, float(idle) / float(hz_ticks)])
	var rows: PackedFloat32Array = PackedFloat32Array()
	var k: int = 0
	for i: int in ticks:
		var victims: PackedInt32Array = towers if kill_towers else pylons
		if i % 6 == 0 and k < victims.size():
			var _c: CommandResult = w.apply_command(CommandPayload.debug_set(0, victims[k], CommandPayload.SET_KILL, 0.0))
			k += 1
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		var _a: bool = rows.push_back(w.profile()[TickProfiler.ROW_ECONOMY])
	rows.sort()
	print("ECONOMY_ROW victims=%s kills=%d p50_ms=%.3f p95_ms=%.3f max_ms=%.3f" % ["tower" if kill_towers else "pylon", k, rows[ticks / 2], rows[int(float(ticks) * 0.95)], rows[ticks - 1]])
	get_tree().quit(0)


# One player's base around direction `c`: Core, 6 arms each with an Outpost root-ish at 700 m and 5 Pylons 200 m apart,
# towers beside the Pylons. Each arm sits inside the Core's radius at its first link.
func _base(w: SimWorld, p: int, pylons: PackedInt32Array, towers: PackedInt32Array) -> void:
	var team: int = 0 if p < 4 else 1
	var ang: float = float(p) * TAU / 8.0
	var c: Vector3 = Vector3(cos(ang), sin(ang), 0.0)
	var along: Vector3 = Vector3(0.0, 0.0, 1.0)
	var side: Vector3 = c.cross(along)
	var _core: int = _put(w, &"core", p, team, c, 0.0)
	for arm: int in 6:
		var a: float = float(arm) * TAU / 6.0
		var t: Vector3 = along * cos(a) + side * sin(a)
		var _o: int = _put(w, &"outpost", p, team, _step(c, t, 800.0 + 0.0), 0.0)
		for j: int in 5:
			var dist: float = 200.0 * float(j + 1)
			var id: int = _put(w, &"relay_pylon", p, team, _step(c, t, dist), 0.0)
			if j == 2:
				var _pp: bool = pylons.push_back(id)
			if j % 2 == 0:
				var _tp: bool = towers.push_back(_put(w, &"autocannon_turret", p, team, _step(c, t, dist + 90.0), 0.0))
	for n: int in 8:
		var _x: int = _put(w, &"solar_array", p, team, _step(c, along, 300.0 + 20.0 * float(n)), 0.0)


# Spawns through the applier directly (debug commands are rate limited per player): the base is laid out in one go.
func _put(w: SimWorld, def: StringName, owner: int, team: int, dir: Vector3, alt: float) -> int:
	var s: int = w._applier.spawn(WorldTestKit.def_id(def), owner, team, dir * (R + alt), Vector3.ZERO, dir.cross(Vector3.BACK), 0)
	return w.store().id_of(s) if s >= 0 else 0


func _step(dir: Vector3, tangent: Vector3, metres: float) -> Vector3:
	var a: float = metres / R
	var t: Vector3 = (tangent - dir * tangent.dot(dir)).normalized()
	return dir * cos(a) + t * sin(a)
