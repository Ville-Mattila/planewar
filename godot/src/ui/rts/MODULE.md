# ui/rts - MODULE.md

Contract for `godot/src/ui/rts/**` (06 s7.2 selection and orders, s7.3 build placement, s7.5 production drawer; A-21 split of `ui/MODULE.md`).
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR; `tools/gen_module_api.py --check` must pass; <= 300 lines.

| Field | Value |
|---|---|
| Responsibility | Selection, picking, orders, control groups, rally lines (UX-20), the production drawer (UX-22) and the build placement controller with validity feedback (UX-21). Issues `Command`s only; the host (app) submits them through ClientSession. |
| Lane owner tier | Sonnet |
| May depend on | as `ui/MODULE.md`; sim named types only (`Build` is injected as a Callable) |
| Must never touch | sim internals, `input/`, `camera/`, `net/` sources |
| Autoloads used | `ContentDB` (defs, economy) |
| Status | UX-20, UX-22 and UX-21 implemented |

## Public API

```gdscript
class_name RtsParams extends RefCounted   # ui/rts/rts_params.gd; numbers from content/ui/rts.json
static func param(key: String) -> float; static func list(key: String) -> Array
class_name OrderClassRules extends RefCounted   # per-class order filter over order_rules.json (enabled_kinds x allowed_kinds); key = def id, towers = &"tower"
static func from_raw(raw: Dictionary) -> OrderClassRules   # raw = OrderRulesDef.raw
static func from_content() -> OrderClassRules                # ContentDB.order_rules
func allows(kind: int, class_key: StringName) -> bool
func is_rally_class(class_key: StringName) -> bool           # rts.json rally_classes (shipyard, vehicle_bay)
class_name OrderResolver extends RefCounted   # pure statics (UX-20, 06 s7.2 table); caller classifies the target; each selected id by class key
enum Target { NEUTRAL, ENEMY, FRIENDLY_PAD, RELAY_STATION, FRIENDLY_UNIT, FRIENDLY_STRUCTURE, ORE_FIELD, ICE_EXTRACTOR, WRECK, GROUND }
const NONE: int; const RALLY: int
static func plan_kind(rules: OrderClassRules, target: Target, cls: StringName, any_attacker: bool) -> int   # OrderSpec.Kind, RALLY or NONE; never a kind the class disallows
static func plan_haul_mode(target: Target) -> OrderSpec.HaulMode
static func resolve(player: int, rules: OrderClassRules, target: Target, target_id: int, target_pos: Vector3, ids: PackedInt32Array, classes: Array[StringName], queue: bool = false) -> Array[Command]
static func resolve_supply(player: int, target_id: int, ids: PackedInt32Array, queue: bool = false) -> Array[Command]
class_name PickMath extends RefCounted   # pure statics (UX-20)
enum PickDevice { POINTER, TOUCH, GAMEPAD }
enum Category { OWN_UNIT, OWN_STRUCTURE, OTHER }
static func radius_du(input: PickDevice) -> float; static func pick(cursor: Vector2, screen: PackedVector2Array, category: PackedInt32Array, depth: PackedFloat32Array, input: PickDevice) -> int
static func paint_radius_du(held_s: float) -> float; static func box_filter(ids: PackedInt32Array, is_unit: PackedByteArray) -> PackedInt32Array
static func same_type(ids: PackedInt32Array, defs: PackedInt32Array, def_id: int) -> PackedInt32Array
class_name SelectionSet extends RefCounted   # client-side selected ids
signal changed
func ids() -> PackedInt32Array
func size() -> int
func has(id: int) -> bool
func set_ids(v: PackedInt32Array) -> void
func add(id: int) -> void
func toggle(id: int) -> void
func clear() -> void
func prune(alive: Callable) -> void
func chunks() -> Array[PackedInt32Array]
class_name ControlGroups extends RefCounted   # client-side, per match, survives possession
func count() -> int
func get_group(slot: int) -> PackedInt32Array
func assign(slot: int, ids: PackedInt32Array) -> void
func add_to(slot: int, ids: PackedInt32Array) -> void
func recall(slot: int, alive: Callable) -> PackedInt32Array
func clear() -> void
class_name RallyMath extends RefCounted   # pure statics
static func line_points(from: Vector3, to: Vector3) -> PackedVector3Array
class_name DrawerLayout extends RefCounted   # pure statics (UX-22, 06 s4.4 / s4.5): 3 x 6 grid, sizes per profile, numbers from rts.json drawer_*
static func cols() -> int; static func rows() -> int; static func capacity() -> int; static func tile_du(profile: UiScale.Profile) -> float; static func gap_du() -> float; static func tab_w_du(profile: UiScale.Profile) -> float
static func tab_h_du(profile: UiScale.Profile) -> float; static func strip_du(profile: UiScale.Profile) -> float; static func font_du(profile: UiScale.Profile) -> int; static func grid_origin(profile: UiScale.Profile) -> Vector2; static func tab_rect(profile: UiScale.Profile, index: int) -> Rect2; static func strip_rect(profile: UiScale.Profile) -> Rect2; static func top_du(profile: UiScale.Profile) -> float; static func grid_size(profile: UiScale.Profile) -> Vector2; static func size_du(profile: UiScale.Profile) -> Vector2
static func tile_rect(profile: UiScale.Profile, index: int) -> Rect2; static func fits(profile: UiScale.Profile, canvas_du: Vector2) -> bool
class_name DrawerCatalog extends RefCounted   # which defs get a tile, all from ContentDB (buildable, produced_at, requires), doctrine-resolved costs
static func structure_ids() -> Array[StringName]; static func unit_ids() -> Array[StringName]; static func factory_of(unit: StringName) -> StringName; static func is_factory(def: StringName) -> bool
static func cost(id: StringName, doctrine: StringName = &"") -> Vector2i; static func requires(id: StringName) -> PackedStringArray; static func max_per_player(id: StringName) -> int; static func name_key(id: StringName) -> String
class_name DrawerMath extends RefCounted   # pure statics (UX-22, 06 s7.5, R0 C3-08): tile state priority, lock, steppers, cancel rights
enum State { AVAILABLE, UNAFFORDABLE, SPEND_LOCKED, LOCKED, CAP_REACHED }; enum Cancel { UNKNOWN, OWNER, DELEGATED, DENIED_NOT_OWNER, DENIED_TEAM }; const KIND_BOT: int; const KIND_OPEN: int
static func classify(tech_ok: bool, capped: bool, cost: Vector2i, stock: Vector2i, lock_left_ore: int) -> State; static func short_of(cost: Vector2i, stock: Vector2i) -> Vector2i
static func lock_blocks(lock_left_ore: int, cost_ore: int) -> bool; static func lock_end_s() -> float; static func share_ore() -> int; static func queue_max() -> int
static func stepper(value: int, delta: int) -> int; static func batch(queue_len: int) -> int; static func pick_factory(ids: PackedInt32Array, queue_lens: PackedInt32Array, dist2: PackedFloat32Array) -> int
static func cancel_verdict(local: int, local_team: int, queuer: int, queuer_team: int, queuer_kind: int, queuer_connected: bool, queuer_eliminated: bool) -> Cancel; static func cancel_allowed(c: Cancel) -> bool
static func cancel_reason(c: Cancel) -> StringName
class_name TileInfo extends RefCounted   # plain data for one tile
var id: StringName; var def: int; var is_unit: bool; var state: DrawerMath.State; var cost: Vector2i; var short: Vector2i; var queued: int; var progress01: float; var replenish: int
var lock_left_ore: int; var need: StringName; var count: int; var limit: int
class_name DrawerContext extends RefCounted   # plain data filled by app from player_state / team_state (ui may not name those views, deps.json)
var player: int; var team: int; var doctrine: StringName; var commander_rights: bool; var eliminated: bool; var ore: int; var ice: int; var unit_cap: int; var structure_cap: int; var unit_count: int; var lock_left_ore: int
func set_player(slot: int, p_team: int, kind: int, connected: bool, p_eliminated: bool) -> void; func has_player(slot: int) -> bool; func player_team(slot: int) -> int; func player_kind(slot: int) -> int; func player_connected(slot: int) -> bool; func player_eliminated(slot: int) -> bool; func stock() -> Vector2i
class_name DrawerModel extends RefCounted   # reads SimView only: tiles, factories, queue verdicts
const FLAG_BUILDING: int; static func sites(view: SimView, team: int, id: StringName) -> PackedInt32Array
static func disabled_reason(ctx: DrawerContext) -> StringName; static func tile(view: SimView, ctx: DrawerContext, id: StringName) -> TileInfo
static func tiles(view: SimView, ctx: DrawerContext, units: bool) -> Array[TileInfo]; static func factories(view: SimView, team: int, unit: StringName) -> PackedInt32Array
static func best_factory(view: SimView, team: int, unit: StringName, focus: Vector3) -> int; static func queue_verdicts(view: SimView, ctx: DrawerContext, factory: int, queuers: PackedInt32Array) -> PackedInt32Array
class_name DrawerCommands extends RefCounted   # builds Commands; the host submits them through ClientSession
static func produce_at_best(view: SimView, ctx: DrawerContext, unit: StringName, count: int, focus: Vector3) -> Command
static func cancel_produce(player: int, factory: int, index: int) -> Command; static func cancel_build(player: int, site: int) -> Command
static func replenish(view: SimView, ctx: DrawerContext, factory: int, unit: StringName, target: int) -> Command
class_name DetailSlot extends RefCounted   # one tile-sized button of the long-press detail page
enum Kind { BACK, BATCH, CANCEL_LAST, REPL_DEC, REPL_VALUE, REPL_INC, QUEUE_ITEM }; var kind: Kind; var index: int; var enabled: bool; var reason: StringName
class_name DrawerText extends RefCounted   # locale keys and args of the drawer; text is translated only in reason() and slot_label()
static func reason_key(info: TileInfo) -> StringName; static func reason_args(info: TileInfo) -> Dictionary; static func reason(info: TileInfo) -> String; static func caption_key(info: TileInfo) -> StringName; static func slot_key(slot: DetailSlot) -> StringName; static func slot_label(slot: DetailSlot, info: TileInfo) -> String
class_name DrawerDetail extends RefCounted   # pure: detail page slots (x5, cancel one, replenish stepper, queue items)
const FIXED_SLOTS: int; static func slots(info: TileInfo, queue_len: int, verdicts: PackedInt32Array, has_factory: bool = true) -> Array[DetailSlot]
class_name DrawerTile extends Button   # one 44 / 64 du tile; draws cost, state, badges, progress ring
signal secondary(tile: DrawerTile); var info: TileInfo; var profile: UiScale.Profile; func set_info(i: TileInfo) -> void; func set_plain(text_value: String, enabled: bool) -> void; var plain_text: String; var plain_on: bool; var long_fired: bool
class_name ProductionDrawer extends Control   # scenes/ui/production_drawer.tscn; BUILD / UNITS tabs, 18 tile buttons, detail page, queue strip; emits Commands
signal command_ready(cmd: Command); signal build_armed(def_id: StringName); var profile: UiScale.Profile; var units_tab: bool
func refresh(view: SimView, ctx: DrawerContext, focus: Vector3) -> void; func set_profile(p: UiScale.Profile) -> void; func tile_nodes() -> Array[DrawerTile]; func focus_first() -> void; func open_detail(id: StringName) -> void
func close_detail() -> void
class_name PlacementRules extends RefCounted   # pure statics (UX-21, 06 s7.3, R0 C2-12): Build.Reject mirror, priority, keys, CommandResult mapping
const OK: int; const ELIMINATED: int; const PREREQ: int; const CAP: int; const OCCUPIED: int; const SLOPE: int; const NODE: int; const NOT_VISIBLE: int; const ENEMY_RADIUS: int
const NO_RADIUS: int; const NO_PRESENCE: int; const SPACING: int; const FUNDS: int; const SPEND_LOCKED: int; const COUNT: int; const GENERIC: int
static func order() -> PackedInt32Array; static func rank(reject: int) -> int; static func top(rejects: PackedInt32Array) -> int
static func key(reject: int) -> StringName; static func args(reject: int, facts: Dictionary) -> Dictionary; static func reason(reject: int, facts: Dictionary) -> String
static func from_result(code: CommandResult.Code, reject: int) -> int; static func client_rejects(ctx: DrawerContext, def: StringName) -> PackedInt32Array
static func tint(reject: int) -> Color; static func arm_alt_m() -> float; static func haptic_ms() -> int; static func rotations() -> int
class_name PlacementMachine extends RefCounted   # pure state machine, the 06 s7.3 diagram
enum State { IDLE, ARMED, POSITIONING, SENT }
var state: State; var def_id: StringName; var cell: int; var rotation: int; var repeat: bool
func arm(id: StringName) -> bool; func set_camera(alt_m: float, focus_cell: int) -> bool; func move_to(new_cell: int) -> bool; func rotate_by(dir: int) -> bool
func confirm(valid: bool) -> bool; func result(accepted: bool) -> bool; func cancel() -> bool; func is_active() -> bool
class_name PlacementRing extends RefCounted   # plain data: one ring on the ground
enum Kind { BUILD, ENEMY_BUILD, PRESENCE, SPACING_FRIENDLY, SPACING_ENEMY }
var kind: Kind; var center: Vector3; var radius_m: float; var follows_ghost: bool; var source: int
func color() -> Color
class_name PlacementRings extends RefCounted   # pure: which rings the armed def shows
static func rings(view: SimView, team: int, def: StringName) -> Array[PlacementRing]
class_name PlacementController extends RefCounted   # glue: machine + injected Build.can_place + Command.build; the host draws, submits and feeds CommandResults
signal command_ready(cmd: Command); signal toast(key: StringName, args: Dictionary); signal validity_flipped(valid: bool); signal state_changed(state: PlacementMachine.State)
var machine: PlacementMachine; var reject: int
func setup(player: int, validator: Callable) -> void   # validator(def_index: int, cell: int, rotation: int) -> int (a Build.Reject ordinal)
func arm(id: StringName, ctx: DrawerContext) -> void; func set_camera(alt_m: float, focus_cell: int) -> void; func move_to(cell: int) -> void; func rotate_by(dir: int) -> void
func set_repeat(on: bool) -> void; func set_facts(facts: Dictionary) -> void; func confirm() -> bool; func cancel() -> void; func on_result(r: CommandResult) -> void; func revalidate(ctx: DrawerContext) -> void
func is_valid() -> bool; func show_pending() -> bool; func reason_key() -> StringName; func reason_args(facts: Dictionary) -> Dictionary
```

