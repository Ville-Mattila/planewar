class_name ScenarioRunner extends RefCounted
## Scenario interpreter (TA-33, 03 TA-33, 01 ADR-11): runs one scenario dictionary (godot/test/sim/scenarios/*.json,
## schema tools/schemas/sim_scenario.schema.json, format in godot/test/sim/README.md) through SimWorld.step() and
## returns the list of mismatches (empty = the scenario holds). Scripted commands at tick t are queued before step t,
## checks at t run after step t. Test layer only: it reuses the shared fixtures (WorldTestKit, EconomyTestKit,
## CombatTestKit, FireTestKit) and reads the sim through its public accessors.

const _BUTTONS: Dictionary = {
	"BOOST": PilotInput.BOOST, "BRAKE": PilotInput.BRAKE, "FLIP": PilotInput.FLIP, "FIRE1": PilotInput.FIRE1,
	"FIRE2": PilotInput.FIRE2, "DOCK": PilotInput.DOCK, "RELEASE": PilotInput.RELEASE,
}

var _w: SimWorld = null
var _names: Dictionary = {}                 ## entity name -> EntityId
var _pending: PackedStringArray = PackedStringArray()   ## names awaiting their SPAWN event, in command order
var _pins: Dictionary = {}                  ## entity name -> Vector3 held every tick
var _hook: FireTestKit.TriggerHook = null
var _counts: Dictionary = {}                ## SimEvent.Kind -> events seen
var _recorded: Array[SimEvent] = []
var _fail: PackedStringArray = PackedStringArray()


## Runs `sc`; returns the failures. A `planned` scenario is not run (returns empty).
func run(sc: Dictionary) -> PackedStringArray:
	_fail = PackedStringArray()
	if str(sc.get("status", "active")) == "planned":
		return _fail
	_build_world(sc.get("world", {}))
	_bind(sc.get("bind_structures", []))
	var filter: Array = sc.get("event_filter", [])
	for t: int in range(1, int(sc.get("ticks", 1)) + 1):
		for step: Dictionary in sc.get("script", []):
			if int(step["at"]) == t:
				_do(step, t)
		for pin: String in _pins:
			if _names.has(pin):
				var s: int = EntityId.slot(int(_names[pin]))
				_w.store().pos[s] = _pins[pin]
				_w.store().vel[s] = Vector3.ZERO
		_w.step()
		for e: SimEvent in _w.drain_events():
			_see(e, filter)
		for c: Dictionary in sc.get("checks", []):
			if int(c["at"]) == t:
				_check(c, t)
	_compare_events(sc.get("events", []))
	return _fail


func _build_world(cfg: Dictionary) -> void:
	var seed_value: int = int(cfg.get("seed", 7))
	var rules: MatchRules = WorldTestKit.rules(float(cfg.get("core_exposure_s", -1.0)), float(cfg.get("hard_end_s", -1.0)))
	if cfg.has("unit_cap"):
		rules.caps.units = int(cfg["unit_cap"])
	match str(cfg.get("kind", "standard")):
		"solo_kit":
			_w = EconomyTestKit.solo_world(true, seed_value, rules)
		"combat":
			_w = CombatTestKit.world(seed_value, rules)
		_:
			_w = WorldTestKit.world(seed_value, rules)


func _bind(list: Array) -> void:
	for b: Dictionary in list:
		var s: int = EconomyTestKit.find(_w, StringName(b["def"]), int(b["owner"]))
		if s < 0:
			_fail.append("bind_structures: no %s owned by %d" % [b["def"], int(b["owner"])])
		else:
			_names[str(b["as"])] = _w.store().id_of(s)


func _see(e: SimEvent, filter: Array) -> void:
	_counts[e.kind] = int(_counts.get(e.kind, 0)) + 1
	if e.kind == SimEvent.Kind.SPAWN and _pending.size() > 0:
		_names[_pending[0]] = e.a
		_pending.remove_at(0)
	if filter.has(SimEvent.Kind.keys()[e.kind]):
		_recorded.append(e)


# --- script ------------------------------------------------------------------------------------------------------

func _do(st: Dictionary, t: int) -> void:
	var cmd: Command = null
	var player: int = int(st.get("player", 0))
	match str(st["do"]):
		"spawn":
			cmd = CommandPayload.debug_spawn(0, WorldTestKit.def_id(StringName(st["def"])), int(st["owner"]), int(st["team"]),
					FireTestKit.at(float(st.get("alt", 0.0)), float(st.get("east", 0.0)), float(st.get("north", 0.0))),
					Vector3.ZERO, Vector3(0, 1, 0))
			var nm: String = str(st.get("as", "spawn@%d_%d" % [t, _pending.size()]))
			_pending.append(nm)
			if bool(st.get("pin", false)):
				_pins[nm] = FireTestKit.at(float(st.get("alt", 0.0)), float(st.get("east", 0.0)), float(st.get("north", 0.0)))
		"possess":
			cmd = Command.possess(player, _id(st["entity"]))
		"release":
			cmd = Command.release(player)
		"build":
			cmd = Command.build(player, WorldTestKit.def_id(StringName(st["def"])), EconomyTestKit.cell_west(float(st["west_m"])),
					int(st.get("rotation", 0)))
		"produce":
			cmd = Command.produce(player, _id(st["factory"]), WorldTestKit.def_id(StringName(st["def"])), int(st.get("count", 1)))
		"kill":
			cmd = CommandPayload.debug_set(player, _id(st["entity"]), CommandPayload.SET_KILL, 0.0)
		"remove_player":
			_w.remove_player(int(st["slot"]))
			return
		"hold":
			if _hook == null:
				_hook = FireTestKit.hook(_w)
			var mask: int = 0
			for b: String in st.get("buttons", []):
				mask |= int(_BUTTONS[b])
			_hook.hold(_id(st["entity"]), mask)
			return
		var other:
			_fail.append("t%d: unknown action '%s'" % [t, other])
			return
	var res: CommandResult = _w.apply_command(cmd)
	var want: String = str(st.get("expect", "ACCEPTED"))
	if not CommandResult.Code.has(want):
		_fail.append("t%d %s: unknown result code '%s'" % [t, st["do"], want])
	elif res.code != CommandResult.Code[want]:
		_fail.append("t%d %s: result %s, expected %s" % [t, st["do"], CommandResult.Code.keys()[res.code], want])
	elif st.has("expect_reject"):
		var rj: String = str(st["expect_reject"])
		if not Build.Reject.has(rj) or res.reject != Build.Reject[rj]:
			_fail.append("t%d %s: reject %s, expected %s" % [t, st["do"], str(res.reject), rj])


