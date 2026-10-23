class_name NetUnknown
## The 04 s3.7 / s5.6 "unknown" classification of NetSimView: which SimView accessor of which replicated entity this
## client does not receive (the accessor then returns the SimView default). Per accessor, so the HUD can ask about one
## field; NetSimView.unknown(id) is "any field of id unknown". Static.

## Never received for any entity: no 04 s3.7 row (overlay, cargo, cargo_kind, link: CQ-5), a TEAM_DETAIL row NET-39
## has not landed, no codec yet (shield01 GD-38, wreck_ore GD-41), the LANDING event not routed (landing_grade_last).
## While this list is non-empty every entity is `unknown` as a whole.
const NEVER: PackedStringArray = [
	"overlay", "cargo", "cargo_kind", "link",
	"pad_queue", "pad_occupant", "order_head", "order_issuer", "pending_order", "supply01", "production_queue",
	"production_progress01", "auto_replenish_target", "field_remaining", "player_score",
	"shield01", "wreck_ore", "landing_grade_last",
]
## Pilot block fields (own possessed unit only, 04 s3.7); dock_state falls back to flags bit 2 elsewhere but is unknown.
const PILOT: PackedStringArray = [
	"fuel01", "ammo", "bombs", "rockets", "boost_state", "flip_cooldown01", "dock_state", "service_progress",
	"incoming_rockets",
]


## True when `accessor` of roster index `i` (a live entry of `v`) is not received.
static func field(v: NetSimView, i: int, accessor: StringName) -> bool:
	var a: String = String(accessor)
	if NEVER.has(a):
		return true
	if PILOT.has(a):
		return i != v.own_index()
	match a:
		"basis", "vel":
			return not v.pose.has_ori(i)                 # C tier (known blip) or no orientation record
		"ai_tag":
			return v.roster.team_of(i) != v.team_id
		"radius":
			return v.defs.kind_of(v.roster.def_of(i), i) == NetSimView.K_WRECK   # split wrecks: hull / n, n not sent (CQ-4)
	return false
