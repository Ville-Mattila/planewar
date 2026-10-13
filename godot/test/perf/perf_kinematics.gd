class_name PerfKinematics
extends SceneTree
## Kinematics micro-benchmark (TA-12; 03 s4.2 row "kinematics" 3.0 ms, s5.2 "~6 us per ship").
## godot --headless --path godot -s res://test/perf/perf_kinematics.gd [-- --ships=400 --ticks=300]
## Prints PERF_KIN lines: per-call us for step_ship over N ships (each its own ShipState and input) and for
## step_projectile (straight and ballistic): `alloc` (out omitted, a new ProjectileState per call), `out` (one
## reused scratch, R0 B.9 A-12, TA-43) and `store` (2,000 live ProjectileStore slots read/stepped/written back with
## the scratch, the 03 s4.2 "projectiles" row's motion share). Loop overhead included. Report only; no gate (03 s12.1).

const DEFS: String = "../tools/tests/fixtures/content/canonical/godot/content/defs/"
const REPS: int = 30


func _initialize() -> void:
	var ships: int = 400
	var ticks: int = 300
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ships="):
			ships = int(arg.substr(8))
		elif arg.begins_with("--ticks="):
			ticks = int(arg.substr(8))
	var ships_json: Dictionary = _json("ships.json")
	var dart: ShipDef = ShipDef.from_dict((ships_json["ships"] as Array)[0] as Dictionary)
	var common: FlightCommonDef = FlightCommonDef.from_dict(ships_json["flight_common"] as Dictionary)
	var rules: RulesDef = RulesDef.from_dict(_json("rules.json"))
	var dt: float = 1.0 / float(rules.tick_hz)
	var states: Array[ShipState] = []
	var inputs: Array[PilotInput] = []
	for k: int in ships:
		var t: float = float(k + 1)
		var dir: Vector3 = Vector3(sin(t * 12.9898), sin(t * 78.233), sin(t * 37.719)).normalized()
		var s: ShipState = ShipState.new()
		s.p = dir * (Sphere.PLANET_RADIUS + 400.0 + float(k % 7) * 100.0)
		s.fwd = Sphere.tangent_frame(s.p).x
		s.up = dir
		s.v = s.fwd * dart.v_cruise
		s.fuel = dart.fuel_s
		states.append(s)
		var inp: PilotInput = PilotInput.new()
		inp.thrust = 0.5 + 0.5 * sin(t)
		inp.pitch = sin(t * 3.1) * 0.3
		inp.yaw = sin(t * 5.7) * 0.2
		inp.roll = sin(t * 7.3) * 0.5
		inputs.append(inp)
	var terrain: Terrain = Terrain.new()
	var t0: int = Time.get_ticks_usec()
	for _tick: int in ticks:
		for k: int in ships:
			var _r: ShipState = Kinematics.step_ship(states[k], inputs[k], dart, common, rules, terrain, dt)
	var us: float = float(Time.get_ticks_usec() - t0)
	var per_call: float = us / float(ticks * ships)
	print("PERF_KIN fn=step_ship ships=%d ticks=%d us_per_call=%.3f us_per_tick=%.1f" % [
		ships, ticks, per_call, per_call * float(ships)])
	_bench_projectiles(rules, dt)
	quit(0)


func _bench_projectiles(rules: RulesDef, dt: float) -> void:
	var list: Array = _json("projectiles.json")["projectiles"]
	for idx: int in [0, 2]:                                      # slug_light (straight), bomb (ballistic)
		var def: ProjectileDef = ProjectileDef.from_dict(list[idx] as Dictionary)
		var n: int = 2000
		var p: Vector3 = Vector3(Sphere.PLANET_RADIUS + 300.0, 0.0, 0.0)
		var v: Vector3 = Vector3(0.0, 700.0, 0.0)
		var t0: int = Time.get_ticks_usec()
		for _rep: int in REPS:
			for _k: int in n:
				var ps: ProjectileState = Kinematics.step_projectile(p, v, def, rules, dt)
				p = ps.p
		_report(def.id, "alloc", t0, n)
		var scratch: ProjectileState = ProjectileState.new()
		p = Vector3(Sphere.PLANET_RADIUS + 300.0, 0.0, 0.0)
		t0 = Time.get_ticks_usec()
		for _rep: int in REPS:
			for _k: int in n:
				var _ps: ProjectileState = Kinematics.step_projectile(p, v, def, rules, dt, scratch)
				p = scratch.p
		_report(def.id, "out", t0, n)
		_bench_store(def, rules, dt, n)


## ProjectileMotion's loop shape: iterate the live list, step with the one scratch, write pos / vel back.
func _bench_store(def: ProjectileDef, rules: RulesDef, dt: float, n: int) -> void:
	var store: ProjectileStore = ProjectileStore.new(n)
	for k: int in n:
		var i: int = store.index_of(store.alloc(ProjectileStore.SLUG, 0))
		store.pos[i] = Vector3(Sphere.PLANET_RADIUS + 300.0 + float(k % 50), float(k), 0.0)
		store.vel[i] = Vector3(0.0, 700.0, 0.0)
	var scratch: ProjectileState = ProjectileState.new()
	var t0: int = Time.get_ticks_usec()
	for _rep: int in REPS:
		for i: int in store.live:
			var _ps: ProjectileState = Kinematics.step_projectile(store.pos[i], store.vel[i], def, rules, dt, scratch)
			store.pos[i] = scratch.p
			store.vel[i] = scratch.v
	_report(def.id, "store", t0, n)


func _report(id: StringName, mode: String, t0: int, n: int) -> void:
	var per_call: float = float(Time.get_ticks_usec() - t0) / float(REPS * n)
	print("PERF_KIN fn=step_projectile kind=%s mode=%s us_per_call=%.3f us_per_2000=%.1f" % [
		id, mode, per_call, per_call * float(n)])


func _json(file: String) -> Dictionary:
	var path: String = ProjectSettings.globalize_path("res://").path_join(DEFS + file)
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
