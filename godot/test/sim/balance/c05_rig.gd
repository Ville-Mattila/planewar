class_name C05Rig extends RefCounted
## GD-26 / C-05 rig (02 s18.3, s4.1 / s9 Lancer vs Autocannon): a team 0 Lancer held `standoff_m` from an Autocannon Turret of
## team FOE (finished, powered, supplied by a Core beside it, driven by the real TowerBrain on the sim's own slew and fire
## gates), level at `REL_M` over it with its nose on the turret, FIRE1 (gun) and FIRE2 (rockets) held. The Lancer is pinned
## in place each tick (a standoff pilot), so the scenario tests the weapons and the turret's reach, not the Lancer brain,
## which closes in for a rocket run (05 s6.3) and is a Dart-class behaviour test, not C-05.

const MAX_S: float = 40.0
const REL_M: float = 100.0
const C0: Vector3 = Vector3(1, 0, 0)
const HZ: int = 30


## Wraps the AiDriver (tower brain) and holds the Lancer's triggers through the same sink.
class Hook extends SimAiHook:
	var inner: AiDriver
	var lancer: int = 0
	var _in: PilotInput = PilotInput.new()

	func on_tick(t: int, v: SimView, sink: CommandSinkBase) -> void:
		inner.on_tick(t, v, sink)
		_in.buttons = PilotInput.FIRE1 | PilotInput.FIRE2
		var _ok: bool = sink.drive(lancer, _in)

	func on_event(ev: SimEvent) -> void:
		inner.on_event(ev)

	func serialize() -> PackedByteArray:
		return inner.serialize()

	func deserialize(bytes: PackedByteArray) -> void:
		inner.deserialize(bytes)


var w: SimWorld
var lancer: int = 0
var turret: int = 0
var kill_tick: int = -1
var min_hp01: float = 1.0
var turret_shots: int = 0              # most turret rounds alive at once (it fired)
var rockets0: int = 0
var rockets_left: int = 0
var _fwd: Vector3 = Vector3.ZERO
var _up: Vector3 = Vector3.ZERO


func build(seed_value: int, standoff_m: float) -> void:
	w = Ai17Kit.world(seed_value)
	var d: AiDriver = Ai17Kit.make_driver(w, true, 3, Ai17Kit.brain())
	var hook: Hook = Hook.new()                                                   # set first: the driver registers SPAWN events
	hook.inner = d
	w.set_ai_hook(hook)
	var _core: int = Ai14Kit.core(w, DartKit.offset(C0, 0.0, -300.0), DartKit.FOE)
	turret = Ai17Kit.tower(w, &"autocannon_turret", DartKit.FOE, C0, DartKit.offset(C0, -3000.0, 0.0))
	var east: float = -sqrt(standoff_m * standoff_m - REL_M * REL_M)
	var p0: Vector3 = Ai17Kit.rel(w, turret, east, 0.0, REL_M)
	var h: Vector3 = DartKit.heading(p0, w.view().pos(turret))
	lancer = DartKit.spawn(w, &"lancer", 0, p0, Vector3.ZERO, h)
	hook.lancer = lancer
	var los: Vector3 = (w.view().pos(turret) - p0).normalized()
	_fwd = los
	_up = (p0.normalized() - los * p0.normalized().dot(los)).normalized()
	rockets0 = w.view().rockets(lancer)


func run() -> void:
	var v: SimView = w.view()
	var p: Vector3 = v.pos(lancer)
	for k: int in int(MAX_S) * HZ:
		IntelKit.teleport(w, lancer, p)
		w.store().fwd[EntityId.slot(lancer)] = _fwd
		w.store().up[EntityId.slot(lancer)] = _up
		var _e: Array[SimEvent] = Ai17Kit.step(w)
		turret_shots = maxi(turret_shots, Ai17Kit.shots_of(w, turret))
		if not v.alive(lancer):
			min_hp01 = 0.0
			break
		min_hp01 = minf(min_hp01, v.hp01(lancer))
		if not v.alive(turret):
			kill_tick = k
			break
	rockets_left = v.rockets(lancer) if v.alive(lancer) else 0
