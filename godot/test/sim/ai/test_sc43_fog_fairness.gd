extends GdUnitTestSuite
## SC-43 commander_fog_fairness (05 s11.2; AI-22): "Brutal bot; enemy base never seen: no command targets an entity that
## was never visible_to its team". The Commander bot's managers land with AI-23 / AI-27; its information channel is
## this task's: a Brutal-profile `Perception` (team vision, 90 s memory, no delay) and `ThreatMap` of bot slot 2. The
## bot here is a greedy probe on that channel (an ATTACK on every usable contact each 1 Hz think, a MOVE to the
## richest enemy-value cell), plus the Dart brains of its three Darts; every command any AI source submits passes an
## audit sink at the hook boundary. An oracle records, after every tick, every enemy entity `visible_to(0)`. Pass: every
## entity a command names (order target / focus, command target) is own or was visible before; the enemy base 90
## degrees away is never seen, never perceived and adds no enemy value to the map; the probe did order attacks.

const HOME: Vector3 = Vector3(1, 0, 0)
const BOT_SLOT: int = 2
const PROBE_CLASS: int = 15
const TICKS: int = 1800


class AuditSink extends CommandSinkBase:
	var inner: CommandSinkBase = null
	var cmds: Array[Command] = []

	func submit(cmd: Command) -> CommandResult:
		cmds.append(cmd)
		return inner.submit(cmd)

	func drive(id: int, input: PilotInput) -> bool:
		return inner.drive(id, input)

	func set_ai_tag(id: int, tag: int) -> void:
		inner.set_ai_tag(id, tag)

	func end_overlay(id: int) -> void:
		inner.end_overlay(id)

	func pathing() -> Pathing:
		return inner.pathing()


class AuditDriver extends AiDriver:
	var audit: AuditSink = AuditSink.new()

	func on_tick(tick: int, view: SimView, sink: CommandSinkBase) -> void:
		audit.inner = sink
		super.on_tick(tick, view, audit)


## The greedy probe: the Brutal information channel and every contact it offers turned into ATTACK orders.
class FogProbe extends AiBrain:
	var perc: Perception
	var map: ThreatMap
	var thinks: int = 0
	var attacks: int = 0
	var known_ever: Dictionary = {}
	var base_value_seen: float = 0.0
	var base_cell: int = -1

	func think_bot(slot: int, _tier: int, tick: int, view: SimView, sink: CommandSink) -> void:
		thinks += 1
		perc.refresh(view, tick)
		map.update(view, perc, tick)
		base_value_seen = maxf(base_value_seen, map.ch[ThreatMap.ENEMY_VALUE * ThreatMap.CELLS + base_cell])
		var darts: PackedInt32Array = PackedInt32Array()
		for i: int in perc.n_own:
			if perc.own_def[i] == DartKit.def_id(&"dart"):
				var _a: bool = darts.push_back(perc.own_id[i])
		var k: int = 0
		for i: int in perc.n_known:
			var s: int = perc.known[i]
			known_ever[perc.k_id[s]] = true
			if darts.is_empty() or not perc.usable(s, tick):
				continue
			var dart: int = darts[k % darts.size()]
			k += 1
			var _r: CommandResult = sink.submit(Command.order(slot, PackedInt32Array([dart]),
				OrderSpec.make(OrderSpec.Kind.ATTACK, perc.k_id[s])))
			attacks += 1
		var best: int = -1
		for c: int in ThreatMap.CELLS:
			if map.ch[ThreatMap.ENEMY_VALUE * ThreatMap.CELLS + c] > 0.0 and (best < 0 or map.ch[ThreatMap.ENEMY_VALUE * ThreatMap.CELLS + c] > map.ch[ThreatMap.ENEMY_VALUE * ThreatMap.CELLS + best]):
				best = c
		if best >= 0 and not darts.is_empty():
			var _m: CommandResult = sink.submit(Command.order(slot, PackedInt32Array([darts[0]]),
				OrderSpec.make(OrderSpec.Kind.MOVE, 0, map.tables.centre[best] * (Sphere.PLANET_RADIUS + 300.0), OrderSpec.FLAG_QUEUE)))


