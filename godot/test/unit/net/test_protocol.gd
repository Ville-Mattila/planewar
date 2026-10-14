extends GdUnitTestSuite
## NET-01: net/protocol.gd against its sources. The catalogue and channel tables are parsed from
## docs/04 s2.1/s2.3 and the enumerations from sim/MODULE.md and R0 B.3, so a doc edit that is not
## mirrored in protocol.gd (or the reverse) fails here.

const DOC_04: String = "../docs/04-networking-and-backend.md"
const DOC_R0: String = "../docs/reviews/R0-resolution-register.md"
const SIM_MODULE: String = "res://src/sim/MODULE.md"


func _read(path: String) -> String:
	var abs_path: String = path if path.begins_with("res://") else \
			ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	assert_object(f).override_failure_message("cannot open " + abs_path).is_not_null()
	return "" if f == null else f.get_as_text()


## Section of a markdown text from the line starting with `heading` to the next heading of the same level.
func _section(text: String, heading: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var level: String = heading.substr(0, heading.find(" ") + 1)
	var inside: bool = false
	for line: String in text.split("\n"):
		if line.begins_with(heading):
			inside = true
			continue
		if inside and line.begins_with(level):
			break
		if inside:
			var _a: bool = out.push_back(line)
	return out


## Ordinal list "0 A, 1 B, ..." that follows the first occurrence of `label`; stops when the
## ordinal sequence breaks (the next enum on the same line starts again at 0).
func _ordinals(text: String, label: String) -> PackedStringArray:
	var at: int = text.find(label)
	assert_int(at).override_failure_message("label not found: " + label).is_greater_equal(0)
	var names: PackedStringArray = PackedStringArray()
	if at < 0:
		return names
	var line_end: int = text.find("\n", at)
	var rest: String = text.substr(at + label.length(), (line_end if line_end >= 0 else text.length()) - at - label.length())
	var re: RegEx = RegEx.create_from_string("\\b(\\d+) ([A-Z][A-Z0-9_]+)\\b")
	for m: RegExMatch in re.search_all(rest):
		if int(m.get_string(1)) != names.size():
			break
		var _a: bool = names.push_back(m.get_string(2))
	return names


func _assert_enum(enum_dict: Dictionary, expected: PackedStringArray, what: String) -> void:
	assert_int(expected.size()).override_failure_message(what + ": no ordinals parsed").is_greater(0)
	assert_int(enum_dict.size()).override_failure_message(what + " size").is_equal(expected.size())
	for i: int in expected.size():
		var key: String = expected[i]
		assert_bool(enum_dict.has(key)).override_failure_message(what + " lacks " + key).is_true()
		if enum_dict.has(key):
			assert_int(int(enum_dict[key])).override_failure_message(what + "." + key).is_equal(i)


func _doc_catalogue() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in _section(_read(DOC_04), "### 2.3 "):
		if line.begins_with("| 0x"):
			var cols: PackedStringArray = line.split("|")
			var row: PackedStringArray = PackedStringArray()
			for c: String in cols:
				var _a: bool = row.push_back(c.strip_edges())
			rows.append(row)                                  # ["", id, name, ch, fields, max, rate, ""]
	return rows


func _leading_int(s: String) -> int:
	var re: RegEx = RegEx.create_from_string("^[0-9,]+")
	var m: RegExMatch = re.search(s)
	return -1 if m == null else int(m.get_string().replace(",", ""))


# --- version, ids, channels, sizes ---------------------------------------------------------------

func test_protocol_version_is_1() -> void:
	assert_int(Protocol.PROTOCOL_VERSION).is_equal(1)


func test_every_s2_3_id_is_defined_once() -> void:
	var rows: Array[PackedStringArray] = _doc_catalogue()
	assert_int(rows.size()).is_equal(33)
	assert_int(Protocol.message_count()).is_equal(rows.size())
	assert_int(Protocol.NAMES.size()).is_equal(rows.size())
	var consts: Dictionary = (load("res://src/net/protocol.gd") as Script).get_script_constant_map()
	var seen: Dictionary[int, bool] = {}
	for r: int in Protocol.message_count():
		var id: int = Protocol.CATALOGUE[r * Protocol.CATALOGUE_STRIDE]
		assert_bool(seen.has(id)).override_failure_message("duplicate id %d" % id).is_false()
		seen[id] = true
		assert_int(Protocol.row_of(id)).is_equal(r)
	for row: PackedStringArray in rows:
		var id: int = row[1].hex_to_int()
		var name: String = row[2]
		assert_bool(consts.has(name)).override_failure_message("no constant " + name).is_true()
		assert_int(int(consts.get(name, -1))).override_failure_message(name).is_equal(id)
		assert_str(Protocol.name_of(id)).is_equal(name)
		assert_int(Protocol.NAMES.count(name)).is_equal(1)
		assert_bool(Protocol.is_client_to_server(id)).is_equal(id < 0x80)
	assert_int(Protocol.DOCTRINE_PICK).is_equal(0x0D)
	assert_int(Protocol.TEAM_DETAIL).is_equal(0x92)
	assert_int(Protocol.LOBBY_STATE).is_equal(0x93)


func test_catalogue_channel_and_max_match_s2_3() -> void:
	for row: PackedStringArray in _doc_catalogue():
		var id: int = row[1].hex_to_int()
		assert_int(Protocol.channel_of(id)).override_failure_message(row[2] + " channel").is_equal(int(row[3]))
		var doc_max: int = _leading_int(row[5])
		assert_int(Protocol.max_bytes(id)).override_failure_message(row[2] + " max").is_equal(doc_max)
	# R0 B.9 A-26: CHAT_RELAY is 222 (8 + 1 + 1 + 4 + 202 + 4 + 1 + 1), in the doc and in the catalogue.
	assert_int(Protocol.max_bytes(Protocol.CHAT_RELAY)).is_equal(222)


func test_channel_allowed_sets_match_s2_1() -> void:
	var parsed: int = 0
	for line: String in _section(_read(DOC_04), "### 2.1 "):
		var m: RegExMatch = RegEx.create_from_string("^\\| ([0-3]) \\| \\w+ \\|.*\\| ([A-Z_, ]+) \\|$").search(line)
		if m == null:
			continue
		parsed += 1
		var ch: int = int(m.get_string(1))
		var doc_names: PackedStringArray = PackedStringArray()
		for n: String in m.get_string(2).split(","):
			var _a: bool = doc_names.push_back(n.strip_edges())
		var mine: PackedStringArray = PackedStringArray()
		for r: int in Protocol.message_count():
			var id: int = Protocol.CATALOGUE[r * Protocol.CATALOGUE_STRIDE]
			if Protocol.channel_of(id) == ch:
				var _b: bool = mine.push_back(Protocol.NAMES[r])
			assert_bool(Protocol.channel_allows(ch, id)).is_equal(Protocol.channel_of(id) == ch)
		doc_names.sort()
		mine.sort()
		assert_array(Array(mine)).override_failure_message("channel %d set" % ch).is_equal(Array(doc_names))
	assert_int(parsed).is_equal(Protocol.CHANNEL_COUNT)
	assert_array(Array(Protocol.CHANNEL_MODE)).is_equal([Protocol.ChannelMode.RELIABLE_ORDERED,
		Protocol.ChannelMode.UNRELIABLE, Protocol.ChannelMode.UNRELIABLE_SEQUENCED, Protocol.ChannelMode.RELIABLE_ORDERED])


## Worst-case sums of the 04 s2.3 field lists (type sizes per the s2.3 legend). "==" rows are fixed layouts.
func test_catalogue_sizes_cover_field_layouts() -> void:
	var exact: Dictionary[int, int] = {
		Protocol.LOADED: 1 + 32, Protocol.COMMAND: 1 + 2 + 4 + 1 + 4 + 2 + 256,
		Protocol.INPUT: 1 + 2 + 4 + 4 + 1 + 3 * 8, Protocol.SNAPSHOT_ACK: 1 + 4 + 2, Protocol.PING: 1 + 4,
		Protocol.QUICK_PING: 1 + 1 + 8 + 4, Protocol.INTEREST_HINT: 1 + 1 + 2 + 2 + 2, Protocol.LEAVE: 2,
		Protocol.REQUEST_KEYFRAME: 2, Protocol.SPECTATE_FOLLOW: 1 + 4, Protocol.DOCTRINE_PICK: 1 + 1 + 1,
		Protocol.REFUSE: 1 + 1 + 2 + 1 + 120, Protocol.MATCH_STATE: 1 + 1 + 4 + 2 + 1,
		Protocol.COMMAND_RESULT: 1 + 2 + 1 + 1,
		Protocol.POSSESS_ACK: 1 + 4 + 2 + 4 + 12 + 12 + 16 + 2 + 2 + 1 + 1 + 2 + 1,
		Protocol.RELEASED: 1 + 4 + 2 + 4 + 1 + 1, Protocol.PONG: 1 + 4 + 4 + 4,
		Protocol.CHAT_RELAY: 1 + 8 + 1 + 1 + 4 + 2 + 200 + 4 + 1, Protocol.PLAYER_STATUS: 1 + 1 + 1 + 2 + 1,
	}
	for id: int in exact:
		assert_int(Protocol.max_bytes(id)).override_failure_message(Protocol.name_of(id)).is_equal(exact[id])
	var at_most: Dictionary[int, int] = {
		Protocol.HELLO: 1 + 2 + 32 + 1 + 160 + 4 + 1 + 1 + 1 + 8 + 16,
		Protocol.CHAT: 1 + 4 + 1 + 2 + 200,
		Protocol.WELCOME: 1 + 2 + 1 + 1 + 8 + 16 + 4 + 4 + 1 + 64 + 32 + 2 + 256 + 1 + 8 * (5 + 1 + 24),
		Protocol.TEAM_STATE: 1 + 5 * 4 + 4 * 2 + 1 + 1 + 8 * (1 + 2 + 2),
		Protocol.LOBBY_STATE: 1 + 1 + 2 + 1 + 8 * 3,
		Protocol.ROSTER_REMOVE: 1 + 1 + 255 * 3,
		Protocol.ADMIN_NOTICE: 1 + 1 + 1,
		# MATCH_END without medals: 8 teams, 8 players x 44 B fixed per-player fields.
		Protocol.MATCH_END: 1 + 1 + 1 + 4 + 32 + 1 + 8 * 4 + 1 + 8 * (1 + 4 + 4 + 2 * 6 + 4 * 3 + 5 * 2 + 1),
		Protocol.EVENTS: 1 + 4 + 1, Protocol.ENTITY_META: 1 + 1 + 25, Protocol.KEYFRAME: 1 + 2 + 4 + 1 + 2 + 1280 * 20,
		Protocol.TEAM_DETAIL: 1 + 4 + 1 + 6, Protocol.PROJECTILE_BATCH: 1 + 4 + 1 + 7, Protocol.SNAPSHOT: 10 + 15,
	}
	for id: int in at_most:
		assert_int(at_most[id]).override_failure_message(Protocol.name_of(id)).is_less_equal(Protocol.max_bytes(id))
	assert_int(Protocol.max_bytes(Protocol.SNAPSHOT)).is_equal(Protocol.MAX_UNRELIABLE_BYTES)
	for r: int in Protocol.message_count():
		var id: int = Protocol.CATALOGUE[r * Protocol.CATALOGUE_STRIDE]
		if Protocol.channel_of(id) == Protocol.CH_INPUT or Protocol.channel_of(id) == Protocol.CH_SNAPSHOT:
			assert_int(Protocol.max_bytes(id)).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)


