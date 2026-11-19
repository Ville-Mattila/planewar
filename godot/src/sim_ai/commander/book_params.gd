class_name BookParams extends RefCounted
## The constants of the opening-book interpreter and the build planner (05 s7.3, s7.8). Session configuration built from
## a dictionary (`bot_profiles.json` carries the block once content lands it; until then the AI-23 fixture
## `test/sim/ai/ai23_params.json`, as AI-22 did): `from_dict` is null when a key is missing or has the wrong type. No
## literal of this lane's behaviour lives in code.

const KEYS: PackedStringArray = ["book_end_s", "max_rejects", "stall_s", "presence_retry_s", "lock_s", "approach_m",
		"toward_first_m", "toward_step_m", "core_ring_m", "ring_step_m", "gap_m", "outpost_ring_m", "outpost_cover", "move_agl_m", "scan_cap",
		"cmds_per_think"]

var book_end_s: float = 0.0          ## match time at which the book hands over to the reactive planner (05 s7.3: 300)
var max_rejects: int = 0             ## REJECTED_PLACEMENT results that skip a step (3)
var stall_s: float = 0.0             ## a due step that cannot complete for this long is skipped
var presence_retry_s: float = 0.0    ## an Outpost step still without presence after this long re-issues its `order move`
var lock_s: float = 0.0              ## `human_order_lock_s` (s7.8): a human's order on a unit is left alone this long
var approach_m: float = 0.0          ## `approach:` anchors: distance from the Core toward the enemy
var toward_first_m: float = 0.0      ## `toward:` anchors: distance of the first chain step from the Core (inside its radius)
var toward_step_m: float = 0.0       ## `toward:` anchors: spacing of the next steps (inside the previous one's radius)
var core_ring_m: float = 0.0         ## `core` anchors: first ring radius
var ring_step_m: float = 0.0         ## radius growth per ring of candidates (8 per ring)
var gap_m: float = 0.0               ## clearance kept between footprints
var outpost_ring_m: float = 0.0      ## Outpost candidates: ring spacing around the anchor (inside the 300 m presence radius)
var outpost_cover: float = 0.0       ## the home-trap Outpost site lies this share of the Outpost radius short of the trap
var move_agl_m: float = 0.0          ## altitude of an `order move` point above the site
var scan_cap: int = 0                ## candidates examined per `resolve_site` call
var cmds_per_think: PackedInt32Array = PackedInt32Array()   ## per tier (easy, normal, hard, brutal) 05 s7.8; AI-28 replaces it


## Def id of `name` in a content `entity_index`, -1 when absent.
static func def_of(index: Dictionary, name: StringName) -> int:
	var v: int = index.get(name, -1)
	return v


static func from_dict(d: Dictionary) -> BookParams:
	for k: String in KEYS:
		if not d.has(k):
			return null
	var p: BookParams = BookParams.new()
	p.book_end_s = Def.num(d["book_end_s"])
	p.max_rejects = roundi(Def.num(d["max_rejects"]))
	p.stall_s = Def.num(d["stall_s"])
	p.presence_retry_s = Def.num(d["presence_retry_s"])
	p.lock_s = Def.num(d["lock_s"])
	p.approach_m = Def.num(d["approach_m"])
	p.toward_first_m = Def.num(d["toward_first_m"])
	p.toward_step_m = Def.num(d["toward_step_m"])
	p.core_ring_m = Def.num(d["core_ring_m"])
	p.ring_step_m = Def.num(d["ring_step_m"])
	p.gap_m = Def.num(d["gap_m"])
	p.outpost_ring_m = Def.num(d["outpost_ring_m"])
	p.outpost_cover = Def.num(d["outpost_cover"])
	p.move_agl_m = Def.num(d["move_agl_m"])
	p.scan_cap = roundi(Def.num(d["scan_cap"]))
	var c: Variant = d["cmds_per_think"]
	if not (c is Array):
		return null
	var tiers: Array = c
	if tiers.size() != 4:
		return null
	for v: Variant in tiers:
		var _a: bool = p.cmds_per_think.push_back(roundi(Def.num(v)))
	if p.max_rejects < 1 or p.scan_cap < 1 or p.book_end_s <= 0.0:
		return null
	return p
