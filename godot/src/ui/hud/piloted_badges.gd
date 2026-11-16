class_name PilotedBadges extends RefCounted
## Names over teammate-flown ships (docs/06 s6.1, s7.6, UX-19; refresh 4 Hz). Display names come from the lobby roster
## the host passes (slot -> String); a missing name falls back to a localised slot label.

const POSSESSED: int = 2   ## SimView.control_state ordinal (sim/MODULE.md: 0 AUTO, 1 ORDERED, 2 POSSESSED)


static func from_view(v: SimView, local_slot: int, local_team: int, names: Dictionary) -> Array[PilotBadge]:
	var out: Array[PilotBadge] = []
	for id: int in v.ships():
		if not v.alive(id) or v.team(id) != local_team or v.control_state(id) != POSSESSED:
			continue
		var slot: int = v.possessor(id)
		if slot == local_slot or slot < 0:
			continue
		var b: PilotBadge = PilotBadge.new()
		b.entity = id
		b.slot = slot
		b.label = name_of(slot, names)
		b.pos = v.pos(id)
		out.append(b)
	return out


## Roster name of `slot`, or the localised "Player N" fallback.
static func name_of(slot: int, names: Dictionary) -> String:
	var n: Variant = names.get(slot, "")
	if n is String:
		var s: String = n
		if not s.is_empty():
			return s
	return TranslationServer.translate(&"hud.badge.slot").format({"n": slot + 1})
