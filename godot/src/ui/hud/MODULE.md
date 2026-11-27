# ui/hud - MODULE.md

Contract for the UX-19 HUD widgets in `godot/src/ui/hud/**` (06 s6.1: threat ring, tower hints, piloted-by badges, pending order,
hand-over toast, canister beacon; A-143 split of `ui/MODULE.md`). The Public API of every script in `ui/hud/` (HudRoot, flight, bomb sight, landing, status: UX-12 to UX-18) moved here verbatim from `ui/MODULE.md`; their invariants U6, U8, U9 stay in the parent.
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR; `tools/gen_module_api.py --check` must pass; <= 300 lines.

| Field | Value |
|---|---|
| Responsibility | Data and drawing of the six situational HUD widgets, each built from `SimView` reads and `SimEvent`s only. Hosts (app) refresh them at the 06 s6.1 rates (threat 10 Hz, hints and badges 4 Hz, the rest on events) and submit the `Command` from `HandoverToast.accept`. |
| Lane owner tier | Sonnet |
| May depend on | as `ui/MODULE.md`; `ContentDB` for tower envelopes |
| Must never touch | sim internals, `input/`, `camera/`, `net/` sources |
| Autoloads used | `ContentDB` |
| Status | UX-19 implemented |

## Public API

```gdscript
class_name HudRoot extends Control        # scenes/ui/hud_root.tscn; children anchor to the safe rect
signal profile_changed(profile: UiScale.Profile)
var profile: UiScale.Profile
func layout(win_px: Vector2i, factor: float, safe_px: Rect2i) -> void
func refresh(win: Window) -> void
class_name HudMath extends RefCounted     # pure statics (UX-16, 06 s6.2); numbers from content/ui/hud.json
enum Band { DECK, LOW, HIGH, FADE }
static func param(key: String) -> float; static func pitch(f: Vector3, n: Vector3) -> float; static func altitude(pos: Vector3) -> float
static func is_pole(n: Vector3) -> bool
static func heading_deg(f: Vector3, n: Vector3) -> float          # NAN at a pole
static func wrap_deg(a: float) -> float; static func delta_deg(a: float, b: float) -> float
static func limb_dip(h: float) -> float                           # acos(R / (R + h)), R = Sphere.PLANET_RADIUS
static func ladder_marks(pitch_rad: float, step_deg: float, half_range_deg: float) -> PackedFloat32Array; static func ladder_y(mark_deg: float, pitch_rad: float, px_per_deg: float) -> float
static func limb_y(pitch_rad: float, h: float, px_per_deg: float) -> float; static func band(agl: float, alt: float) -> Band; static func uplink(alt: float) -> float
static func uplink_visible(alt: float) -> bool; static func uplink_lost(alt: float) -> bool; static func uplink_pulse(alt: float, t: float) -> float
static func tape_x(bearing: float, heading: float, width_du: float, span_deg: float) -> float
static func barrel_deg(rad: float, min_deg: float, max_deg: float) -> int; static func barrel_fill01(deg: float, min_deg: float, max_deg: float) -> float   # UX-49
class_name BarrelReadoutData extends RefCounted   # UX-49: plain data; shown = def has a barrel and the view receives the field
var shown: bool; var deg: int; var min_deg: int; var max_deg: int; var fill01: float
static func has_barrel(g: GroundUnitDef) -> bool; static func from_def(g: GroundUnitDef, rad: float, received: bool) -> BarrelReadoutData
static func from_view(v: SimView, id: int, g: GroundUnitDef) -> BarrelReadoutData   # not received = field_unknown(id, &"barrel_elevation") where the view has it
class_name BarrelReadoutView extends Control   # scenes/ui/barrel_readout.tscn; "ELEV n" + bar + min / max end marks, nothing when not shown
var data: BarrelReadoutData
var profile: UiScale.Profile
func set_data(d: BarrelReadoutData) -> void
func lines() -> PackedStringArray
class_name FlightHudData extends RefCounted   # plain data for the instruments
static func from_state(pos: Vector3, vel: Vector3, b: Basis, ground_radius: float, home_dir: Vector3) -> FlightHudData
class_name FlightInstruments extends Control  # scenes/ui/flight_instruments.tscn; ladder, limb tick, tape, blocks, uplink
var data: FlightHudData
var profile: UiScale.Profile
func set_data(d: FlightHudData) -> void
func readout_rects() -> Array[Rect2]
func font_size() -> int
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
static func vert_speed(vel: Vector3, pad_up: Vector3) -> float; static func horiz_speed(vel: Vector3, pad_up: Vector3) -> float
static func nose_from_vertical_deg(fwd: Vector3, pad_up: Vector3) -> float; static func zone_vert(v: float) -> Zone; static func zone_horiz(v: float) -> Zone
static func zone_nose(deg: float) -> Zone; static func zone_color(z: Zone) -> Color; static func fill01(value: float, damage_limit: float) -> float
static func safe_tick01(safe: float, damage_limit: float) -> float; static func guide_visible(pad_dist_m: float, agl_m: float, fuel01: float) -> bool
static func phase(pad_dist_m: float, agl_m: float) -> Phase; static func pad_offset(pos: Vector3, pad_pos: Vector3, pad_up: Vector3, east: Vector3, north: Vector3) -> Vector2
static func drift_arrow(offset_m: Vector2, pad_radius_m: float) -> Vector2; static func first_free(pads: PackedInt32Array, occupants: PackedInt32Array) -> int
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
enum Boost { READY, ACTIVE, COOLING }
static func shield_remaining_s(until_s: float, clock_s: float) -> float; static func shield_ring01(until_s: float, clock_s: float) -> float
static func shield_visible(team_flags: int, until_s: float, clock_s: float) -> bool; static func ring_fill(cooldown01: float) -> float; static func ring_ready(cooldown01: float) -> bool
static func boost_fill(state: int) -> float;  static func boost_ring_fill(state: int, cooldown01: float) -> float; static func share01(count: int, capacity: int) -> float
class_name LandingHudData extends RefCounted   # plain data, read only through SimView
var ship: int; var pad: int; var pad_dist_m: float; var pad_radius_m: float; var agl_m: float
var v_vert: float; var v_horiz: float; var nose_deg: float; var phase: LandingMath.Phase
var visible: bool; var pad_occupied: bool; var drift: Vector2; var docked: bool; var service: Vector3; var waiting: int
var fuel01: float; var ammo: int; var bombs: int; var rockets: int; var flip_cd01: float; var boost: int; var boost_cd01: float
static func from_view(v: SimView, id: int, agl: float, radius_m: float) -> LandingHudData
class_name HudText extends RefCounted   # shared HUD text, bar and ring drawing
static func font_size(profile: UiScale.Profile) -> int
static func text(ci: CanvasItem, pos: Vector2, s: String, col: Color, fs: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void
static func bar(ci: CanvasItem, r: Rect2, fill01: float, col: Color, tick01: float = -1.0) -> void; static func ring(ci: CanvasItem, c: Vector2, radius: float, fill01: float, col: Color) -> void
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
class_name ThreatMath extends RefCounted   # pure statics (UX-19, 06 s6.1)
static func angle(rel: Vector3, b: Basis) -> float; static func ring_pos(a: float, radius: float) -> Vector2   # angle 0 = up, clockwise positive, (-PI, PI]
static func intensity(dist: float, range_m: float) -> float; static func ahead(rel: Vector3, b: Basis) -> bool
class_name ThreatArrow extends RefCounted   # plain data
var id: int; var angle: float; var dist: float; var intensity: float; var ahead: bool
class_name ThreatData extends RefCounted    # hostiles within threat_range_m, visible to the team, nearest first, at most threat_max_arrows
var arrows: Array[ThreatArrow]; var rocket_lock: bool; var rockets: int
static func from_view(v: SimView, ship: int, team: int) -> ThreatData
class_name TowerHint extends RefCounted     # one hint per hostile tower type in its sensor range, nearest first, at most tower_hint_max
enum Rule { BELOW, ABOVE }
var tower: int; var def: StringName; var rule: Rule; var limit_m: float; var inside: bool; var dist: float
static func rule_for(env: Dictionary) -> Rule; static func limit_for(env: Dictionary) -> float; static func in_envelope(env: Dictionary, h_rel: float, agl: float) -> bool
static func key(r: Rule) -> StringName; static func from_view(v: SimView, ship: int, team: int, agl: float) -> Array[TowerHint]
func text() -> String
class_name PilotBadge extends RefCounted    # plain data
var entity: int; var slot: int; var label: String; var pos: Vector3
class_name PilotedBadges extends RefCounted
static func from_view(v: SimView, local_slot: int, local_team: int, names: Dictionary) -> Array[PilotBadge]   # names: slot -> display name (lobby roster)
static func name_of(slot: int, names: Dictionary) -> String   # roster name or the localised "Player N"
class_name PendingLine extends RefCounted   # "Order from Aino: escort Bomber 2 (on release)"
var entity: int; var kind: int; var issuer: int; var issuer_name: String; var target: int; var target_label: String
static func from_view(v: SimView, id: int, names: Dictionary, label: Callable) -> PendingLine   # null when no pending order; Callable(id: int) -> String
static func verb_key(k: int) -> StringName
func text() -> String
class_name HandoverToast extends RefCounted # one toast, replaced by a newer request
var entity: int; var requester: int; var requester_name: String; var left_s: float
func on_event(e: SimEvent, v: SimView, local_slot: int, names: Dictionary) -> bool   # POSSESS_REQUESTED for the local pilot opens it; RELEASED / HANDOVER of the entity closes it
func tick(dt: float) -> void; func active() -> bool; func dismiss() -> void
func accept(local_slot: int) -> Command   # HANDOVER of the entity to the requester, null when closed
func text() -> String
class_name BeaconPip extends RefCounted     # plain data
var canister: int; var pos: Vector3; var dist: float; var x: float; var on_tape: bool
class_name BeaconTracker extends RefCounted # team canisters from CANISTER_DEPLOYED / CANISTER_COLLECTED
func on_event(e: SimEvent, local_team: int) -> void; func count() -> int; func clear() -> void
func pips(ship_pos: Vector3, heading_deg: float, width_du: float, span_deg: float) -> Array[BeaconPip]   # x via HudMath.tape_x, pinned to the tape edge when off it
func positions() -> PackedVector3Array       # world markers for presentation
class_name ThreatOverlayView extends Control   # scenes/ui/threat_overlay.tscn; ring, hint lines, pending line, toast, beacon pips
var profile: UiScale.Profile
func set_threats(d: ThreatData) -> void; func set_hints(h: Array[TowerHint]) -> void; func set_pending(p: PendingLine) -> void
func set_toast(t: HandoverToast) -> void; func set_beacons(p: Array[BeaconPip]) -> void; func set_badges(b: Array[PilotBadge], screen: PackedVector2Array) -> void
func lines() -> PackedStringArray; func font_size() -> int
```

