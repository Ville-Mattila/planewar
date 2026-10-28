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

class_name Fmt extends RefCounted         # ui/i18n/fmt.gd (UX-29, 06 s11); separators and units from content/ui/i18n.json
const PARAMS_PATH: String
static func param_str(key: String) -> String
static func param_num(key: String) -> float
static func supported() -> Array
static func normalize(locale: String) -> String                   # "fi_FI" -> "fi"; unsupported -> default_locale
static func separator(locale: String, key: String) -> String
static func integer(n: int, locale: String) -> String             # en "12,400", fi "12 400" (U+202F)
static func decimal(x: float, digits: int, locale: String) -> String
static func distance_m(metres: float, locale: String) -> String   # "850 m", en "1.2 km", fi "1,2 km"
static func clock_24h(seconds_of_day: int) -> String
static func duration(seconds: int) -> String

class_name LocaleSelect extends RefCounted   # ui/i18n/locale_select.gd; App._ready calls setup()
static func resolve(os_locale: String, override_code: String) -> String
static func register_translations(dir: String) -> int            # loads <dir>/<code>.po into TranslationServer
static func saved_override(path: String) -> String
static func save_override(path: String, code: String) -> Error
static func apply(code: String) -> String
static func set_pseudo(enabled: bool) -> void
static func setup() -> String                                     # --ui_locale=, saved override, then OS language; --pseudo_locale

