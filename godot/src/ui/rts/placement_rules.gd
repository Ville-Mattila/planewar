class_name PlacementRules extends RefCounted
## Build placement reasons (docs/06 s7.3, R0 C2-12). `ui` cannot name `Build`, so the 14 `Build.Reject` ordinals are
## mirrored here (a test pins them equal). The one reason line shows the highest of every known reject by the order in
## `content/ui/placement.json`; each value has one `ui.place.reject.*` locale key. Pure statics.

const PARAMS_PATH: String = "res://content/ui/placement.json"

const OK: int = 0
const ELIMINATED: int = 1
const PREREQ: int = 2
const CAP: int = 3
const OCCUPIED: int = 4
const SLOPE: int = 5
const NODE: int = 6
const NOT_VISIBLE: int = 7
const ENEMY_RADIUS: int = 8
const NO_RADIUS: int = 9
const NO_PRESENCE: int = 10
const SPACING: int = 11
const FUNDS: int = 12
const SPEND_LOCKED: int = 13
const COUNT: int = 14
const GENERIC: int = 99   ## a rejection with no placement meaning (rate limit, phase, ...)

const _NAMES: PackedStringArray = ["OK", "ELIMINATED", "PREREQ", "CAP", "OCCUPIED", "SLOPE", "NODE", "NOT_VISIBLE", "ENEMY_RADIUS",
		"NO_RADIUS", "NO_PRESENCE", "SPACING", "FUNDS", "SPEND_LOCKED"]

static var _params: Dictionary = {}
static var _order: PackedInt32Array = PackedInt32Array()


static func _load() -> void:
	if not _params.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
	if parsed is Dictionary:
		var d: Dictionary = parsed
		_params = d
	if _params.is_empty():
		push_error("PlacementRules: %s missing or invalid" % PARAMS_PATH)
		return
	var names: Variant = _params.get("priority", [])
	if names is Array:
		var list: Array = names
		for n: Variant in list:
			var idx: int = _NAMES.find(str(n))
			if idx > 0:
				var _a: bool = _order.append(idx)


static func _num(name: String) -> float:
	_load()
	var v: Variant = _params.get(name, null)
	if v is float or v is int:
		return v
	push_error("PlacementRules: no number '%s' in %s" % [name, PARAMS_PATH])
	return 0.0


static func arm_alt_m() -> float:
	return _num("arm_alt_m")


static func haptic_ms() -> int:
	return int(_num("haptic_ms"))


static func rotations() -> int:
	return int(_num("rotations"))


## The 13 failure reasons, highest priority first.
static func order() -> PackedInt32Array:
	_load()
	return _order


## Position in `order()`; -1 for OK and for anything that is not a placement reject.
static func rank(reject: int) -> int:
	_load()
	return _order.find(reject)


## The highest-priority non-OK reject of `rejects`; OK when there is none.
static func top(rejects: PackedInt32Array) -> int:
	var best: int = OK
	var best_rank: int = COUNT
	for r: int in rejects:
		var k: int = rank(r)
		if k >= 0 and k < best_rank:
			best_rank = k
			best = r
	return best


## Locale key of the reason line; empty for OK. `GENERIC` has its own key.
static func key(reject: int) -> StringName:
	if reject == OK:
		return &""
	if reject > 0 and reject < COUNT:
		return StringName("ui.place.reject." + _NAMES[reject].to_lower())
	return &"ui.place.reject.generic"


## Format arguments of the key: numbers come from content, `facts` may add "deg" (measured slope) and "need" (def id).
static func args(reject: int, facts: Dictionary) -> Dictionary:
	var ec: EconomyDef = ContentDB.economy
	var out: Dictionary = {}
	match reject:
		NO_PRESENCE:
			out["m"] = int(ec.outpost_presence_radius_m) if ec != null else 0
		SLOPE:
			var deg: int = facts.get("deg", 0)
			out["deg"] = deg
			out["max"] = int(ec.build_max_slope_deg) if ec != null else 0
		SPACING:
			out["m"] = int(ec.outpost_spacing_friendly_m) if ec != null else 0
		SPEND_LOCKED:
			out["time"] = Fmt.duration(int(DrawerMath.lock_end_s()))
		PREREQ:
			var need: StringName = facts.get("need", &"")
			out["need"] = DrawerCatalog.name_key(need)
	return out


## The translated reason line; empty for OK.
static func reason(reject: int, facts: Dictionary) -> String:
	var k: StringName = key(reject)
	if k == &"":
		return ""
	var a: Dictionary = args(reject, facts)
	if a.has("need"):
		var nk: String = a["need"]
		a["need"] = TranslationServer.translate(StringName(nk))
	return TranslationServer.translate(k).format(a)


## The reject a `CommandResult` stands for: the payload of REJECTED_PLACEMENT, or the placement reason of the
## code that replaces it (early share lock, cost, cap, prerequisite, rights). OK for ACCEPTED.
static func from_result(code: CommandResult.Code, reject: int) -> int:
	match code:
		CommandResult.Code.ACCEPTED:
			return OK
		CommandResult.Code.REJECTED_PLACEMENT:
			return reject if reject > 0 and reject < COUNT else GENERIC
		CommandResult.Code.REJECTED_LOCKED:
			return SPEND_LOCKED
		CommandResult.Code.REJECTED_COST:
			return FUNDS
		CommandResult.Code.REJECTED_CAP:
			return CAP
		CommandResult.Code.REJECTED_PREREQ:
			return PREREQ
		CommandResult.Code.REJECTED_NO_RIGHTS:
			return ELIMINATED
	return GENERIC


## Rejects the client already knows from the drawer context (rights, share lock, funds).
static func client_rejects(ctx: DrawerContext, def: StringName) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if ctx == null:
		return out
	if ctx.eliminated or not ctx.commander_rights:
		var _e: bool = out.append(ELIMINATED)
	var cost: Vector2i = DrawerCatalog.cost(def, ctx.doctrine)
	if DrawerMath.lock_blocks(ctx.lock_left_ore, cost.x):
		var _l: bool = out.append(SPEND_LOCKED)
	var short: Vector2i = DrawerMath.short_of(cost, ctx.stock())
	if short.x > 0 or short.y > 0:
		var _f: bool = out.append(FUNDS)
	return out


## Footprint cell tint: green when valid, amber for a slope problem, red for everything else.
static func tint(reject: int) -> Color:
	if reject == OK:
		return UiTokens.UI_OK
	if reject == SLOPE:
		return UiTokens.UI_WARN
	return UiTokens.UI_DANGER