## Invariants

- U10: pick radii 22 / 10 / 28 du (touch / pointer / gamepad), paint circle 30 -> 240 du over 1.2 s, 10 control groups, all in `rts.json`. The resolver follows the 06 s7.2 table per selected id, then filters every kind through `order_rules.json` (`OrderClassRules.allows`): the sim rejects a whole ORDER if any id's class disallows the kind, so a unit whose kind is not allowed gets no command, and an output the sim would reject never leaves the resolver (test-enforced for every target x shipped class). Where 06 s7.2 and order_rules.json differ (Harvester return/guard, Bomber escort) order_rules.json wins. Relay Station: haul CAPTURE if the class hauls, else guard if allowed. Enemy: attack for attack-capable classes when the selection has any, else move. Ground tap: SET_RALLY for rts.json `rally_classes`, else move if allowed. ORDER chunks at 32 ids per (kind, haul mode) (UX-20).
- U11: production drawer (UX-22, 06 s7.5): BUILD lists every `buildable` structure and tower (16), UNITS every ship / ground def with `produced_at` (7), derived from ContentDB, never from a class list; 3 x 6 tiles of 44 du (COMPACT) / 64 du (REGULAR), gap 4, all 18 visible without scrolling at 800x360 and 1280x720. Tile state priority LOCKED (a `requires` structure missing, or no finished factory) > CAP_REACHED (unit cap, every factory queue full, `max_per_player`, structure cap) > UNAFFORDABLE > SPEND_LOCKED (`early_spend_left_ore` >= 0 and Ore cost > left) > AVAILABLE, the sim's check order for PRODUCE; test-enforced to agree with `CommandValidator` / `Build.can_place` on a real SimWorld. Costs are doctrine-resolved. Tap on a unit queues 1 at the factory with the shortest queue (tie: nearest the focus); long-press / RMB / pad X opens the detail page (x5 clipped to the free slots, cancel one, replenish stepper 0-12, queue items). Cancel is enabled for the queuer, or any teammate of a queuer who is disconnected, eliminated, a bot or an open slot (`PlayerTable.cancel_delegable`, test-pinned), else disabled with `ui.prod.cancel.not_owner`. An eliminated or rights-less player sees the drawer disabled with `ui.prod.disabled.eliminated`. The drawer only emits `Command`s, and for an eliminated or rights-less player nothing can open, emit or arm: one guard (`_locked`) sits in `_emit`, `_arm`, `open_detail`, `_on_tile`, `_run_slot`, `_on_secondary`, a disabled `DrawerTile` ignores RMB / pad X, and `refresh` closes an open detail page (test_drawer_eliminated.gd).
- U12: build placement (UX-21, 06 s7.3, R0 C2-12): `PlacementMachine` is exactly the s7.3 diagram (IDLE, ARMED, POSITIONING, SENT); ARMED becomes POSITIONING at camera altitude <= `placement.json` `arm_alt_m` (1,200), the ghost starts at the focus cell, rotations wrap over 4, CONFIRM needs a valid ghost, SENT returns to IDLE on ACCEPTED (POSITIONING with `repeat`) and to POSITIONING on any rejection with a toast; CANCEL is ignored while SENT. `ui` cannot name `Build`: the validator is injected as a Callable returning a `Build.Reject` ordinal, and `PlacementRules` mirrors the 14 ordinals (test-enforced equal to `Build.Reject`). One reason line: the highest of the sim verdict and the client facts (`client_rejects`) by `placement.json` `priority` (06 order: ELIMINATED > PREREQ > NO_RADIUS > NO_PRESENCE > ENEMY_RADIUS > NOT_VISIBLE > NODE > OCCUPIED > SLOPE > SPACING > SPEND_LOCKED > FUNDS > CAP), one `ui.place.reject.*` key per value (all 13 plus `generic`); `CommandResult` codes map to Rejects (`from_result`). Outpost has no build-radius rings: it shows the presence ring (`outpost_presence_radius_m`, follows the ghost), amber friendly and red enemy spacing rings around Cores / Outposts (`outpost_spacing_*_m`, enemy only if visible); every other def shows the build radius of own finished structures (and visible enemy ones in red). Radii come from `ContentDB.economy` / defs, never literals. After CONFIRM the pending outline stays (`show_pending`) until `on_result`; validity flips emit `validity_flipped` (haptic `haptic_ms` 8) except the first evaluation.