class_name LeadSolver extends RefCounted   # pure statics (UX-17, 06 s6.3): straight-line intercept, no gravity term
static func lead_time(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> float   # INF if none
static func lead_point(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> Vector3
static func pip_visible(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float, range_m: float) -> bool
static func aim_dir(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> Vector3

class_name BombSight extends RefCounted    # pure statics (UX-17); physics injected as Callables (step wraps Kinematics.step_projectile)
const NO_IMPACT: Vector4
static func has_impact(r: Vector4) -> bool
static func predict(p: Vector3, v: Vector3, n: Vector3, eject_down_mps: float, step: Callable, ground: Callable, dt: float = 0.0) -> Vector4   # xyz impact, w time to impact
static func hit_predicted(r: Vector4, targets: PackedVector3Array) -> bool

class_name BombSightView extends Control   # scenes/ui/bomb_sight_view.tscn; ring (green on predicted hit), TTI text, lead pips
func set_ring(pos: Vector2, hit: bool, tti: float) -> void
func hide_ring() -> void
func set_pips(p: PackedVector2Array) -> void

class_name LandingMath extends RefCounted   # pure statics (UX-18, 06 s6.4); bands from hud.json gauge_* (mirror flight_common)
enum Zone { SAFE, DAMAGE, DESTROY }
enum Phase { APPROACH, FLARE, HOVER }
static func zone(value: float, safe: float, damage: float) -> Zone   # > limit is the next band, as Collision.landing_band
static func vert_speed(vel: Vector3, pad_up: Vector3) -> float
static func horiz_speed(vel: Vector3, pad_up: Vector3) -> float
static func nose_from_vertical_deg(fwd: Vector3, pad_up: Vector3) -> float
static func zone_vert(v: float) -> Zone
static func zone_horiz(v: float) -> Zone
static func zone_nose(deg: float) -> Zone
static func zone_color(z: Zone) -> Color
static func fill01(value: float, damage_limit: float) -> float
static func safe_tick01(safe: float, damage_limit: float) -> float
static func guide_visible(pad_dist_m: float, agl_m: float, fuel01: float) -> bool
static func phase(pad_dist_m: float, agl_m: float) -> Phase
static func pad_offset(pos: Vector3, pad_pos: Vector3, pad_up: Vector3, east: Vector3, north: Vector3) -> Vector2
static func drift_arrow(offset_m: Vector2, pad_radius_m: float) -> Vector2
static func first_free(pads: PackedInt32Array, occupants: PackedInt32Array) -> int

class_name LandingStamp extends RefCounted   # grade stamp data from a LANDING event (extra = grade, q, flags, v_vert, v_horiz); points from scoring.json landing_grade
const SCORING_PATH: String
const FLAG_MANUAL: int; const FLAG_HOT: int; const FLAG_DEAD_STICK: int
const GRADE_KEYS: Array[StringName]
const POINT_KEYS: Array[String]
var ship: int; var pad: int; var grade: int; var q: float; var manual: bool; var hot: bool; var dead_stick: bool
var v_vert: float; var v_horiz: float; var base_points: int; var hot_mult: float; var bonus_points: int
static func from_event(e: SimEvent) -> LandingStamp               # null unless a well-formed LANDING
func total_points() -> int
func label_key() -> StringName
func color() -> Color

class_name StatusMath extends RefCounted   # pure statics (UX-18): Core shield timer, cooldown rings, consumables
const CORE_SHIELD_UP: int
enum Boost { READY, ACTIVE, COOLING }
static func shield_remaining_s(until_s: float, clock_s: float) -> float
static func shield_ring01(until_s: float, clock_s: float) -> float
static func shield_visible(team_flags: int, until_s: float, clock_s: float) -> bool
static func ring_fill(cooldown01: float) -> float
static func ring_ready(cooldown01: float) -> bool
static func boost_fill(state: int) -> float
static func share01(count: int, capacity: int) -> float

class_name LandingHudData extends RefCounted   # plain data, read only through SimView
var ship: int; var pad: int; var pad_dist_m: float; var pad_radius_m: float; var agl_m: float
var v_vert: float; var v_horiz: float; var nose_deg: float; var phase: LandingMath.Phase
var visible: bool; var pad_occupied: bool; var drift: Vector2; var docked: bool; var service: Vector3; var waiting: int
var fuel01: float; var ammo: int; var bombs: int; var rockets: int; var flip_cd01: float; var boost: int
static func from_view(v: SimView, id: int, agl: float, radius_m: float) -> LandingHudData

class_name HudText extends RefCounted   # shared HUD text, bar and ring drawing
static func font_size(profile: UiScale.Profile) -> int
static func text(ci: CanvasItem, pos: Vector2, s: String, col: Color, fs: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void
static func bar(ci: CanvasItem, r: Rect2, fill01: float, col: Color, tick01: float = -1.0) -> void
static func ring(ci: CanvasItem, c: Vector2, radius: float, fill01: float, col: Color) -> void

class_name LandingGuideView extends Control   # scenes/ui/landing_guide.tscn; three gauges, flare cue, pad ring and drift arrow
const GAUGE_UNIT: Dictionary
var data: LandingHudData
var profile: UiScale.Profile
func set_data(d: LandingHudData) -> void

class_name ServicePanelView extends Control   # scenes/ui/service_panel.tscn; DOCKED: fuel / ammo / repair bars, waiting note, "thrust to launch"
const BARS: Array[StringName]
var data: LandingHudData
var profile: UiScale.Profile
func set_data(d: LandingHudData) -> void
func fills() -> PackedFloat32Array

class_name GradeStampView extends Control   # scenes/ui/grade_stamp.tscn; shown stamp_hold_s after a LANDING event
signal finished
var stamp: LandingStamp
var profile: UiScale.Profile
var left_s: float
func show_event(e: SimEvent) -> bool
func lines() -> PackedStringArray

class_name StatusClusterView extends Control   # scenes/ui/status_cluster.tscn; consumables, flip / boost rings, Core shield badge
var data: LandingHudData
var profile: UiScale.Profile
var shield_left_s: float
var shield_ring01: float
var shield_shown: bool
func set_data(d: LandingHudData) -> void
func set_shield(team_flags: int, until_s: float, clock_s: float) -> void
func rows() -> Array[PackedStringArray]
```

## Invariants

- U1: on touch, canvas size in du equals window pixels / `screen_scale` (1 du = 1 pt/dp).
- U2: COMPACT iff the visible canvas height < `compact_below_height_du` (500); desktop and Deck at 1280x720/1280x800 are REGULAR.
- U3: the HUD root rect is the display safe area converted to du, clipped to the canvas, inset by `safe_margin_du` (8).
- U4: every `UiTokens` colour equals its `palette.json` entry (test-enforced); regenerate the file, never hand-edit.
- U6: instruments read only `FlightHudData`; altitude is `|pos| - Sphere.PLANET_RADIUS`, bands and uplink thresholds are in `hud.json` (06 s6.2); text never below `font_du_min` (9).
- U7: locale = `--ui_locale`, then saved override (`user://settings.cfg` [ui] locale), then OS language; only `fi` is Finnish. Finnish gaps fall back to English (`locale/fallback="en"`), never to the key. `.po` files are built from `content/locale/src/*.csv` (+ `en.json`) by `tools/locale/build_po.py`; CI fails on a stale PO, missing id, placeholder mismatch or `max_len`.
- U8: bomb sight and lead pip use thresholds from `hud.json` (`bomb_*`, `lead_iterations`); impact within 2 m of a 1/30 s reference, pip matches a straight-flying slug (test-enforced); the HUD calls no sim physics, `app` injects `step`/`ground`.
- U9: landing gauges switch at hud.json `gauge_*` (vert 8/15 m/s, horiz 15/25 m/s, nose 25/45 deg; strictly above a limit is the next band, equal to the sim's `flight_common`, test-enforced); the guide shows within 1,500 m of a friendly pad and below 400 m AGL or fuel < 25 %; the grade stamp decodes LANDING `extra` = [grade, q, flags (bit0 manual, bit1 hot, bit2 dead stick), v_vert, v_horiz] and takes points / hot x / dead-stick bonus from scoring.json `landing_grade` (UX-18).
- U5: thresholds and clamps live in `godot/content/ui/ui_scale.json`, not in code.

## Data owned

`godot/content/ui/ui_scale.json` (scale, profile threshold, safe margin). `godot/content/ui/i18n.json` (locales, separators, units). `scenes/ui/hud_root.tscn`, `godot/content/ui/hud.json`, `scenes/ui/flight_instruments.tscn`, `scenes/ui/{landing_guide,service_panel,grade_stamp,status_cluster}.tscn`.

## Events emitted / consumed

`HudRoot.profile_changed` only. No commands issued yet.

## Performance budget

Layout runs on boot and window resize only; no per-frame cost.

## Test entry points

- `godot/test/unit/ui/test_ui_scale.gd` (U1-U3, profile selection, safe insets, HudRoot)
- `godot/test/unit/ui/test_ui_tokens.gd` (U4)
- `godot/test/unit/ui/test_bomb_sight.gd` (U8: impact vs reference, horizon/ground edges, lead vs analytic and stepped slug)
- `godot/test/unit/ui/test_landing_hud.gd` (U9: gauge bands, guide rule, every grade stamp, shield timer, cooldown rings, SimView read)
- `godot/test/unit/ui/test_hud_math.gd` (U6: pitch, ladder, bank, limb dip, heading wrap, bands, uplink)

- `godot/test/unit/ui/test_fmt.gd` (en/fi formats), `test_locale_select.gd` (U7); Python: `tools/tests/test_locale.py`

## How to add X (recipes for the cheapest tier)

New colour token: add it to `tools/blender/palette.json`, regenerate `ui_tokens.gd` (one `const NAME: Color = Color("#hex")`
per key, upper-case, prefix `RELATION_`/`WORLD_` for those groups), extend `UiTokens` here, run `test_ui_tokens.gd`.

## Open items

ART-21 generates `theme_pw.tres` from the palette and fonts; a `tools/art` generator for `ui_tokens.gd` (needs art lane).
UX-06, UX-16, UX-22 and UX-37 build on `HudRoot`.

needs sim: `boost_cooldown01` (SimView has only the 3-state `boost_state`, so the boost ring has no fraction); waiting-for-Ice/Ore is fed from the WAITING_FOR_* ALERT events by the caller (`LandingHudData.waiting`).
