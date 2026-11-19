# ui/screens - MODULE.md

Contract for the UX-27 match overlays in `godot/src/ui/screens/**` (06 s8: Loading, Pause, Reconnecting, ELIMINATED_COMMANDER,
Results with REMATCH_VOTE; A-143 split of `ui/MODULE.md`). A change to "Public API" or "Invariants" is a contract change:
contract tests first, same PR; `tools/gen_module_api.py --check` must pass; <= 300 lines.

| Field | Value |
|---|---|
| Responsibility | State and drawing of the match overlays. Models (`ReconnectModel`, `RematchVote`, `LoadingModel`, `PauseModel`, `OverlayState`, `ResultsMath`) are pure and unit-tested; the screen scripts only build Controls and forward signals. |
| Lane owner tier | Sonnet |
| May depend on | as `ui/MODULE.md`; `Protocol.MatchEndReason` (net) for the end reason |
| Must never touch | sim internals, `input/`, `camera/`, `net/` sources |
| Autoloads used | none (`ContentDB` only in tests) |
| Status | UX-27 implemented; UX-09 remap screen |

## Public API

```gdscript
class_name ScreenParams extends RefCounted   # numbers from content/ui/screens.json
const PARAMS_PATH: String
static func param(key: String) -> float
class_name ScreenKit extends RefCounted      # Control builders at the screens.json sizes; text comes from the caller
static func font_px() -> int
static func on(sig: Signal, cb: Callable) -> void
static func label(text: String, size_du: int = 0, color: Color = UiTokens.UI_TEXT) -> Label
static func button(text: String) -> Button
static func shell(root: Control, min_width_du: float) -> VBoxContainer
class_name ScreenBase extends Control        # the FlowScreen protocol (D1: ui may not name app)
func enter(_args: Dictionary) -> void
func exit() -> void
func handle_back() -> bool
func initial_focus() -> Control
class_name ReconnectModel extends RefCounted
enum State { IDLE, RESYNCING, RETRYING, REJOIN_OFFERED, RECOVERED }
var state: State
var elapsed_s: float
var attempts: int
func begin(resync: bool) -> void
func tick(dt: float) -> bool
func on_recovered() -> void
func rejoin() -> bool
func window_s() -> float
func remaining_s() -> float
func is_open() -> bool
class_name RematchVote extends RefCounted
enum Status { DISABLED, PENDING, PASSED, FAILED }
enum Vote { NONE, YES, NO }
var status: Status
var left_s: float
func open(eligible: PackedInt32Array, allowed: bool) -> void
func cast(slot: int, yes: bool) -> bool
func tick(dt: float) -> void
func vote_of(slot: int) -> Vote
func yes_count() -> int
func eligible_count() -> int
class_name LoadingModel extends RefCounted
enum State { DOWNLOADING_MAP, PREWARMING, WAITING_PLAYERS, TIMEOUT }
var map01: float
var prewarm01: float
var ready_count: int
var player_count: int
var waited_s: float
var names: PackedStringArray
var doctrines: PackedStringArray
var ready_flags: PackedByteArray
func set_progress(map_fraction: float, prewarm_fraction: float) -> void
func set_roster(p_names: PackedStringArray, p_doctrines: PackedStringArray, p_ready: PackedByteArray) -> void
func tick(dt: float) -> void
func state() -> State
func ready_fraction() -> float
func progress01() -> float
class_name PauseItem extends RefCounted
var id: StringName
var enabled: bool
var reason_key: StringName
static func make(p_id: StringName, p_enabled: bool = true, p_reason: StringName = &"") -> PauseItem
class_name PauseModel extends RefCounted
const SCOPE_LISTEN_HOST: String
const SCOPE_IN_PROCESS: String
const IDS: Array[StringName]
static func items(online: bool, pause_save: bool, pause_scope: String, surrender_ok: bool) -> Array[PauseItem]
static func pauses_sim(online: bool, pause_scope: String, is_listen_host: bool) -> bool
class_name OverlayState extends RefCounted
enum State { PLAYING, PEEK, PAUSED, RECONNECTING, ELIMINATED_COMMANDER, SPECTATING, ENDING }
static func resolve(ending: bool, reconnecting: bool, paused: bool, eliminated: bool, spectating: bool, peek: bool) -> State
static func is_local_elimination(e: SimEvent, local_slot: int) -> bool
static func is_eliminated(p: PlayerStateView) -> bool
class_name ResultsRow extends RefCounted     # one player of MATCH_END (04 s2.3, R0 C2-17) plus kills and manual landings
const CLASS_IDS: PackedStringArray
var slot: int
var team: int
var player_name: String
var score_pilot: int
var score_commander: int
var kills: int
var manual_landings: int
var structures_destroyed: int
var sorties: int
var ore_mined: int
var ore_spent: int
var ice_delivered: int
var pilot_time_s: PackedInt32Array
var medals: PackedByteArray
static func from_dict(d: Dictionary) -> ResultsRow
class_name ResultsData extends RefCounted    # the decoded MATCH_END: winner, reason, tick, structure_value per team, rows
var winner_team: int
var end_reason: int
var tick: int
var structure_value: PackedInt32Array
var rows: Array[ResultsRow]
static func from_dict(d: Dictionary) -> ResultsData
func team_ids() -> PackedInt32Array
func value_of(team: int) -> int
class_name ResultsMath extends RefCounted
enum Outcome { VICTORY, DEFEAT, TIME_LIMIT }
const COLUMNS: PackedStringArray
static func outcome(winner_team: int, end_reason: int, local_team: int) -> Outcome
static func local_won(winner_team: int, local_team: int) -> bool
static func reason_key(end_reason: int) -> StringName
static func total_score(row: ResultsRow) -> int
static func sorted_rows(rows: Array[ResultsRow]) -> Array[ResultsRow]
static func cells(row: ResultsRow, locale: String) -> PackedStringArray
static func medal_ids(row: ResultsRow, order: PackedStringArray) -> PackedStringArray
static func pilot_times(row: ResultsRow) -> Array[PackedStringArray]
class_name LoadingScreen extends ScreenBase  # scenes/ui/screens/loading.tscn
signal leave_requested
var model: LoadingModel
func state_key() -> StringName
func refresh() -> void
class_name ReconnectScreen extends ScreenBase   # scenes/ui/screens/reconnecting.tscn; enter({resync: bool})
signal retry_due
signal rejoin_requested
signal leave_requested
var model: ReconnectModel
func title_key() -> StringName
func refresh() -> void
class_name PauseScreen extends ScreenBase    # scenes/ui/screens/pause.tscn
signal item_chosen(id: StringName)
var items: Array[PauseItem]
func configure(p_items: Array[PauseItem]) -> void
func button_of(id: StringName) -> Button
class_name RemapModel extends RefCounted     # UX-09 remapping state; persists on every change
var store: BindingStore; var device: StringName; var autosave: bool; var last_conflict: StringName
func _init(p_store: BindingStore) -> void
func actions() -> Array[StringName]; func slot_count() -> int; func set_device(d: StringName) -> void
func is_listening() -> bool; func listening_action() -> StringName; func listening_slot() -> int
func begin_listen(action: StringName, slot: int) -> void; func cancel() -> void
func capture(event: InputEvent) -> bool       # Esc / Start cancel, Delete / View clear, else bind; true when consumed
func clear(action: StringName, slot: int) -> void; func reset_device() -> void
func label(action: StringName, slot: int, glyph_set: StringName) -> String
func conflict_of(action: StringName, slot: int) -> StringName; func has_conflicts() -> bool
class_name RemapScreen extends ScreenBase    # scenes/ui/screens/remap.tscn; enter({store: BindingStore, glyph_set: StringName})
signal done_requested
var model: RemapModel
var glyph_set: StringName
func set_glyph_set(p_set: StringName) -> void   # host calls on InputRouter.glyph_set_changed; labels swap at once
func slot_button(action: StringName, slot: int) -> Button
func prompt_text() -> String
func refresh() -> void
class_name EliminatedOverlay extends Control   # scenes/ui/screens/eliminated.tscn; never blocks input
func show_for(selfdestruct_left_s: float) -> void
func hide_overlay() -> void
func hint_text() -> String
class_name ResultsScreen extends ScreenBase  # scenes/ui/screens/results.tscn
signal rematch_cast(yes: bool)
signal lobby_requested
signal menu_requested
signal report_requested
var data: ResultsData
var vote: RematchVote
var local_team: int
var local_slot: int
var medal_order: PackedStringArray
func outcome() -> ResultsMath.Outcome
func outcome_key() -> StringName
func refresh() -> void
```

