extends GdUnitTestSuite
## S14 (TA-18): the ordinals in sim/MODULE.md "Enumerations" (R0 B.3, append-only) equal the GDScript enums, for
## every enumeration the sim defines so far. The bullet format "label ...: 0 NAME, 1 NAME" is part of the contract
## (R0 B.9 A-21); pairs are read in sequence, so prose numbers inside a bullet are ignored.

const SIM_MODULE: String = "res://src/sim/MODULE.md"


func _section() -> String:
	var text: String = FileAccess.get_file_as_string(SIM_MODULE)
	var a: int = text.find("## Enumerations")
	var b: int = text.find("\n## ", a + 4)
	assert_int(a).is_greater(0)
	return text.substr(a, b - a)


## Names by ordinal after the first occurrence of `label`, stopping at the next enumeration's 0.
func _doc_names(label: String) -> PackedStringArray:
	var sec: String = _section()
	var at: int = sec.find(label)
	assert_int(at).is_greater_equal(0)
	var line_end: int = sec.find("\n", at)
	var body: String = sec.substr(at + label.length(), (line_end if line_end > 0 else sec.length()) - at - label.length())
	var re: RegEx = RegEx.create_from_string("(\\d+) ([A-Z][A-Z0-9_]*)")
	var out: PackedStringArray = PackedStringArray()
	for m: RegExMatch in re.search_all(body):
		var n: int = int(m.get_string(1))
		if n == out.size():
			out.push_back(m.get_string(2))
		elif n == 0 and out.size() > 0:
			break
	return out


func _check(label: String, enum_dict: Dictionary) -> void:
	var doc: PackedStringArray = _doc_names(label)
	assert_int(doc.size()).is_equal(enum_dict.size())
	for i: int in doc.size():
		assert_int(int(enum_dict.get(doc[i], -1))).override_failure_message("%s %s" % [label, doc[i]]).is_equal(i)


func _consts(prefix: String, names: PackedStringArray) -> Dictionary:
	var d: Dictionary = {}
	var cmap: Dictionary = (load("res://src/sim/world/command_applier.gd") as Script).get_script_constant_map()
	for n: String in names:
		d[n] = cmap[prefix + n]
	return d


func test_sim_event_kind() -> void:
	_check("`SimEvent.Kind` (", SimEvent.Kind)


func test_command_kind() -> void:
	_check("`Command.Kind` (", Command.Kind)


func test_order_spec_kind() -> void:
	_check("`OrderSpec.Kind` (", OrderSpec.Kind)


func test_alert_kind() -> void:
	_check("`AlertKind` (", AlertKind.Kind)


func test_command_result_code() -> void:
	_check("`CommandResult.Code`:", CommandResult.Code)


func test_phase_arc_player_kind() -> void:
	_check("`MatchRules.Phase`:", MatchRules.Phase)
	_check("`MatchArc`:", MatchArc.Arc)
	_check("`PlayerKind`:", {"HUMAN": PlayerTable.KIND_HUMAN, "BOT": PlayerTable.KIND_BOT, "OPEN": PlayerTable.KIND_OPEN})


func test_control_state_overlay_release_reason_mirrors() -> void:
	_check("Control state (", _consts("CS_", _doc_names("Control state (")))
	_check("AI overlay (", _consts("OV_", _doc_names("AI overlay (")))
	_check("`ReleaseReason`:", _consts("RR_", _doc_names("`ReleaseReason`:")))
	assert_int(_doc_names("`ReleaseReason`:").size()).is_equal(8)
