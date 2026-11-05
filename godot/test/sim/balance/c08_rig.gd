class_name C08Rig extends RefCounted
## GD-26 / C-08 rig (02 s18.3): one Dart of team 0 and one of team FOE, both under the real DartBrain AUTO (the driver's
## choice point, no orders), `separation_m` apart at `AGL_M` on the flat datum, nose to nose at cruise speed. A run ends
## when one Dart dies or after `max_s` (a draw). `winner`: 0 = team 0, 1 = FOE, -1 = draw (both alive, or both dead:
## a ram, 01 s3.1.3, counted in `rammed`).
## AI-46 (R0 B.27 A-140): the world is symmetric (`world`: one player per side, no doctrine; the kits' FOE player has
## Vanguard, 80 HP and +15 % speed and rates, so GD-26's pair was not); seeds 2k - 1 and 2k fly one seeded geometry
## (lateral offset +-150 m, altitude difference +-50 m) with the sides swapped, odd seeds putting team 0 east, and the
## spawn order is by side (the west Dart first on even pairs), so on the odd seed of a pair the team spawn order is
## swapped as well: a side, slot-order or spawn-order bias shows as a share off 50 %, the geometry cancels in pairs.
## Per Dart (index 0 = team 0's, 1 = FOE's): rounds fired, rounds fired while the true lead (`AimSolver.lead_point`,
## no aim error) was inside the shooter's 05 s6.2 fire cone, hits landed (HIT events by the shooter), EXTEND entries
## and the break-offs among them (target ahead of the nose at entry), ENGAGE ticks.

const AGL_M: float = 300.0
const C0: Vector3 = Vector3(1, 0, 0)
const HZ: int = 30

var w: SimWorld
var driver: AiDriver
var a: int = 0                          # team 0's Dart
var b: int = 0                          # FOE's Dart
var winner: int = -1
var rammed: bool = false               # both died on the same tick
var end_tick: int = -1
var max_s: float = 15.0
var min_dist_m: float = INF            # closest approach of the pair
var rounds: int = 0                    # gun rounds the pair spent (ammo drop)
var ammo0: int = 0
var fired: PackedInt32Array = PackedInt32Array([0, 0])
var fired_in_cone: PackedInt32Array = PackedInt32Array([0, 0])
var hits: PackedInt32Array = PackedInt32Array([0, 0])
var extends_n: PackedInt32Array = PackedInt32Array([0, 0])
var breakoffs: PackedInt32Array = PackedInt32Array([0, 0])
var engage_ticks: PackedInt32Array = PackedInt32Array([0, 0])
var _ammo: PackedInt32Array = PackedInt32Array([0, 0])
var _tag: PackedInt32Array = PackedInt32Array([0, 0])
static var _prm: DartParams = null


## A world on the AI-14 content with one player per side and no doctrine on either.
static func world(seed_value: int) -> SimWorld:
	var sw: SimWorld = SimWorld.new(Ai14Kit.content())
	var res: Result = sw.load_map(MapDef.new(), seed_value, DartKit.rules())
	assert(res.ok, res.message)
	sw.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	sw.add_player(1, DartKit.FOE, &"", PlayerTable.KIND_HUMAN)
	return sw


## `Ai14Kit.driver` with only the Dart brain built (the other three cost a third of a 200-duel run), hooked into `sw`.
static func dart_driver(sw: SimWorld) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(3))
	d.set_class_table(AiClassTable.from_content(Ai14Kit.content()))
	d.set_brain(Ai14Kit.cls(&"dart"), Ai14Kit.dart(sw.terrain()))
	d.set_overlay_params(Ai14Kit.cls(&"dart"), Ai14Kit.overlays(&"dart"))
	d.set_terrain(sw.terrain())
	var intel: TeamIntel = TeamIntel.new(IntelKit.tables(), IntelKit.profile("team"), Ai14Kit.content().rules.tick_hz)
	intel.track(0, true)
	intel.track(DartKit.FOE, true)
	d.set_intel(intel)
	sw.set_ai_hook(d)
	return d


