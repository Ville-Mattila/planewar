class_name LandingScenario extends RefCounted
## Scenario driver for the AI-09 landing scenarios (05 s11.2 SC-02..SC-08): LandingPilot think / act on the 05
## s4.3 schedule (think every `think_period` ticks, staggered by ship index; act every tick) over a LandingWorld.
## Records per ship the RETURN start, the gate tick (first APPROACH), the dock tick, go-arounds with their abort
## reasons, HOLD ticks, the minimum clearance and the minimum distance between ships. Not a contract: the class
## brains (AI-13+) call LandingPilot the same way through AiDriver.

var world: LandingWorld
var st: AiState = AiState.new(512)
var think_period: int = 10
var pilots: Array[LandingPilot] = []
var inputs: Array[PilotInput] = []
var returning: PackedByteArray = PackedByteArray()
var return_tick: PackedInt32Array = PackedInt32Array()
var gate_tick: PackedInt32Array = PackedInt32Array()
var hold_ticks: PackedInt32Array = PackedInt32Array()
var go_arounds: PackedInt32Array = PackedInt32Array()
var abort_log: PackedStringArray = PackedStringArray()   ## "ship tick reason"
var min_sep_m: float = INF
var on_tick: Callable = Callable()                       ## (scenario, tick) -> void, before think / act
var trace: int = -1                                      ## ship index to print every 10 ticks


func _init(t: Terrain, model: StringName = RulesDef.LIFT_SPEED_SCALED) -> void:
	world = LandingWorld.new(t, FlightTestKit.common(), FlightTestKit.rules(model))


## Adds a ship flying from `p` along `heading` (tangent) at `speed`; `rtb` starts RETURN on `pad` now, otherwise the
## pilot's needs_rtb decides at each think.
func add_ship(id_name: StringName, p: Vector3, heading: Vector3, speed: float, pad: int, rtb: bool,
		overrides: Dictionary = {}) -> int:
	var def: ShipDef = FlightTestKit.ship(id_name)
	var n: Vector3 = p.normalized()
	var s: ShipState = FlightTestKit.spawn(def, p, heading, n, heading * speed)
	var id: int = world.add_ship(def, s)
	var pilot: LandingPilot = Ai09Kit.pilot(def, world, overrides)
	pilots.append(pilot)
	inputs.append(PilotInput.new())
	var _r: Array[bool] = [returning.push_back(0), return_tick.push_back(-1), gate_tick.push_back(-1),
		hold_ticks.push_back(0), go_arounds.push_back(0)]
	if rtb:
		start_return(world.ids.size() - 1, pad)
	return id


## Starts RETURN on `pad` for ship index `i` now.
func start_return(i: int, pad: int) -> void:
	pilots[i].begin(world.ids[i], pad, st)
	returning[i] = 1
	return_tick[i] = world.now


## One tick for every flying ship.
func step() -> void:
	if on_tick.is_valid():
		on_tick.call(self, world.now)
	for i: int in world.ids.size():
		if not world.flying(i):
			continue
		var id: int = world.ids[i]
		var think: bool = (world.now + i) % think_period == 0
		if returning[i] == 0:
			if think and pilots[i].needs_rtb(id, world):
				start_return(i, world.nearest_friendly_pad(id))
			else:
				_cruise(i)
				continue
		if think:
			pilots[i].think(id, world, st)
		var before: int = pilots[i].phase(id, st)
		var ph: int = pilots[i].act(id, world, st, inputs[i])
		_record(i, before, ph)
		world.step_ship(i, inputs[i])
	_separation()
	world.end_tick()


# Before RETURN: hold the spawn heading and speed level (a stand-in for the class brain's patrol).
func _cruise(i: int) -> void:
	var s: ShipState = world.ss[i]
	var n: Vector3 = s.p.normalized()
	var h: Vector3 = (s.v - n * s.v.dot(n)).normalized() * world.defs[i].v_cruise
	var p: LandingPilot = pilots[i]
	var _i: Vector2 = FlightController.track_velocity(Ai05Kit.basis(s), s.v, h, n, p.gains, Vector2.ZERO, inputs[i])
	world.step_ship(i, inputs[i])


func _record(i: int, before: int, ph: int) -> void:
	if ph == LandingController.Phase.APPROACH and gate_tick[i] < 0:
		gate_tick[i] = world.now
	if ph == LandingController.Phase.HOLD:
		hold_ticks[i] += 1
	if ph == LandingController.Phase.GO_AROUND and before != LandingController.Phase.GO_AROUND:
		go_arounds[i] += 1
		var _b: bool = abort_log.push_back("%d %d %d" % [i, world.now, st.land_abort[EntityId.slot(world.ids[i])]])
	if i == trace and world.now % 10 == 0:
		var s: ShipState = world.ss[i]
		var pad: int = st.aux_id[EntityId.slot(world.ids[i])]
		var pp: Vector3 = world.pos(pad)
		print("t=%.1f ph=%d d=%.0f h=%.1f agl=%.1f u=%.1f vz=%.1f tilt=%.0f thr=%.2f fuel=%.2f" % [
			float(world.now) / 30.0, ph, s.p.angle_to(pp) * pp.length(), s.p.length() - pp.length(),
			s.p.length() - Sphere.PLANET_RADIUS - world.terrain.height_at(s.p), s.v.length(), s.v.dot(s.p.normalized()),
			rad_to_deg(s.fwd.angle_to(world.basis(pad).y)), inputs[i].thrust, world.fuel01(world.ids[i])])


func _separation() -> void:
	for i: int in world.ids.size():
		for j: int in range(i + 1, world.ids.size()):
			if world.alive(world.ids[i]) and world.alive(world.ids[j]):
				min_sep_m = minf(min_sep_m, world.ss[i].p.distance_to(world.ss[j].p))


## Runs until every ship has docked (or crashed) or `max_ticks`; true when all docked.
func run(max_ticks: int) -> bool:
	for k: int in max_ticks:
		var busy: bool = false
		for i: int in world.ids.size():
			busy = busy or world.flying(i)
		if not busy:
			break
		step()
	for i: int in world.ids.size():
		if world.dock_pad[i] == 0:
			return false
	return true


## Seconds from the gate to the dock of ship `i` (-1 if it did not dock or never reached the gate).
func gate_to_dock_s(i: int) -> float:
	if world.dock_pad[i] == 0 or gate_tick[i] < 0:
		return -1.0
	return float(world.dock_tick[i] - gate_tick[i]) / float(world.rules.tick_hz)


## Ship index `i`'s current landing phase.
func phase(i: int) -> int:
	return pilots[i].phase(world.ids[i], st)
