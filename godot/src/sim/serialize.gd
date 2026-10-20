class_name SimSerialize
## The byte form of a whole `SimWorld` (S4; 01 ADR-10; R0 C2-07, C2-25): `SimWorld.serialize()` / `deserialize()` call
## `write` / `read`. File: magic u32, format u32, raw size u32, SHA-256 of the raw body (32 B), `ContentSet.content_hash` (32 B, A-72), then the raw body zstd-compressed (the packed arrays are
## mostly zeros; ~600 KB raw is ~185 KB at 1,200 entities and 2,000 projectiles). Raw body, in this order (names in
## `SECTIONS`): header (seed, RNG, map), rules, clock,
## players, input slots, rate buckets, pending commands, control, entity store, projectile store, Collision's per-slot
## state, Combat's fire state, orders, pathing, vision, economy (`EconomyHub`: Build, Economy, Construction, Production),
## the queued hook events (A-71) and the AI hook's opaque bytes. Events are not included: the caller drains them each tick.
## Versioning: `FORMAT` counts layout changes; there is no migration, a world is only read by the format that wrote it.
## `check` names the reason a byte array is refused so a save slot UI can say "from an older version". Saves are for the
## same build on the same machine (ADR-03/06): the bytes are a function of the state alone.

const MAGIC: int = 0x57535750   ## "PWSW" little-endian
const FORMAT: int = 10          ## 4: Combat fire state (GD-36); 5: TA-21 vision pass clocks, zstd file; 6: raw-body SHA-256 in the header; 7: TA-19 economy section; 8: TA-58 content hash; 9: TA-57 pending hook events; 10: GD-17 launch bay + replenish targets (Production state)
const HASH_BYTES: int = 32
const HEADER_BYTES: int = 12 + 2 * HASH_BYTES   ## magic, format, raw size (u32 each), SHA-256 of the raw body, content hash
const COMPRESSION: int = FileAccess.COMPRESSION_ZSTD
const MAX_RAW_BYTES: int = 64 << 20   ## a header claiming more is refused before anything is allocated
const MAX_TICK_HZ: int = 1000
const MAX_RATIO: int = 256            ## ... as is one claiming more than this many times the compressed size
const SECTIONS: PackedStringArray = ["header", "rules", "clock", "players", "inputs", "rate_buckets", "pending_commands",
	"control", "entities", "projectiles", "collision", "combat", "orders", "pathing", "vision", "economy", "hook"]
const _RULES_STATE: PackedStringArray = ["mode", "caps_profile", "sim_budget_profile", "core_exposure_s", "hard_end_s",
	"debug_commands", "profile_enabled", "friendly_fire", "adjutant_allowed", "sun_period_s", "ranked", "tick_hz"]
const _CAPS_STATE: PackedStringArray = ["id", "units", "structures", "projectiles", "wrecks", "slots"]
const _COLLISION_STATE: PackedStringArray = ["ep_gen", "ep_last", "born_gen", "born_tick"]
const _VISION_STATE: PackedStringArray = ["last_pass"]

enum Status { OK, TOO_SHORT, BAD_MAGIC, OLD_FORMAT, NEWER_FORMAT, CONTENT_MISMATCH }   # append-only; CONTENT_MISMATCH: TA-58, only `check_content` returns it


## OK when `bytes` start with this build's magic and `FORMAT`; otherwise the reason `read` returns null.
static func check(bytes: PackedByteArray) -> Status:
	if bytes.size() < HEADER_BYTES:
		return Status.TOO_SHORT
	if bytes.decode_u32(0) != MAGIC:
		return Status.BAD_MAGIC
	var f: int = bytes.decode_u32(4)
	if f < FORMAT:
		return Status.OLD_FORMAT
	return Status.NEWER_FORMAT if f > FORMAT else Status.OK


## `check`, and CONTENT_MISMATCH when the header's content hash differs from `content.content_hash`.
static func check_content(bytes: PackedByteArray, content: ContentSet) -> Status:
	var st: Status = check(bytes)
	if st == Status.OK and bytes.slice(12 + HASH_BYTES, HEADER_BYTES) != _fit(content.content_hash):
		return Status.CONTENT_MISMATCH
	return st