func test_sc43_commander_fog_fairness() -> void:
	var w: SimWorld = DartKit.world(43)
	var d: AuditDriver = AuditDriver.new(Rng.new(3))
	var c: ContentSet = DartKit.content()
	d.set_class_table(AiClassTable.from_content(c))
	d.set_brain(DartKit.CLS_DART, DartKit.brain(w))
	d.set_overlay_params(DartKit.CLS_DART, OverlayParams.for_ship(DartKit.ap(), DartKit.ship(&"dart"), c.rules, c.rules.tick_hz, c.flight_common))
	d.set_terrain(w.terrain())
	var cruise: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(&"bomber"), w.terrain())
	d.set_brain(DartKit.class_of(&"bomber"), cruise)
	var probe: FogProbe = FogProbe.new()
	probe.perc = Perception.new(0, BOT_SLOT, IntelKit.profile("brutal"), IntelKit.tables())
	probe.map = ThreatMap.new(IntelKit.tables())
	d.set_brain(PROBE_CLASS, probe, true)
	d.schedule_bot(BOT_SLOT, 3)
	w.set_ai_hook(d)
	# own base and three Darts (bot slot 2)
	var _core: int = IntelKit.spawn(w, &"core", BOT_SLOT, 0, IntelKit.at(w, HOME, 0.0, 0.0))
	var _ref: int = IntelKit.spawn(w, &"refinery", BOT_SLOT, 0, IntelKit.at(w, HOME, 400.0, 0.0))
	for k: int in 3:
		var _dart: int = IntelKit.spawn(w, &"dart", BOT_SLOT, 0, IntelKit.at(w, HOME, -300.0 + 300.0 * float(k), 200.0, 300.0))
	# the enemy base, 90 degrees away (never in range or above the horizon)
	var far: Vector3 = DartKit.geo(0.0, 90.0)
	var base: PackedInt32Array = PackedInt32Array()
	for def: StringName in [&"core", &"autocannon_turret", &"flak_battery", &"refinery"]:
		var _b: bool = base.push_back(IntelKit.spawn(w, def, 1, 1, IntelKit.at(w, far, 300.0 * float(base.size()), 0.0)))
	probe.base_cell = IntelKit.cell(DartKit.above(w, far, 0.0))
	# an enemy Bomber crossing 1.2 km north of home, east to west (seen, then a ghost)
	var pb: Vector3 = IntelKit.at(w, HOME, 5000.0, 1200.0, 400.0)
	var hb: Vector3 = DartKit.heading(pb, IntelKit.at(w, HOME, -5000.0, 1200.0, 400.0))
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, pb, hb * 70.0, hb)
	cruise.heading[bomber] = hb
	var ever: Dictionary = {}
	for _t: int in TICKS:
		_oracle(w, ever)
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	# the audit
	var spec: OrderSpec = OrderSpec.new()
	var ids: PackedInt32Array = PackedInt32Array()
	var named: int = 0
	for cmd: Command in d.audit.cmds:
		var refs: PackedInt32Array = PackedInt32Array([cmd.target])
		if cmd.kind == Command.Kind.ORDER and CommandPayload.read_order(cmd, spec, ids):
			refs.append_array(PackedInt32Array([spec.target, spec.focus]))
		for id: int in refs:
			if id == 0 or _own(w, id):
				continue
			named += 1
			assert_bool(ever.has(id)).override_failure_message("command %d names %d, never visible to team 0" % [cmd.kind, id]).is_true()
	for id: Variant in probe.known_ever.keys():
		assert_bool(ever.has(id)).is_true()
	for id: int in base:
		assert_bool(ever.has(id)).override_failure_message("setup: the enemy base must stay unseen").is_false()
		assert_bool(probe.known_ever.has(id)).is_false()
	assert_float(probe.base_value_seen).is_equal(0.0)
	assert_int(probe.thinks).is_greater_equal(55)
	assert_int(probe.attacks).is_greater(0)
	assert_int(named).is_greater(0)
	assert_bool(ever.has(bomber)).is_true()


# Every non-team-0 ship / structure visible to team 0 now.
func _oracle(w: SimWorld, ever: Dictionary) -> void:
	var v: SimView = w.view()
	for list: PackedInt32Array in [v.ships(), v.structures()]:
		for id: int in list:
			if v.team(id) != 0 and v.visible_to(0, id):
				ever[id] = true


func _own(w: SimWorld, id: int) -> bool:
	return w.view().alive(id) and w.view().team(id) == 0