func test_every_byte_is_known_or_reserved() -> void:
	# 0x00 is neither assigned nor reserved by 04 s2.3: it is never a valid id.
	assert_bool(Protocol.is_known(0x00) or Protocol.is_reserved(0x00)).is_false()
	for id: int in range(1, 256):
		assert_bool(Protocol.is_known(id) != Protocol.is_reserved(id)).override_failure_message("id %d" % id).is_true()
		if not Protocol.is_known(id):
			assert_int(Protocol.channel_of(id)).is_equal(-1)
			assert_int(Protocol.max_bytes(id)).is_equal(0)
			assert_str(Protocol.name_of(id)).is_equal("")
			for ch: int in Protocol.CHANNEL_COUNT:
				assert_bool(Protocol.channel_allows(ch, id)).is_false()
	assert_bool(Protocol.is_known(-1)).is_false()
	assert_bool(Protocol.is_known(256)).is_false()
	assert_bool(Protocol.is_reserved(0x70) and Protocol.is_reserved(0xF0)).is_true()


# --- enumerations ---------------------------------------------------------------------------------

func test_enums_match_sim_module_ordinals() -> void:
	var text: String = "\n".join(_section(_read(SIM_MODULE), "## Enumerations"))
	_assert_enum(Protocol.EventKind, _ordinals(text, "`SimEvent.Kind` (`sim/sim_event.gd`):"), "SimEvent.Kind")
	_assert_enum(Protocol.CommandKind, _ordinals(text, "`Command.Kind` (`sim/command.gd`):"), "Command.Kind")
	_assert_enum(Protocol.ResultCode, _ordinals(text, "`CommandResult.Code`:"), "CommandResult.Code")
	_assert_enum(Protocol.BuildReject, _ordinals(text, "`Build.Reject`:"), "Build.Reject")
	_assert_enum(Protocol.ControlState, _ordinals(text, "Control state (`control_state` u8):"), "Control state")
	_assert_enum(Protocol.ReleaseReason, _ordinals(text, "`ReleaseReason`:"), "ReleaseReason")
	_assert_enum(Protocol.DockState, _ordinals(text, "Dock state (pilot block):"), "Dock state")
	_assert_enum(Protocol.PlayerKind, _ordinals(text, "`PlayerKind`:"), "PlayerKind")


