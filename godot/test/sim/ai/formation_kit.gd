class_name FormationKit extends RefCounted
## AI-11 fixtures: the shipped defs through WorldTestKit, FormationParams from `ai11_params.json` + the shipped
## `wing.json`, a SimWorld with a driver, and two test brains: Darts on EscortPilot (class 0) and a Bomber leader flown
## toward a point with FlightController (class 1). Flat datum (the scenario map recipe is tiny_test, not built yet).

const PARAMS: String = "res://test/sim/ai/ai11_params.json"
const CLS_ESCORT: int = 0
const CLS_LEADER: int = 1


static func block(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS))
	assert(parsed is Dictionary, "missing " + PARAMS)
	return (parsed as Dictionary)[name] as Dictionary


static func content() -> ContentSet:
	return WorldTestKit.content()


static var _ring2: float = -1.0


## `Spatial.ring2_m` of the collision hash (the neighbour query's ring path limit).
static func ring2_m() -> float:
	if _ring2 < 0.0:
		_ring2 = Spatial.new(EntityStore.new(), ProjectileStore.new(16)).ring2_m
	return _ring2


## OrderRulesDef keeps its fields in `raw` until sim_ai names them.
static func engage_m() -> float:
	var e: float = content().order_rules.raw["escort_engage_radius_m"]
	return e


static func params() -> FormationParams:
	var c: ContentSet = content()
	var p: FormationParams = FormationParams.from_dict(block("separation"), block("formation"), c.wing, c.rules.ceiling_soft_m, engage_m(), ring2_m())
	assert(p != null, "ai11_params.json must build FormationParams")
	return p


static func ship(id: StringName) -> ShipDef:
	for sd: ShipDef in content().ships:
		if sd.id == id:
			return sd
	return null


static func gains(id: StringName) -> FlightGains:
	return Ai05Kit.gains(ship(id), content().rules)


static func pilot(id: StringName = &"dart", prm: FormationParams = null) -> EscortPilot:
	return EscortPilot.new(ship(id), prm if prm != null else params(), gains(id))


## A SimWorld with an AiDriver hooked in; `bomber` leader brain on class 1, escort brain on class 0.
static func driver(w: SimWorld, escort: EscortTestBrain, leader: LeaderTestBrain) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(3))
	d.set_brain(CLS_ESCORT, escort)
	d.set_brain(CLS_LEADER, leader)
	w.set_ai_hook(d)
	return d


## Gives each of `ids` a standing ESCORT order on `leader`. The ORDER wire payload carries no escort_slot / escort_mode /
## focus yet (needs sim, 04 s2.5), so the order goes straight into the world's OrderQueue; `issue_tick` is the current tick.
static func escort_order(w: SimWorld, ids: PackedInt32Array, leader: int, slot: int = -1, mode: int = 0, focus: int = 0) -> void:
	var q: OrderQueue = w.get("_orders")
	for id: int in ids:
		var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.ESCORT, leader)
		spec.escort_slot = slot
		spec.escort_mode = mode as OrderSpec.EscortMode
		spec.focus = focus
		spec.issuer = 0
		spec.issue_tick = w.tick()
		var res: int = q.push(EntityId.slot(id), OrderQueue.STANDING, spec)
		assert(res == OrderQueue.Push.OK, "ESCORT order refused: %d" % res)


## A class-slot ESCORT through the command path (the wire payload carries the target only).
static func escort_command(w: SimWorld, ids: PackedInt32Array, leader: int) -> void:
	var res: CommandResult = w.apply_command(Command.order(0, ids, OrderSpec.make(OrderSpec.Kind.ESCORT, leader)))
	assert(res.code == CommandResult.Code.ACCEPTED, "ESCORT order refused: %d" % res.code)


static func move_order(w: SimWorld, id: int, to: Vector3) -> void:
	var res: CommandResult = w.apply_command(Command.order(0, PackedInt32Array([id]), OrderSpec.make(OrderSpec.Kind.MOVE, 0, to)))
	assert(res.code == CommandResult.Code.ACCEPTED, "MOVE order refused: %d" % res.code)


## Escort-class brain: EscortPilot think each slice, act each tick.
class EscortTestBrain extends AiBrain:
	var pilot: EscortPilot
	var inp: PilotInput = PilotInput.new()
	var lost: int = 0
	var thinks: int = 0       ## FORMING thinks
	var refreshes: int = 0    ## of those, the ones that refreshed the separation term (Separation.term)

	func _init(p: EscortPilot) -> void:
		pilot = p

	func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, _sink: CommandSink, tick: int) -> void:
		for i: int in n:
			var o: EscortPilot.Outcome = pilot.think(ids[i], view, st, tick)
			if o == EscortPilot.Outcome.LOST:
				lost += 1
			elif o == EscortPilot.Outcome.FORMING:
				thinks += 1
				refreshes += st.sep_age[EntityId.slot(ids[i])] & Separation.AGE_FRESH

	func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void:
		for id: int in ids:
			if pilot.act(id, view, st, inp):
				var _ok: bool = sink.drive(id, inp)


## Leader brain: level flight toward `goal` at `speed` and `alt_cmd` above the datum; `arrived` within `arrive_m`.
class LeaderTestBrain extends AiBrain:
	var gains: FlightGains
	var goal: Vector3 = Vector3.ZERO
	var speed: float = 70.0
	var alt_cmd: float = 300.0
	var arrive_m: float = 100.0
	var arrived: bool = false
	var inp: PilotInput = PilotInput.new()

	func _init(g: FlightGains) -> void:
		gains = g

	func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void:
		for id: int in ids:
			var p: Vector3 = view.pos(id)
			var up: Vector3 = p.normalized()
			var to: Vector3 = goal - p
			arrived = arrived or to.length() < arrive_m
			var tang: Vector3 = (to - up * to.dot(up)).normalized()
			var vz: float = clampf(0.5 * (alt_cmd - (p.length() - Sphere.PLANET_RADIUS)), -10.0, 10.0)
			var s: int = EntityId.slot(id)
			st.integ[s] = FlightController.track_velocity(view.basis(id), view.vel(id), tang * speed + up * vz, up, gains,
				st.integ[s], inp)
			var _ok: bool = sink.drive(id, inp)