## Invariants

- U13: the threat ring shows only hostile (team differs), `visible_to` entities within `hud.json` `threat_range_m` (2,000 m), nearest first, at most `threat_max_arrows`; `rocket_lock` iff `incoming_rockets(ship) > 0`. Arrow angle is measured in the ship basis (0 = up, clockwise positive), intensity falls linearly to 0 at the range.
- U14: a tower hint derives from the tower def envelope in `ContentDB` (`h_rel_min`, `h_rel_max`, `target_agl_min`), never from literals: `target_agl_min > 0` -> "stay below" that AGL, else `h_rel_min > 0` -> "stay below" it, else "climb above" `h_rel_max`. `inside` is true when the ship's height above the tower is within the envelope and its AGL is at least the floor.
- U15: badges are shown for own-team ships with `control_state == POSSESSED` flown by another player; names come from the roster the host passes, never from literals. The pending line reads `pending_order`; the toast opens only for a `POSSESS_REQUESTED` whose entity the local player pilots, lasts `toast_s` (8 s, 01 s4.4) and `accept` yields the `HANDOVER` Command (`target` entity, payload u8 requester slot, as `ControlMachine`).
- U16: beacons come from CANISTER_DEPLOYED events of the local team only and end on CANISTER_COLLECTED; the compass pip uses `HudMath.heading_deg` and `HudMath.tape_x`. All text is a locale key (`hud.threat.*`, `hud.tower.*`, `hud.pending.*`, `hud.toast.*`, `hud.badge.*`, `hud.beacon.*`); text never below `font_du_min` (9).

## Data owned

`content/ui/hud.json` keys `threat_*`, `tower_mask`, `tower_hint_max`, `toast_s`, `beacon_pip_du`; `scenes/ui/threat_overlay.tscn`.

## Test entry points

`godot/test/unit/ui/test_threat_hud.gd` (U13, U14), `test_hud_social.gd` (U15, U16), `test_threat_overlay_scene.gd`; scripted views in `hud_scenario_view.gd`.

## Open items
- `StatusMath.boost_fill(state)` deprecated by GD-46 (no caller); delete at a major version, by ADR (10 s4.1).

needs app: refresh `ThreatData`, `TowerHint.from_view` (agl from terrain), `PilotedBadges` and the pip list at their rates, feed `SimEvent`s to `HandoverToast` / `BeaconTracker`, project badge positions through the camera, submit `HandoverToast.accept`; the roster names come from the lobby.
needs sim: `Command.handover(player, entity, to_slot)` builder (UX-19 builds the Command by hand); the `ids_near` mask for hostiles is a kind bitmask, there is no HOSTILE team mask.
needs presentation: the world marker for a beacon (`BeaconTracker.positions`).
