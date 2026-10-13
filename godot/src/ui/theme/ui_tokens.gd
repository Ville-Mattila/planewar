class_name UiTokens extends RefCounted
## Colour tokens generated from tools/blender/palette.json (docs/07 s2, s4.3). Do not edit by hand;
## test_ui_tokens.gd fails when a value drifts from the palette.

const UI_BG_0: Color = Color("#080B10")
const UI_BG_1: Color = Color("#0F141C")
const UI_BG_2: Color = Color("#18202C")
const UI_LINE: Color = Color("#2B3748")
const UI_TEXT: Color = Color("#E6EBF2")
const UI_TEXT_DIM: Color = Color("#98A4B6")
const UI_ACCENT: Color = Color("#5CC8FF")
const UI_FOCUS: Color = Color("#FFFFFF")
const UI_OK: Color = Color("#6FD08C")
const UI_WARN: Color = Color("#FFC247")
const UI_DANGER: Color = Color("#FF5A5A")
const RES_ORE: Color = Color("#C8A25E")
const RES_ICE: Color = Color("#8FD3F2")
const RES_POWER: Color = Color("#FFF0A0")

const RELATION_ALLY: Color = Color("#2A8FCF")
const RELATION_ENEMY: Color = Color("#D55E00")
const RELATION_SELF: Color = Color("#F0E442")

const WORLD_SPACE: Color = Color("#05070C")
const WORLD_SUN: Color = Color("#FFF1DC")
const WORLD_EARTHSHINE: Color = Color("#9DB6E8")

## Team colours by slot 0..7.
const TEAM: Array[Color] = [
	Color("#E1A633"),
	Color("#4C64ED"),
	Color("#3BFAB2"),
	Color("#17840E"),
	Color("#B1369D"),
	Color("#E9A1FD"),
	Color("#D6F72C"),
	Color("#F06867")
]


static func team_color(slot: int) -> Color:
	return TEAM[clampi(slot, 0, TEAM.size() - 1)]
