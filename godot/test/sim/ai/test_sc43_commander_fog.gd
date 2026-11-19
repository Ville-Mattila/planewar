extends GdUnitTestSuite
## SC-43 commander_fog_fairness, re-run with the real Commander (05 s11.2; AI-22's AuditDriver pattern, AI-23): a Brutal
## Commander plays its opening book on cradle slot 0; the enemy base of slot 2 is 90 degrees away and never seen. Every
## command any AI source submits passes an audit sink at the hook boundary; an oracle records, after every tick, every
## enemy entity `visible_to(0)`. Pass: every entity a command names (command target, order target / focus) is own or was
## visible before; the enemy base is never perceived; the bot did build, produce and order.

const HZ: int = Ai23Kit.HZ
const TICKS: int = 300 * HZ


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


func test_sc43_real_commander_never_names_an_entity_it_has_not_seen() -> void:
	var w: SimWorld = Ai23Kit.world(43)
	var d: AuditDriver = AuditDriver.new(Rng.new(3))
	d.set_class_table(AiClassTable.from_content(Ai23Kit.content()))
	var t: Terrain = w.terrain()
	var brains: Array[AiBrain] = [Ai14Kit.dart(t), Ai14Kit.lancer(t), Ai14Kit.bomber(t), Ai14Kit.scout(t)]
	var defs: Array[StringName] = [&"dart", &"lancer", &"bomber", &"scout"]
	for i: int in 4:
		d.set_brain(Ai14Kit.cls(defs[i]), brains[i])
		d.set_overlay_params(Ai14Kit.cls(defs[i]), Ai14Kit.overlays(defs[i]))
	d.set_terrain(t)
	var intel: TeamIntel = TeamIntel.new(IntelKit.tables(), IntelKit.profile("brutal"), HZ)
	intel.track(0, true)
	intel.track(1, true)
	d.set_intel(intel)
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [Ai23Kit.book(&"vanguard_standard")])
	d.set_brain(15, cb, true)
	d.schedule_bot(0, 3)
	w.set_ai_hook(d)
	var ever: Dictionary = {}
	for _t: int in TICKS:
		_oracle(w, ever)
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	var spec: OrderSpec = OrderSpec.new()
	var ids: PackedInt32Array = PackedInt32Array()
	var named: int = 0
	var kinds: Dictionary = {}
	for cmd: Command in d.audit.cmds:
		kinds[cmd.kind] = true
		var refs: PackedInt32Array = PackedInt32Array([cmd.target])
		if cmd.kind == Command.Kind.ORDER and CommandPayload.read_order(cmd, spec, ids):
			refs.append_array(PackedInt32Array([spec.target, spec.focus]))
		for id: int in refs:
			if id == 0 or _own(w, id):
				continue
			named += 1
			assert_bool(ever.has(id)).override_failure_message("command %d names %d, never visible to team 0" % [cmd.kind, id]).is_true()
	assert_bool(kinds.has(Command.Kind.BUILD) and kinds.has(Command.Kind.PRODUCE) and kinds.has(Command.Kind.ORDER)).is_true()
	assert_int(ever.size()).is_equal(0)   # no enemy entity was ever visible: 90 degrees away
	var perc: Perception = d.perception(0)
	assert_int(perc.n_known).is_equal(0)
	assert_int(named).is_equal(0)


# Every non-team-0 entity (ships, ground units, structures) visible to team 0 now.
func _oracle(w: SimWorld, ever: Dictionary) -> void:
	for id: int in w.view().visible_ids(0):
		if w.view().team(id) != 0:
			ever[id] = true


func _own(w: SimWorld, id: int) -> bool:
	return w.view().alive(id) and w.view().team(id) == 0
