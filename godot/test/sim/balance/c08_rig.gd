class_name C08Rig extends RefCounted
## GD-26 / C-08 rig (02 s18.3): one Dart of team 0 and one of team FOE, both under the real DartBrain AUTO (the driver's
## choice point, no orders), `separation_m` apart at `AGL_M` on the flat datum, nose to nose at cruise speed. Seed `k` feeds
## the world's roll stream and a seeded lateral offset and altitude difference of the pair; odd seeds swap the sides (team 0
## east) and the spawn order, so a side or slot-order bias shows in the totals. A run ends when one Dart dies or after
## `max_s` (a draw). `winner`: 0 = team 0, 1 = FOE, -1 = draw.

const AGL_M: float = 300.0
const C0: Vector3 = Vector3(1, 0, 0)
const HZ: int = 30

var w: SimWorld
var driver: AiDriver
var a: int = 0                          # team 0's Dart
var b: int = 0                          # FOE's Dart
var winner: int = -1
var end_tick: int = -1
var max_s: float = 15.0
var min_dist_m: float = INF            # closest approach of the pair
var rounds: int = 0                    # gun rounds the pair spent (ammo drop)
var ammo0: int = 0


func build(seed_value: int, separation_m: float) -> void:
	w = Ai14Kit.world(seed_value)
	driver = Ai14Kit.driver(w, true, 3, [true, false, false, false])
	var rng: Rng = Rng.new(seed_value * 7919 + 13)
	var lat: float = (rng.next_float() - 0.5) * 300.0                          # +-150 m lateral offset between the pair
	var dalt: float = (rng.next_float() - 0.5) * 100.0                         # +-50 m altitude difference
	var half: float = separation_m * 0.5
	var sgn: float = 1.0 if seed_value % 2 == 0 else -1.0                      # team 0 west on even seeds
	var p0: Vector3 = DartKit.above(w, DartKit.offset(C0, -half * sgn, -lat * 0.5), AGL_M + dalt * 0.5)
	var p1: Vector3 = DartKit.above(w, DartKit.offset(C0, half * sgn, lat * 0.5), AGL_M - dalt * 0.5)
	var spd: float = Ai14Kit.ship(&"dart").v_cruise
	var h0: Vector3 = DartKit.heading(p0, p1)
	var h1: Vector3 = DartKit.heading(p1, p0)
	if seed_value % 4 < 2:
		a = DartKit.spawn(w, &"dart", 0, p0, h0 * spd, h0)
		b = DartKit.spawn(w, &"dart", DartKit.FOE, p1, h1 * spd, h1)
	else:
		b = DartKit.spawn(w, &"dart", DartKit.FOE, p1, h1 * spd, h1)
		a = DartKit.spawn(w, &"dart", 0, p0, h0 * spd, h0)


func run() -> void:
	var v: SimView = w.view()
	ammo0 = v.ammo(a) + v.ammo(b)
	for k: int in int(max_s) * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
		var a_up: bool = v.alive(a)
		var b_up: bool = v.alive(b)
		if a_up and b_up:
			min_dist_m = minf(min_dist_m, v.pos(a).distance_to(v.pos(b)))
			rounds = ammo0 - v.ammo(a) - v.ammo(b)
			continue
		end_tick = k
		winner = 0 if a_up else (1 if b_up else -1)
		return
	end_tick = int(max_s) * HZ