## Invariants

- U17: Reconnecting auto-retries (`retry_due` every `reconnect_retry_s`) until `ContentDB.match_rules.reconnect_grace_s` (120) after `begin`, read directly, never mirrored; `LoadingModel` times out at `load_timeout_s` the same way; then `REJOIN_OFFERED` and no more automatic attempts until `rejoin()`. A stall starts RESYNCING and becomes RETRYING after `resync_drop_s` (60, 06 s9.1).
- U18: Results bind every `MATCH_END` field of 06 s8 / R0 C2-17 (winner, `end_reason`, tick, `structure_value` per team; per player `score_pilot`, `score_commander`, medals in `medals.json` order, `structures_destroyed`, `sorties`, `ore_mined`, `ore_spent`, `ice_delivered`, `pilot_time_s[5]`, kills, manual landings). TIME_LIMIT iff `end_reason` is `Protocol.MatchEndReason.HARD_END_VALUE`; a `medals[i]` byte != 0 means earned.
- U19: REMATCH_VOTE lasts `rematch_vote_s` (20); unanimity of the eligible slots passes, any no or the timeout fails.
- U20: Pause items are the eight of 06 s8; Save/Load only offline with `pause_save` and not `listen_host`; `pauses_sim` is true offline and for the Co-op listen host only. Unavailable items stay focusable-by-order but disabled, with a reason key.
- U22: Remap (UX-09): one row per `BindingStore` action, a button per slot, a conflict flag naming the other action, Reset and Done; every control focusable, buttons >= 44 du; B / Esc first cancels a pending listen, then leaves; keys and pad buttons persist on each bind; pad labels follow the active glyph set (`ui.remap.*` keys, `content/ui/screens.json` `remap_list_h_du`).
- U21: every string is a locale key (`ui.loading.*`, `ui.reconnect.*`, `ui.pause.*`, `ui.eliminated.*`, `ui.results.*`, `ui.medal.*`); text >= `font_du_min`; buttons >= `button_h_du` (44); every screen has an initial focus and B / Esc handling.

## Data owned

`content/ui/screens.json`; `scenes/ui/screens/*.tscn`.

## Test entry points

`godot/test/unit/ui/screens/` (`test_reconnect_model.gd`, `test_rematch_vote.gd`, `test_results_math.gd`, `test_overlay_models.gd`, `test_screens_scene.gd`, `test_remap_screen.gd`).

## Open items

needs app: ScreenFlow hosts `ScreenBase` (it casts to `app` `FlowScreen`, which ui may not name, D1); feed Results the decoded MATCH_END dictionary (keys in `ResultsData` / `ResultsRow.from_dict`; `Array` values, not packed arrays) and `ContentDB.medals` ids as `medal_order`; drive `ReconnectScreen.retry_due` into `ClientSession`; show `EliminatedOverlay` on `OverlayState.is_local_elimination`.
needs net: `ClientSession` decodes only the MATCH_END head today; the per-player tail and the rematch-vote messages are not on the wire yet.
