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
| Status | UX-12 foundation, HUD widgets, UX-20 selection and UX-22 production drawer implemented |

## Public API

```gdscript
class_name UiScale extends RefCounted     # pure statics; numbers from content/ui/ui_scale.json
enum Profile { COMPACT, REGULAR }
const PARAMS_PATH: String
static func param(key: String) -> float; static func base_scale(win_px: Vector2i) -> float
static func content_scale_factor(win_px: Vector2i, screen_scale: float, is_touch: bool, user_scale: float) -> float; static func canvas_size_du(win_px: Vector2i, factor: float) -> Vector2
static func profile_for_height(height_du: float) -> Profile; static func select_profile(win_px: Vector2i, screen_scale: float, is_touch: bool, user_scale: float) -> Profile
static func safe_rect_du(win_px: Vector2i, factor: float, safe_px: Rect2i) -> Rect2; static func apply(win: Window, screen_scale: float, is_touch: bool, user_scale: float) -> float
# HudRoot, HudMath, FlightHudData, FlightInstruments, LeadSolver, BombSight(View), Landing*, StatusMath, HudText, *View: see ui/hud/MODULE.md
class_name UiTokens extends RefCounted    # generated from tools/blender/palette.json; do not edit by hand
const UI_BG_0: Color; const UI_BG_1: Color; const UI_BG_2: Color; const UI_LINE: Color
const UI_TEXT: Color; const UI_TEXT_DIM: Color; const UI_ACCENT: Color; const UI_FOCUS: Color
const UI_OK: Color; const UI_WARN: Color; const UI_DANGER: Color
const RES_ORE: Color; const RES_ICE: Color; const RES_POWER: Color
const RELATION_ALLY: Color; const RELATION_ENEMY: Color; const RELATION_SELF: Color
const WORLD_SPACE: Color; const WORLD_SUN: Color; const WORLD_EARTHSHINE: Color
const TEAM: Array[Color]
static func team_color(slot: int) -> Color
class_name Fmt extends RefCounted         # ui/i18n/fmt.gd (UX-29, 06 s11); separators and units from content/ui/i18n.json
const PARAMS_PATH: String
static func param_str(key: String) -> String; static func param_num(key: String) -> float; static func supported() -> Array
static func normalize(locale: String) -> String                   # "fi_FI" -> "fi"; unsupported -> default_locale
static func separator(locale: String, key: String) -> String
static func integer(n: int, locale: String) -> String             # en "12,400", fi "12 400" (U+202F)
static func decimal(x: float, digits: int, locale: String) -> String
static func distance_m(metres: float, locale: String) -> String   # "850 m", en "1.2 km", fi "1,2 km"
static func clock_24h(seconds_of_day: int) -> String; static func duration(seconds: int) -> String
class_name LocaleSelect extends RefCounted   # ui/i18n/locale_select.gd; App._ready calls setup()
static func resolve(os_locale: String, override_code: String) -> String
static func register_translations(dir: String) -> int            # loads <dir>/<code>.po into TranslationServer
static func saved_override(path: String) -> String; static func save_override(path: String, code: String) -> Error; static func apply(code: String) -> String
static func set_pseudo(enabled: bool) -> void
static func setup() -> String                                     # --ui_locale=, saved override, then OS language; --pseudo_locale
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

`godot/content/ui/ui_scale.json` (scale, profile threshold, safe margin). `godot/content/ui/i18n.json` (locales, separators, units). `scenes/ui/hud_root.tscn`, `godot/content/ui/hud.json`, `scenes/ui/flight_instruments.tscn`, `content/ui/rts.json`, `scenes/ui/{landing_guide,service_panel,grade_stamp,status_cluster,production_drawer}.tscn`; rts.json `drawer_*`, `replenish_max`, `batch_count`, `long_press_s`.

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

## Sub-modules

`godot/src/ui/rts/` (selection, orders, production drawer, build placement) has its own `MODULE.md` (A-21 split): API, invariants U10-U12, tests and open items for those files live there.
`godot/src/ui/hud/MODULE.md` (A-143) holds the UX-19 widgets (threat ring, tower hints, badges, pending order, hand-over toast, beacon; U13-U16).

## Open items

ART-21 done: `godot/assets/ui/theme_pw.tres` is generated by `tools/art/build_theme.py` from the palette (`--check` for staleness); fonts in `godot/assets/ui/fonts/` (Inter body, Rajdhani SemiBold headings, SIL OFL, subset by `tools/art/subset_font.py` per `content/ui/font_charset.json`). Type variations `HeadingLabel`, `DimLabel`; Inter digits are tabular. Test: `test_theme_pw.gd`. A `tools/art` generator for `ui_tokens.gd` is still open (needs art lane).
UX-06, UX-16, UX-22 and UX-37 build on `HudRoot`.

needs sim: `boost_cooldown01` (SimView has only the 3-state `boost_state`, so the boost ring has no fraction); waiting-for-Ice/Ore is fed from the WAITING_FOR_* ALERT events by the caller (`LandingHudData.waiting`).