func _id(ref: Variant) -> int:
	if ref is String:
		if not _names.has(ref):
			_fail.append("unknown entity name '%s'" % ref)
			return 0
		return int(_names[ref])
	return int(ref)


# --- expectations ------------------------------------------------------------------------------------------------

func _compare_events(expected: Array) -> void:
	var got: Array[String] = []
	for e: SimEvent in _recorded:
		got.append(_fmt(e))
	var want: Array[String] = []
	for x: Dictionary in expected:
		want.append("t%d %s%s%s%s" % [int(x["tick"]), x["kind"], _opt(x, "a"), _opt(x, "b"), _opt(x, "reason")])
	var n: int = maxi(got.size(), want.size())
	for i: int in n:
		if i >= got.size():
			_fail.append("event %d: missing %s" % [i, want[i]])
		elif i >= want.size():
			_fail.append("event %d: unexpected %s" % [i, got[i]])
		elif not _event_matches(_recorded[i], expected[i]):
			_fail.append("event %d: got %s, expected %s" % [i, got[i], want[i]])


func _opt(x: Dictionary, key: String) -> String:
	return " %s=%s" % [key, str(x[key])] if x.has(key) else ""


func _fmt(e: SimEvent) -> String:
	var s: String = "t%d %s a=%d b=%d" % [e.tick, SimEvent.Kind.keys()[e.kind], e.a, e.b]
	if e.extra.size() > 0:
		s += " reason=%d" % e.extra[0]
	return s


func _event_matches(e: SimEvent, x: Dictionary) -> bool:
	if e.tick != int(x["tick"]) or SimEvent.Kind.keys()[e.kind] != str(x["kind"]):
		return false
	if x.has("a") and e.a != _id(x["a"]):
		return false
	if x.has("b") and e.b != _id(x["b"]):
		return false
	if x.has("reason"):
		var key: String = str(x["reason"])
		if not ControlMachine.ReleaseReason.has(key) or e.extra.size() == 0 or e.extra[0] != ControlMachine.ReleaseReason[key]:
			return false
	return true


func _check(c: Dictionary, t: int) -> void:
	var got: float = _query(c, t)
	var want: float = float(_value(c["value"]))
	var tol: float = float(c.get("tol", 0.001))
	var ok: bool = false
	match str(c.get("op", "eq")):
		"eq":
			ok = is_equal_approx(got, want)
		"ge":
			ok = got >= want
		"le":
			ok = got <= want
		"gt":
			ok = got > want
		"lt":
			ok = got < want
		"approx":
			ok = absf(got - want) <= tol
	if not ok:
		_fail.append("t%d %s %s: got %s, expected %s %s" % [t, c["query"], str(c.get("entity", c.get("team", c.get("def", "")))),
				str(got), str(c.get("op", "eq")), str(want)])


func _value(v: Variant) -> Variant:
	if v is bool:
		return 1.0 if v else 0.0
	return v


func _query(c: Dictionary, t: int) -> float:
	var v: SimView = _w.view()
	match str(c["query"]):
		"possessor":
			return float(v.possessor(_id(c["entity"])))
		"alive":
			return 1.0 if _w.store().alive(_id(c["entity"])) else 0.0
		"hp01":
			return v.hp01(_id(c["entity"]))
		"ore":
			return float(_w.economy().economy.stockpile(int(c.get("team", 0))).x)
		"queue_size":
			return float(v.production_queue(_id(c["entity"])).size())
		"ship_count":
			return float(_w.store().ships.size())
		"structure_count":
			return float(_structures(StringName(c["def"]), int(c.get("owner", -1))))
		"event_count":
			var k: String = str(c["kind"])
			return float(int(_counts.get(SimEvent.Kind[k], 0))) if SimEvent.Kind.has(k) else -1.0
	_fail.append("t%d: unknown query '%s'" % [t, c["query"]])
	return -1.0


func _structures(def: StringName, owner: int) -> int:
	var d: int = WorldTestKit.def_id(def)
	var n: int = 0
	for s: int in _w.store().structures:
		if _w.store().def_id[s] == d and (owner < 0 or _w.store().owner[s] == owner):
			n += 1
	return n