func test_04_owned_enums_match_r0_b3() -> void:
	var text: String = "\n".join(_section(_read(DOC_R0), "### B.3 "))
	_assert_enum(Protocol.SessionPhase, _ordinals(text, "**`SessionPhase`** (04):"), "SessionPhase")
	_assert_enum(Protocol.QuickPingKind, _ordinals(text, "**`QuickPing.Kind`** (06 `content/ui/pings.json`, 04 cites):"),
		"QuickPing.Kind")
	# B.3: KEYFRAME.scope lost TIER_C_ONLY; ROSTER_REMOVE reasons are C2-35's three.
	_assert_enum(Protocol.KeyframeScope, PackedStringArray(["ALL", "ROSTER_REPAIR"]), "KeyframeScope")
	_assert_enum(Protocol.RosterRemoveReason, PackedStringArray(["DEATH", "OUT_OF_VISION", "LEFT_INTEREST"]),
		"RosterRemoveReason")


func test_flag_bits_match_team_state_view_and_04() -> void:
	assert_array([Protocol.TEAM_CORE_EXPOSURE, Protocol.TEAM_LOW_POWER, Protocol.TEAM_CORE_SHIELD_UP,
		Protocol.TEAM_SPEND_LOCK_ACTIVE]).is_equal([1, 2, 4, 8])
	assert_array([Protocol.SNAP_HAS_A, Protocol.SNAP_HAS_B, Protocol.SNAP_HAS_C, Protocol.SNAP_HAS_PILOT,
		Protocol.SNAP_CONTINUED, Protocol.SNAP_LAST]).is_equal([1, 2, 4, 8, 16, 32])
	assert_int(Protocol.SNAP_INDEX_SHIFT).is_equal(6)                      # bits 6-7: packet index (A-36)
	# 04 s3.5 worked example: flags 0x2B = HAS_A | HAS_B | HAS_PILOT | LAST.
	assert_int(Protocol.SNAP_HAS_A | Protocol.SNAP_HAS_B | Protocol.SNAP_HAS_PILOT | Protocol.SNAP_LAST).is_equal(0x2B)
	assert_int(Protocol.PROJ_HAS_FUSE).is_equal(0x80)
	assert_int(Protocol.Platform.SERVER_BOT).is_equal(6)
	assert_int(Protocol.RefuseReason.RATE_LIMIT).is_equal(8)
	assert_int(Protocol.PlayerStatus.ELIMINATED_COMMANDER).is_equal(5)