func build(seed_value: int, separation_m: float) -> void:
	w = world(seed_value)
	driver = dart_driver(w)
	var pair: int = (seed_value + 1) >> 1                                      # seeds 2k - 1 and 2k share one geometry
	var rng: Rng = Rng.new(pair * 7919 + 13)
	var sgn: float = 1.0 if seed_value % 2 == 0 else -1.0                      # team 0 west on even seeds
	var lat: float = (rng.next_float() - 0.5) * 300.0 * sgn                    # +-150 m lateral offset between the pair
	var dalt: float = (rng.next_float() - 0.5) * 100.0 * sgn                   # +-50 m altitude difference
	var half: float = separation_m * 0.5
	var p0: Vector3 = DartKit.above(w, DartKit.offset(C0, -half * sgn, -lat * 0.5), AGL_M + dalt * 0.5)
	var p1: Vector3 = DartKit.above(w, DartKit.offset(C0, half * sgn, lat * 0.5), AGL_M - dalt * 0.5)
	var spd: float = Ai14Kit.ship(&"dart").v_cruise
	var h0: Vector3 = DartKit.heading(p0, p1)
	var h1: Vector3 = DartKit.heading(p1, p0)
	if (pair % 2 == 0) == (seed_value % 2 == 0):                               # the west Dart first on even pairs
		a = DartKit.spawn(w, &"dart", 0, p0, h0 * spd, h0)
		b = DartKit.spawn(w, &"dart", DartKit.FOE, p1, h1 * spd, h1)
	else:
		b = DartKit.spawn(w, &"dart", DartKit.FOE, p1, h1 * spd, h1)
		a = DartKit.spawn(w, &"dart", 0, p0, h0 * spd, h0)
	if _prm == null:
		_prm = DartParams.from_content(Ai14Kit.ap(&"dart"), Ai14Kit.ship(&"dart"), Ai14Kit.content())


func run() -> void:
	var v: SimView = w.view()
	ammo0 = v.ammo(a) + v.ammo(b)
	_ammo[0] = v.ammo(a)
	_ammo[1] = v.ammo(b)
	for k: int in int(max_s) * HZ:
		for e: SimEvent in Ai14Kit.step(w):
			if e.kind == SimEvent.Kind.HIT and (e.b == a or e.b == b):
				hits[0 if e.b == a else 1] += 1
		var a_up: bool = v.alive(a)
		var b_up: bool = v.alive(b)
		if a_up and b_up:
			min_dist_m = minf(min_dist_m, v.pos(a).distance_to(v.pos(b)))
			rounds = ammo0 - v.ammo(a) - v.ammo(b)
			_observe(v, 0, a, b)
			_observe(v, 1, b, a)
			continue
		end_tick = k
		winner = 0 if a_up else (1 if b_up else -1)
		rammed = not a_up and not b_up
		return
	end_tick = int(max_s) * HZ


# One Dart's counters for this tick: rounds since the last tick (and whether the true lead sat in the cone), mode entries.
func _observe(v: SimView, i: int, me: int, it: int) -> void:
	var n: int = _ammo[i] - v.ammo(me)
	_ammo[i] = v.ammo(me)
	var p: Vector3 = v.pos(me)
	var pt: Vector3 = v.pos(it)
	var nose: Vector3 = -v.basis(me).z
	if n > 0:
		fired[i] += n
		var lead: Vector3 = AimSolver.lead_point(p, v.vel(me), pt, v.vel(it), _prm.slug_speed)
		if AimSolver.in_fire_cone(nose, (lead - p).normalized(), _prm.fire_cone_k, v.radius(it), p.distance_to(pt)):
			fired_in_cone[i] += n
	var tag: int = v.ai_tag(me)
	if tag == AiTag.Tag.ENGAGE:
		engage_ticks[i] += 1
	if tag == AiTag.Tag.EXTEND and _tag[i] != AiTag.Tag.EXTEND:
		extends_n[i] += 1
		if (pt - p).dot(nose) > 0.0:
			breakoffs[i] += 1
	_tag[i] = tag
