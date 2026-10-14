class_name ControlTestKit extends RefCounted
## Fixtures for the ControlMachine tests (AI-02): WorldTestKit's world (0 human team 0, 1 human team 1, 2 bot
## team 0) plus slot 3, a second human on team 0, so hand-over runs between two humans; helpers that queue a
## command, step once and return that step's events.

const MATE: int = 3


static func world(seed_value: int = 7, r: MatchRules = null) -> SimWorld:
	var w: SimWorld = WorldTestKit.world(seed_value, r)
	w.add_player(MATE, 0, &"", PlayerTable.KIND_HUMAN)
	return w


static func dart(w: SimWorld, owner: int = 0, team: int = 0, alt: float = 500.0, east: float = 0.0) -> int:
	return WorldTestKit.spawn(w, &"dart", owner, team, WorldTestKit.at(alt, east))


## Submits `cmd`, asserts its code, steps once and returns the events of that step.
static func run(w: SimWorld, cmd: Command, code: int = CommandResult.Code.ACCEPTED) -> Array[SimEvent]:
	var got: int = w.apply_command(cmd).code
	assert(got == code, "command %d: code %d, wanted %d" % [cmd.kind, got, code])
	return step(w)


static func step(w: SimWorld, n: int = 1) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for _i: int in n:
		w.step()
		out.append_array(w.drain_events())
	return out


static func code(w: SimWorld, cmd: Command) -> int:
	return w.apply_command(cmd).code


static func control(w: SimWorld) -> ControlMachine:
	return w._control


static func inputs(w: SimWorld) -> InputSlots:
	return w._inputs


static func order(p: int, id: int, kind: OrderSpec.Kind, target: int = 0, flags: int = 0) -> Command:
	var pt: Vector3 = WorldTestKit.at(800.0, 900.0) if kind == OrderSpec.Kind.MOVE else Vector3.ZERO
	return Command.order(p, PackedInt32Array([id]), OrderSpec.make(kind, target, pt, flags))


static func request(p: int, id: int) -> Command:
	return CommandPayload.simple(p, Command.Kind.REQUEST_POSSESS, id)


static func pilot(w: SimWorld, p: int, thrust: float, pitch: float, buttons: int = 0) -> int:
	var inp: PilotInput = PilotInput.new()
	inp.thrust = thrust
	inp.pitch = pitch
	inp.yaw = pitch
	inp.roll = -pitch
	inp.buttons = buttons
	return w.apply_command(Command.pilot(p, w.tick() + 1, inp)).code


static func of_kind(events: Array[SimEvent], kind: SimEvent.Kind) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.kind == kind:
			out.append(e)
	return out


static func state(w: SimWorld, id: int) -> int:
	return w.view().control_state(id)


static func overlay(w: SimWorld, id: int) -> int:
	return w.store().overlay[EntityId.slot(id)]


static func standing(w: SimWorld, id: int) -> int:
	return w._orders.count(EntityId.slot(id), OrderQueue.STANDING)


static func pending(w: SimWorld, id: int) -> int:
	return w._orders.count(EntityId.slot(id), OrderQueue.PENDING)
