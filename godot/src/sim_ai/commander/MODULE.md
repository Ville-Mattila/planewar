# sim_ai/commander - MODULE.md

Contract for `godot/src/sim_ai/commander/**`: the Commander bot's opening book (05 s7.3), site resolution
(`BuildPlanner.resolve_site`, ADR-05 radius, 02 AR-1 Outpost presence and spacing) and the bot think that runs them;
AI-23. Sub-module of `sim_ai` (R0 B.9 A-21 split pattern): `sim_ai/MODULE.md` keeps `AiBrain` / `AiDriver`. The reactive
managers (AI-25 economy, AI-26 production, AI-27 military), the `CommandGovernor` (AI-28) and the Adjutant (AI-29) land here
later. A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Compile a `build_orders.json` entry into an `OpeningBook`, run it step by step for one bot slot (`BookRun`), resolve its location tokens to placeable sites, and turn each action into `Command`s through the `CommandSink`. Not here: the reactive planner (AI-25), the rosters (AI-26), squads and raids (AI-27), the rate governor (AI-28). |
| Lane owner tier | Opus (Commander); Sonnet for recipes against this file |
| May depend on | `core`, `content`, `sim`, `sim_ai` (Perception) (`tools/deps.json` row `sim_ai`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`; no `await`, signals, `Thread`, autoloads; never an entity the team does not see |
| Autoloads used | None |
| Status | implemented (AI-23). Constants: `godot/test/sim/ai/ai23_params.json` until `bot_profiles.json` carries the `opening_book` block (needs content); books: `godot/content/defs/build_orders.json` (AI-24: 3 doctrines x 2 books, schema `tools/schemas/build_orders.schema.json`, cross-file rules in `tools/validate_content.py` `check_books`); `godot/test/sim/ai/ai23_books.json` stays the interpreter's unit fixture. |

## Public API

```gdscript
class_name BookParams extends RefCounted             # the interpreter's and planner's constants (session configuration)
const KEYS: PackedStringArray
var book_end_s: float; var max_rejects: int; var stall_s: float; var presence_retry_s: float; var lock_s: float
var approach_m: float; var toward_first_m: float; var toward_step_m: float; var core_ring_m: float; var ring_step_m: float; var gap_m: float; var slot_phase_rad: float
var outpost_ring_m: float; var outpost_cover: float; var move_agl_m: float; var presence_slack_cells: float; var scan_cap: int; var cmds_per_think: PackedInt32Array
static func def_of(index: Dictionary, name: StringName) -> int                 # content entity_index lookup, -1 when absent
static func cell_m() -> float                                                  # one build cell's ground width (m)
func reach_m(presence_radius_m: float) -> float                                # presence radius less presence_slack_cells cells
func orbit_dist_m(hold_orbit_radius_m: float) -> float                         # 3-D site-to-hold-orbit distance of a book move
static func from_dict(d: Dictionary) -> BookParams                             # null on a missing key or a bad value

class_name BookContext extends RefCounted            # what a condition reads, filled once per think
var t_s: float; var ore: float; var ice: float; var power01: float; var enemy_seen: bool; var affordable: bool; var presence: bool
var have_done: PackedInt32Array; var have_all: PackedInt32Array                # by def id: finished / incl. sites
func size_defs(n: int) -> void

class_name BookCondition extends RefCounted          # 05 s7.3 grammar: t ore ice have: power01 enemy_seen affordable presence, & then |
enum Atom { T, ORE, ICE, HAVE, POWER01, ENEMY_SEEN, AFFORDABLE, PRESENCE }
enum Cmp { GE, GT, LE, LT, EQ }
var src: String; var uses_presence: bool; var uses_affordable: bool
static func compile(text: String, def_index: Dictionary, count_sites: bool = false) -> BookCondition   # null when not in the grammar
func eval(c: BookContext) -> bool;  func waits_on_clock(c: BookContext) -> bool

class_name SiteToken extends RefCounted              # core, approach:nearest_enemy, toward:<t>, cold_trap:home, ore_field:home_N, outpost_site:home_trap, contested_field, refinery, outpost
enum Kind { CORE, APPROACH, TOWARD, COLD_TRAP, ORE_FIELD, OUTPOST_SITE, CONTESTED, REFINERY, OUTPOST }
var src: String; var kind: Kind; var arg: String; var nth: int; var inner: SiteToken
static func parse(text: String) -> SiteToken                                   # null outside the grammar

class_name MapSites extends RefCounted               # features.json: start slots, Ore Fields, Cold Traps (public map data)
static func from_features(d: Dictionary) -> MapSites                           # null without start_slots
func slot_count() -> int;  func has_slot(slot: int) -> bool;  func slot_dir(slot: int) -> Vector3
func home_field(slot: int, nth: int) -> Vector3;  func home_trap(slot: int) -> Vector3;  func contested(from: Vector3) -> Vector3   # ZERO = none

class_name BuildPlanner extends RefCounted           # token -> anchor -> k-th valid candidate (unit direction)
enum Status { OK, UNRESOLVED, BLOCKED }
const R: float; const R2: float; const RING: int; const RING_SHIFT: int
var status: Status; var last_k: int; var enemy_hint: Vector3
var own_n: int; var own_def: PackedInt32Array; var own_dir: PackedVector3Array; var own_done: PackedByteArray
var foe_n: int; var foe_def: PackedInt32Array; var foe_dir: PackedVector3Array
func _init(content: ContentSet, params: BookParams, sites: MapSites) -> void
func is_structure(def_id: int) -> bool;  func is_outpost_def(def_id: int) -> bool;  func clear_view() -> void
func add_own(def_id: int, dir: Vector3, done: bool) -> void;  func add_foe(def_id: int, dir: Vector3) -> void
func load_view(perc: Perception, v: SimView) -> void
func anchor(tok: SiteToken, slot: int, issued: int) -> Vector3
func accepts(def_id: int, c: Vector3) -> bool                                  # the pre-check alone
func resolve_site(def_id: int, tok: SiteToken, slot: int, k: int, issued: int) -> Vector3

class_name BookHost extends RefCounted               # what a book needs from its bot (abstract; Out answers)
var next_k: int
func presence(_tok: SiteToken, _def_id: int) -> bool;  func affordable(_kind: int, _def_id: int, _n: int) -> bool
func build(_def_id: int, _tok: SiteToken, _k: int, _issued: int) -> int;  func produce(_def_id: int, _count: int) -> int
func replenish(_def_id: int, _n: int) -> int;  func order(_kind: int, _classes: PackedInt32Array, _tok: SiteToken) -> int
func raid(_target: StringName, _with: StringName) -> int

class_name BookRun extends RefCounted                # one bot's progress; S4 bytes
const PENDING: int; const DONE: int; const SKIPPED_HAVE: int; const SKIPPED_REJECTS: int; const SKIPPED_STALL: int; const SKIPPED_FAIL: int; const FORMAT: int
var book: OpeningBook; var cursor: int; var done: bool; var outcome: PackedByteArray
var rejects: int; var cand_k: int; var issued: int; var due_tick: int; var wait_tick: int
func _init(b: OpeningBook) -> void
func finish(code: int) -> void
func serialize() -> PackedByteArray;  func deserialize(bytes: PackedByteArray) -> bool

class_name OpeningBook extends RefCounted            # a compiled build_orders.json entry and its interpreter
enum Do { BUILD, PRODUCE, SET_REPLENISH, ORDER, RAID }
enum Out { DONE, WAIT, REJECT, FAIL }
const MAX_UNITS_PER_STEP: int
var id: StringName; var doctrine: StringName; var mode: StringName; var reactive: bool; var weight: float; var n_steps: int
static func compile(e: Dictionary, content: ContentSet, errors: Array[String]) -> OpeningBook     # null + errors on a bad entry
func kind_of(i: int) -> int;  func def_of(i: int) -> int;  func count_of(i: int) -> int;  func token_of(i: int) -> SiteToken
func classes_of(i: int) -> PackedInt32Array;  func order_kind_of(i: int) -> int;  func when_of(i: int) -> BookCondition
func think(run: BookRun, ctx: BookContext, host: BookHost, tick: int, hz: int, p: BookParams, budget: int) -> int

class_name CommanderHost extends BookHost            # the bot's actions: Commands through the CommandSink, verdict -> Out
const WAIT_REJECTS: PackedInt32Array
var planner: BuildPlanner; var cmds_left: int
const WAIT_FUNDS: int; const WAIT_SITE: int; const WAIT_CMDS: int; const WAIT_PRESENCE: int
var st_by_code: PackedInt32Array; var st_waits: PackedInt32Array; var st_by_reject: PackedInt32Array; var st_cmds: int; var st_accepted: int; var st_placement_rejects: int; var st_repeat_rejects: int; var st_locked: int; var st_raids: int
func _init(content: ContentSet, params: BookParams, plan: BuildPlanner, tick_hz: int) -> void
func bind_doctrine(slot: int, doctrine: StringName) -> void
func bind_think(v: SimView, sink: CommandSink, perc: Perception, slot: int, tick: int, cap: int, have_done: PackedInt32Array) -> void

class_name CommanderBrain extends AiBrain            # AiDriver.set_brain(cls, brain, true) + schedule_bot(slot, tier)
const FORMAT: int
var st_thinks: int; var host: CommanderHost
func _init(content: ContentSet, params: BookParams, sites: MapSites, tick_hz: int) -> void
func set_books(books: Array[OpeningBook]) -> void;  func pick_book(doctrine: StringName) -> OpeningBook
func bind_rng(rng: Rng) -> void;  func bind_intel(intel: TeamIntel) -> void;  func think_bot(slot: int, tier: int, tick: int, view: SimView, sink: CommandSink) -> void
func serialize() -> PackedByteArray;  func deserialize(bytes: PackedByteArray) -> bool
func run_of(slot: int) -> BookRun;  func book_of(slot: int) -> OpeningBook;  func debug_state(slot: int) -> Dictionary
```

## Invariants

- OB1 (05 s7.3): steps run in order; a step waits for its `when`; a `when` that is false blocks the steps behind it. A `build` or `produce` step is due only while its `when` holds (absent = `affordable`) and it is affordable; a step that costs nothing (`order`, `raid`, `set_replenish`) with no `when` is due at once (R0 B.33 A-162). `BookCondition.compile("")` stays always true; the default is applied in `OpeningBook`. `skip_if_have` counts sites (`have_all`); a `when` `have:` counts finished entities (`have_done`).
- OB2: a REJECTED_PLACEMENT for geometry makes the next think try the next candidate (`BookHost.next_k`); `max_rejects` (3) skip the step. Funds, prerequisites, caps, locks, presence, vision and queue space are WAIT, never a rejection. A site the map does not have (UNRESOLVED) skips at once.
- OB3: a due step that cannot complete for `stall_s` is skipped (SKIPPED_STALL); the stall clock counts a due step's waits for prerequisites, caps, queue space and locks, never a wait on `when` or for funds (A-162; it restarts when the step stops being due). SC-41 leaves a step PENDING at the hand-over only as the `order move` of an Expansion pair that `BookCondition.waits_on_clock` (A-163).
- OB4 (02 AR-1): `OpeningBook.compile` refuses a `build outpost` without `when: presence` or without an `order move` to the same site as the step before it. An Outpost step with no unit in place for `presence_retry_s` re-issues that `order move`.
- OB5: the book hands over to the reactive planner after the last step or at `book_end_s` (`BookRun.done`); a handed-over run issues nothing.
- OB6 (AI-24 review F1, AI-51): a book `order move`'s NOMINAL hold orbit lies inside presence reach: `BookParams.orbit_dist_m(hold_orbit_radius_m)` (order_rules.json hold orbit, horizontal, with `move_agl_m` up) <= `reach_m(outpost_presence_radius_m)` (presence less `presence_slack_cells` build cells); the Commander's own presence test uses the same reach. The order and its presence retry pick an own unit that is not DOCKED, and a docked one only when none else exists (`CommanderHost._pick_unit`). Tests: `test_book_move_reach.gd`,.
- BP1 (ADR-05, 02 AR-1): `resolve_site` returns only candidates that pass the pre-check: footprint centre inside a finished friendly build radius, outside every known enemy build radius, clear of own footprints; an anchor outside every radius is pulled to the edge of the nearest one, except a structure on a node (Ice Extractor). Outposts: no radius; >= 800 m from friendly and >= 1,500 m from enemy Cores / Outposts (sites included); candidates within half the presence radius's horizontal reach of the anchor. The planner is a pure function of its loaded lists; the sim stays the judge.
- CB1 (05 s7.1, s7.9): the Commander reads positions only from the team's `Perception` (own list, known list) and `SimView` reads of own entities; the book's `order` picks only own units that are not POSSESSED and whose head order was not issued by another player within `lock_s`.
- CB2: a think submits at most the tier's `cmds_per_think` commands (the stand-in for the `CommandGovernor`, AI-28); the book is chosen once per slot by weighted draw on the driver's AI RNG among the books of the slot's doctrine; a doctrine with no book idles.
- CB3 (AI-33, SC-47): the slots, book ids and `BookRun`s are S4 bytes (`CommanderBrain.serialize`, written by `AiDriver` FORMAT 3 after the intel section); restore + continue is byte-identical (`test_sc47_commander_save_load.gd`). Books are session configuration: restore with the same books or the bytes are refused.

- Perf (AI-23, `test_commander_perf.gd`; 05 s10 / 03 s4.2 Commander row <= 0.7 ms per slice; dev laptop, SC-41 opening, two bots, vanguard_standard, 600 thinks over 0:00-5:00, best of 3): mean 104 us, p95 155 us, max 523 us. A think is `load_view` (own + known structure lists), one pass over the own list for the counts, then at most `cmds_per_think` steps; `resolve_site` scans <= `scan_cap` candidates against tens of own structures with chord compares (no trigonometry in the loops). No allocation per think except the sim's own `Command` objects.

## Tests

`godot/test/unit/sim_ai/commander/`: `test_book_condition.gd` (grammar), `test_site_tokens.gd` (tokens, `MapSites`), `test_build_planner.gd` (BP1), `test_opening_book.gd` (OB1-OB5, `BookRun` bytes), `test_commander_brain.gd` (CB1, CB2, bytes), `test_commander_perf.gd` (the Commander row), `test_book_move_reach.gd` (OB6). Scenarios `godot/test/sim/ai/`: `test_sc40_opening_vanguard.gd` (SC-40), `test_sc41_all_books.gd` (SC-41), `test_sc43_commander_fog.gd` (SC-43 with the real Commander), `test_sc47_commander_save_load.gd` (CB3). Fixtures `ai23_kit.gd`, `ai23_params.json`, `ai23_books.json`.
