# ui - MODULE.md

Contract for `godot/src/ui/**` (06 s4-s8, ADR-14). UX-12 lands the scale/profile/safe-area/token foundation;
later UX tasks append screens and HUD widgets. A change to "Public API" or "Invariants" is a contract change:
update the contract tests first, in the same PR; `tools/gen_module_api.py --check` must pass; <= 300 lines.

| Field | Value |
|---|---|
| Responsibility | Player-facing screens and HUD. Owns UI scale (du), COMPACT/REGULAR profiles, the safe-area HUD root and colour tokens. Reads the sim only through the named public types; issues commands through `ClientSession`. |
| Lane owner tier | Sonnet |
| May depend on | core, content, input, camera, presentation, net; sim named types only (`tools/deps.json`) |
| Must never touch | sim internals, `input/`, `camera/`, `net/` sources |
| Autoloads used | none so far |
| Status | UX-12 foundation implemented; screens and HUD widgets planned |

## Public API

```gdscript
class_name UiScale extends RefCounted     # pure statics; numbers from content/ui/ui_scale.json
enum Profile { COMPACT, REGULAR }
const PARAMS_PATH: String
static func param(key: String) -> float
static func base_scale(win_px: Vector2i) -> float
static func content_scale_factor(win_px: Vector2i, screen_scale: float, is_touch: bool, user_scale: float) -> float
static func canvas_size_du(win_px: Vector2i, factor: float) -> Vector2
static func profile_for_height(height_du: float) -> Profile
static func select_profile(win_px: Vector2i, screen_scale: float, is_touch: bool, user_scale: float) -> Profile
static func safe_rect_du(win_px: Vector2i, factor: float, safe_px: Rect2i) -> Rect2
static func apply(win: Window, screen_scale: float, is_touch: bool, user_scale: float) -> float

class_name HudRoot extends Control        # scenes/ui/hud_root.tscn; children anchor to the safe rect
signal profile_changed(profile: UiScale.Profile)
var profile: UiScale.Profile
func layout(win_px: Vector2i, factor: float, safe_px: Rect2i) -> void
func refresh(win: Window) -> void

class_name UiTokens extends RefCounted    # generated from tools/blender/palette.json; do not edit by hand
const UI_BG_0: Color; const UI_BG_1: Color; const UI_BG_2: Color; const UI_LINE: Color
const UI_TEXT: Color; const UI_TEXT_DIM: Color; const UI_ACCENT: Color; const UI_FOCUS: Color
const UI_OK: Color; const UI_WARN: Color; const UI_DANGER: Color
const RES_ORE: Color; const RES_ICE: Color; const RES_POWER: Color
const RELATION_ALLY: Color; const RELATION_ENEMY: Color; const RELATION_SELF: Color
const WORLD_SPACE: Color; const WORLD_SUN: Color; const WORLD_EARTHSHINE: Color
const TEAM: Array[Color]
static func team_color(slot: int) -> Color

class_name HudMath extends RefCounted     # pure statics (UX-16, 06 s6.2); numbers from content/ui/hud.json
enum Band { DECK, LOW, HIGH, FADE }
static func param(key: String) -> float
static func pitch(f: Vector3, n: Vector3) -> float
static func altitude(pos: Vector3) -> float
static func is_pole(n: Vector3) -> bool
static func heading_deg(f: Vector3, n: Vector3) -> float          # NAN at a pole
static func wrap_deg(a: float) -> float
static func delta_deg(a: float, b: float) -> float
static func limb_dip(h: float) -> float                           # acos(R / (R + h)), R = Sphere.PLANET_RADIUS
static func ladder_marks(pitch_rad: float, step_deg: float, half_range_deg: float) -> PackedFloat32Array
static func ladder_y(mark_deg: float, pitch_rad: float, px_per_deg: float) -> float
static func limb_y(pitch_rad: float, h: float, px_per_deg: float) -> float
static func band(agl: float, alt: float) -> Band
static func uplink(alt: float) -> float
static func uplink_visible(alt: float) -> bool
static func uplink_lost(alt: float) -> bool
static func uplink_pulse(alt: float, t: float) -> float
static func tape_x(bearing: float, heading: float, width_du: float, span_deg: float) -> float

class_name FlightHudData extends RefCounted   # plain data for the instruments
static func from_state(pos: Vector3, vel: Vector3, b: Basis, ground_radius: float, home_dir: Vector3) -> FlightHudData

class_name FlightInstruments extends Control  # scenes/ui/flight_instruments.tscn; ladder, limb tick, tape, blocks, uplink
var data: FlightHudData
var profile: UiScale.Profile
func set_data(d: FlightHudData) -> void
func readout_rects() -> Array[Rect2]
func font_size() -> int
```

## Invariants

- U1: on touch, canvas size in du equals window pixels / `screen_scale` (1 du = 1 pt/dp).
- U2: COMPACT iff the visible canvas height < `compact_below_height_du` (500); desktop and Deck at 1280x720/1280x800 are REGULAR.
- U3: the HUD root rect is the display safe area converted to du, clipped to the canvas, inset by `safe_margin_du` (8).
- U4: every `UiTokens` colour equals its `palette.json` entry (test-enforced); regenerate the file, never hand-edit.
- U6: instruments read only `FlightHudData`; altitude is `|pos| - Sphere.PLANET_RADIUS`, bands and uplink thresholds are in `hud.json` (06 s6.2); text never below `font_du_min` (9).
- U5: thresholds and clamps live in `godot/content/ui/ui_scale.json`, not in code.

## Data owned

`godot/content/ui/ui_scale.json` (scale, profile threshold, safe margin). `scenes/ui/hud_root.tscn`, `godot/content/ui/hud.json`, `scenes/ui/flight_instruments.tscn`.

## Events emitted / consumed

`HudRoot.profile_changed` only. No commands issued yet.

## Performance budget

Layout runs on boot and window resize only; no per-frame cost.

## Test entry points

- `godot/test/unit/ui/test_ui_scale.gd` (U1-U3, profile selection, safe insets, HudRoot)
- `godot/test/unit/ui/test_ui_tokens.gd` (U4)
- `godot/test/unit/ui/test_hud_math.gd` (U6: pitch, ladder, bank, limb dip, heading wrap, bands, uplink)

## How to add X (recipes for the cheapest tier)

New colour token: add it to `tools/blender/palette.json`, regenerate `ui_tokens.gd` (one `const NAME: Color = Color("#hex")`
per key, upper-case, prefix `RELATION_`/`WORLD_` for those groups), extend `UiTokens` here, run `test_ui_tokens.gd`.

## Open items

ART-21 generates `theme_pw.tres` from the palette and fonts; a `tools/art` generator for `ui_tokens.gd` (needs art lane).
UX-06, UX-16, UX-22 and UX-37 build on `HudRoot`.