# A hash as exactly HASH_BYTES (zero-padded or cut): a ContentSet built in code may carry none.
static func _fit(h: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = h.slice(0, HASH_BYTES)
	var _e: int = out.resize(HASH_BYTES)
	return out


## The compressed save bytes of `w` (what `SimWorld.serialize` returns).
static func write(w: SimWorld) -> PackedByteArray:
	return pack(write_raw(w), w._defs.content.content_hash)


## `raw` (a body from `write_raw`) with the file header (carrying `content_hash`) and compression.
static func pack(raw: PackedByteArray, content_hash: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var head: StreamPeerBuffer = StreamPeerBuffer.new()
	head.put_u32(MAGIC)
	head.put_u32(FORMAT)
	head.put_u32(raw.size())
	var _e: int = head.put_data(_hash(raw))
	_e = head.put_data(_fit(content_hash))
	var out: PackedByteArray = head.data_array
	out.append_array(raw.compress(COMPRESSION))
	return out


## The uncompressed body of `bytes`; empty when `check` != OK, the size claim is absurd or the data does not inflate.
static func unpack(bytes: PackedByteArray) -> PackedByteArray:
	if check(bytes) != Status.OK:
		return PackedByteArray()
	var n: int = bytes.decode_u32(8)
	var packed: int = bytes.size() - HEADER_BYTES
	if n <= 0 or n > MAX_RAW_BYTES or packed <= 0 or n > packed * MAX_RATIO:
		return PackedByteArray()
	var raw: PackedByteArray = bytes.slice(HEADER_BYTES).decompress(n, COMPRESSION)
	if raw.size() != n or _hash(raw) != bytes.slice(12, 12 + HASH_BYTES):
		return PackedByteArray()
	return raw


static func _hash(raw: PackedByteArray) -> PackedByteArray:
	var ctx: HashingContext = HashingContext.new()
	var _e: int = ctx.start(HashingContext.HASH_SHA256)
	_e = ctx.update(raw)
	return ctx.finish()


## The uncompressed body of `w`. `marks` (optional, `SECTIONS.size()` entries) receives the size after each section.
static func write_raw(w: SimWorld, marks: PackedInt32Array = PackedInt32Array()) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.put_64(w._match_seed)
	buf.put_var(w.rng.state())
	buf.put_var(String(w._map_id))
	_mark(buf, marks, 0)
	StateIO.put_props(buf, w._rules, _RULES_STATE)
	StateIO.put_props(buf, w._rules.caps, _CAPS_STATE)
	_mark(buf, marks, 1)
	w._state.write_state(buf)
	_mark(buf, marks, 2)
	w._players.write_state(buf)
	_mark(buf, marks, 3)
	w._inputs.write_state(buf)
	_mark(buf, marks, 4)
	w._validator.write_state(buf)
	_mark(buf, marks, 5)
	w._intake.write_state(buf)
	_mark(buf, marks, 6)
	w._control.write_state(buf)
	_mark(buf, marks, 7)
	w._store.write_state(buf)
	_mark(buf, marks, 8)
	w._proj.write_state(buf)
	_mark(buf, marks, 9)
	StateIO.put_props(buf, w.collision, _COLLISION_STATE)
	_mark(buf, marks, 10)
	w._combat.write_state(buf)
	_mark(buf, marks, 11)
	buf.put_var(OrderQueueCodec.serialize(w._orders))
	_mark(buf, marks, 12)
	w._pathing.write_state(buf)
	_mark(buf, marks, 13)
	StateIO.put_props(buf, w.vision, _VISION_STATE)
	_mark(buf, marks, 14)
	w._econ.write_state(buf)
	_mark(buf, marks, 15)
	w._events.write_pending(buf)
	buf.put_var(w._hook.serialize() if w._hook != null else PackedByteArray())
	_mark(buf, marks, 16)
	return buf.data_array


## Bytes per section of `SECTIONS` for `w` as it is now (the size report).
static func size_report(w: SimWorld) -> PackedInt32Array:
	var marks: PackedInt32Array = PackedInt32Array()
	var _e: int = marks.resize(SECTIONS.size())
	var _b: PackedByteArray = write_raw(w, marks)
	for k: int in range(SECTIONS.size() - 1, 0, -1):
		marks[k] -= marks[k - 1]
	return marks


## A world equal to the one `write` saw, with `hook` attached and handed its bytes; null when the bytes are refused
## (`check` != OK), corrupt, malformed, or the map fails to load.
static func read(bytes: PackedByteArray, content: ContentSet, hook: SimAiHook) -> SimWorld:
	if check_content(bytes, content) != Status.OK:
		return null
	var raw: PackedByteArray = unpack(bytes)
	if raw.is_empty():
		return null
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = raw
	var w: SimWorld = SimWorld.new(content)
	w._restoring = true
	var seed_v: int = buf.get_64()
	var rng_v: Variant = buf.get_var()
	var map_v: Variant = buf.get_var()
	if typeof(rng_v) != TYPE_PACKED_BYTE_ARRAY or typeof(map_v) != TYPE_STRING:
		return null
	var rules: MatchRules = MatchRules.new()
	rules.caps = CapsDef.new()
	rules.adopt_match_def(content.match_rules)
	if not StateIO.get_props(buf, rules, _RULES_STATE) or not StateIO.get_props(buf, rules.caps, _CAPS_STATE):
		return null
	if rules.tick_hz < 1 or rules.tick_hz > MAX_TICK_HZ or rules.caps.units < 0 or rules.caps.structures < 0 			or rules.caps.projectiles < 0 or rules.caps.wrecks < 0 or rules.caps.slots < 0:
		return null
	var map: MapDef = MapDef.new()
	map.id = StringName(str(map_v))
	if not w.load_map(map, seed_v, rules).ok or not _read_body(w, buf):
		return null
	var rng_b: PackedByteArray = rng_v
	if not w._events.read_pending(buf):
		return null
	var hv: Variant = buf.get_var()
	if typeof(hv) != TYPE_PACKED_BYTE_ARRAY or buf.get_available_bytes() != 0 or not _indices_ok(w):
		return null
	w.rng = Rng.from_state(rng_b)
	w._hook = hook
	if hook != null:
		var hook_b: PackedByteArray = hv
		hook.deserialize(hook_b)          # last: every check above has passed
	w.spatial.rebuild()
	w.vision.rebuild_lists()
	return w


# Indices the tick uses to address defs and tables, for every live slot and projectile.
static func _indices_ok(w: SimWorld) -> bool:
	var st: EntityStore = w._store
	for list: PackedInt32Array in [st.ships, st.ground, st.structures, st.wrecks]:
		for s: int in list:
			if st.def_id[s] < 0 or st.def_id[s] >= DefRanges.WEAPON_BASE:
				return false
	var ps: ProjectileStore = w._proj
	for i: int in ps.live:
		if ps.projectile_def[i] >= w._defs.projectile_radius.size() or ps.weapon_def[i] >= w._defs.turn_rad_per_s.size():
			return false
	return w.vision.last_pass.size() == Vision.TEAMS


static func _read_body(w: SimWorld, buf: StreamPeerBuffer) -> bool:
	if not (w._state.read_state(buf) and w._players.read_state(buf) and w._inputs.read_state(buf)):
		return false
	if not (w._validator.read_state(buf) and w._intake.read_state(buf) and w._control.read_state(buf)):
		return false
	if not (w._store.read_state(buf) and w._proj.read_state(buf)):
		return false
	if not StateIO.get_props(buf, w.collision, _COLLISION_STATE) or not w._combat.read_state(buf):
		return false
	var ov: Variant = buf.get_var()
	if typeof(ov) != TYPE_PACKED_BYTE_ARRAY:
		return false
	var ob: PackedByteArray = ov
	if not OrderQueueCodec.deserialize(w._orders, ob) or not w._pathing.read_state(buf):
		return false
	if not StateIO.get_props(buf, w.vision, _VISION_STATE) or w.vision.last_pass.size() != Vision.TEAMS:
		return false
	if not w._econ.read_state(buf):
		return false
	for p: int in PlayerTable.SLOTS:
		if w._players.is_active(p):
			var _ok: bool = w._defs.resolve(p, StringName(w._players.doctrine[p]))
			w.vision.bind(p, w._defs.resolved(p))
	w._events.tick = w._state.tick
	return true


static func _mark(buf: StreamPeerBuffer, marks: PackedInt32Array, k: int) -> void:
	if k < marks.size():
		marks[k] = buf.get_size()