## Data owned

`content/ui/rts.json` (picking, groups, drawer), `content/ui/placement.json` (arm altitude, reject priority, haptic).

## Test entry points

- `godot/test/unit/ui/test_rts_orders.gd` (U10 resolver table), `test_rts_selection.gd` (U10 picking, groups, rally)
- `godot/test/unit/ui/test_drawer_layout.gd`, `test_drawer_math.gd`, `test_drawer_catalog.gd`, `test_drawer_model.gd` (mocked SimView), `test_drawer_sim_agreement.gd` (real SimWorld), `test_drawer_scene.gd` (U11)
- `godot/test/unit/ui/test_placement_rules.gd` (U12 priority, keys, mirror of `Build.Reject`, result mapping), `test_placement_machine.gd` (U12 diagram), `test_placement_rings.gd` (U12 rings), `test_placement_controller.gd` (U12 pending outline, toast, haptic flip, real SimWorld agreement)

## Open items

needs app (UX-22): fill `DrawerContext` from `SimView.player_state` / `team_state` at 4 Hz (reference: `test/unit/ui/drawer_context_kit.gd`) and submit `command_ready` through ClientSession.
needs sim (UX-22): `LocalSimView.player_state` leaves `early_spend_left_ore` at -1 and `team_state` never sets `SPEND_LOCK_ACTIVE`, so the lock display stays dark offline until they are filled; `SimView.production_queuer(factory, i)` so cancel rights show per item (until then verdict UNKNOWN is enabled and the sim answers); a construction-progress read for sites (the tile ring uses the site `hp01`).

needs app (UX-21): bind `ProductionDrawer.build_armed` to `PlacementController.arm`, inject `validator` = `Build.can_place` of the local world (or ProtocolValidator mirror online), pass the camera altitude and focus cell each frame, submit `command_ready`, call `on_result` for the BUILD result, draw the ghost, footprint tint (`PlacementRules.tint`, cells from `Build.footprint_cells`), `PlacementRings` and the pending outline, and play `haptic_ms` on `validity_flipped`.

needs presentation (UX-21): world-space ghost, ring and outline drawing; ui only supplies the data.
