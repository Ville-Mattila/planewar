# net/interest - MODULE.md

Contract for `godot/src/net/interest/**`: per-client interest management, tiers A / B / C over the shared snapshot
cache (NET-08; 04 s4.1, s4.2 knobs, s13.3 spectators; R0 C1-02). `net/MODULE.md` is at its 300-line cap, so this
subsystem has its own file (R0 B.9 A-21 precedent; 04 s4.1 names `net/interest.gd`, it lives at `net/interest/interest.gd`).
A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Server: once per tick bucket the frame by interest cell (the codec's quantisation cell, 384 cells) and read the per-team visible sets V from the codec (`SnapshotCodec.team_visible`); per client choose the A / B / C encode lists for `SnapshotCodec.encode`, apply caps and hysteresis, keep ghosts 30 s, and report roster joins (ENTITY_META) and leaves (ROSTER_REMOVE). Not here: sending (ServerSession, NET-15), the rolling-refresh pick (NET-07, reads `c_set`), the rate governor (NET-09, sets the knobs), the spectator delay buffer (NET-26). |
| Lane owner tier | Opus |
| May depend on | `core` (`Sphere`), `net` (`Codec`, `Roster`, `SnapshotCodec`, `SnapshotFrame`, `Protocol`) |
| Must never touch | Nodes, `await`, `Thread`, `WorkerThreadPool` (web is single-threaded); `sim` internals (V comes through `SnapshotFrame.visible_mask`, filled by the NET-15 `SimView` adapter from `SimView.visible_to`) |
| Autoloads used | None |
| Status | implemented (NET-08, 2026-10-14); projectile entities (NET-58, R0 B.22 A-112) |

## Public API

```gdscript
class_name Interest extends RefCounted                 # shared per-tick half; one per match
const CAPACITY: int; const CELLS: int; const TEAM_MAX: int; const RING1_STRIDE: int; const RING2_STRIDE: int; const NO_CELL: int   # 3584 384 8; 8 24; -1
var tick: int; var ring1: PackedInt32Array; var ring2: PackedInt32Array; var cell_dir: PackedVector3Array   # ring tables -1 padded
var cell_start: PackedInt32Array; var cell_ids: PackedInt32Array; var all_ids: PackedInt32Array           # per tick: roster indices by cell; all ascending
var stamp: PackedInt32Array; var cell: PackedInt32Array; var dir: PackedVector3Array; var vmask: PackedInt32Array; var gen: PackedInt32Array   # by roster index (vmask = codec c_vmask)
func begin_tick(frame: SnapshotFrame, codec: SnapshotCodec) -> void   # once per tick after codec.prepare_tick(frame); null codec: Sphere.cell_of
func present(s: int) -> bool;  func visible(s: int, team: int) -> bool   # team < 0 = spectator (everything present)
func team_list(team: int) -> PackedInt32Array          # V ascending, once per team per tick; team < 0 = all_ids
func assign(client: InterestClient) -> void            # the per-client half for this tick

class_name InterestClient extends RefCounted           # one per connected client (and per spectator)
enum CameraTier { CHASE, TACTICAL, COMMANDER }         # INTEREST_HINT.camera_tier (04 s2.3), append-only
enum Tier { NONE, A, B, C }
const NONE: int; const A_RADIUS_M: float; const A_CAP: int; const B_CAP: int; const C_CAP: int   # -1; 600; 40 200 1000
const B_PERIOD: int; const C_PERIOD: int; const STICKY_TICKS: int; const GHOST_TICKS: int; const CAPACITY: int   # 2 15 15 900; 3584
var key: int; var team: int; var spectator: bool; var possessed: int; var target: int; var follow: int   # inputs (slots, NONE = none)
var camera_tier: int; var focus_cell: int              # INTEREST_HINT (focus NONE: the anchor's cell)
var a_cap: int; var b_cap: int; var c_cap: int; var b_period: int; var c_period: int   # rate governor knobs (04 s4.2)
var a: PackedInt32Array; var b: PackedInt32Array; var c: PackedInt32Array   # this tick's encode lists (b / c empty off schedule)
var c_set: PackedInt32Array; var cells: PackedInt32Array   # C of the last C tick (rolling refresh); focus + ring of the last B tick
var added: PackedInt32Array; var removed: PackedInt32Array; var removed_reason: PackedInt32Array   # roster deltas this tick
var b_tick: bool; var c_tick: bool
func _init(schedule_key: int = 0, team_id: int = 0) -> void
func reset() -> void                                   # keyframe / reconnect: forget roster and tiers
func in_roster(s: int) -> bool;  func tier_of(s: int) -> int;  func roster_count() -> int
func assign(it: Interest) -> void                      # called by Interest.assign

class_name ProjectileMembers extends RefCounted        # interest/projectile_members.gd: an InterestClient's projectile entities (A-112)
const HOLD_TICKS: int; const NONE: int;  var count: int   # 3 (100 ms, NET-58, not in 04); -1
func reset() -> void;  func add(s: int) -> void
func sweep(it: Interest, t: int, vt: int, rgen: PackedInt32Array, last_tier: PackedInt32Array, hold: PackedInt32Array, c_set: PackedInt32Array, out_s: PackedInt32Array, out_reason: PackedInt32Array) -> void

class_name VisibleSets extends RefCounted              # interest/visible_sets.gd: SnapshotCodec's per-team V lists of one tick (04 s4.1)
const TEAM_MAX: int; const CAPACITY: int               # 8; Roster.CAPACITY
func clear() -> void;  func add(s: int, mask: int) -> void;  func sorted(team: int) -> PackedInt32Array
static func entity_mask(id: int, tick: int, ticks: PackedInt32Array, gens: PackedInt32Array, vmask: PackedInt32Array) -> int   # a shooter / target's V bits, 0 if absent or stale
```

## Rules (04 s4.1 as built)

- Anchor: the possessed entity; else the followed entity (spectator, visible); else, below the Commander camera, the
  focus cell's centre; else none. A = possessed + target (visible) + visible entities whose direction is within
  600 m great-circle of the anchor (cell + ring 1 pre-filter, then a squared-chord check), nearest 40 (forced first).
- B, on `(tick + key) % b_period == 0`: visible entities of the focus cell + ring 1 (ring 2 at COMMANDER) not in A
  this tick, nearest 200 to the focus (cell centre when hinted, else the anchor). C, on `(tick + key) % c_period ==
  0`: V \ A \ B (B = the last B list), ascending slot; over `c_cap`, the nearest to the focus. Sort keys are
  (squared chord, slot) integers: ties are deterministic.
- Hysteresis: promotion is immediate; a member of the previous A (B) list stays while visible and in that tier for
  < 15 ticks, inside the cap after the fresh selection. A demoted entity is labelled C until it is re-tiered.
- Roster: an entity joins when first put in a list or when its slot's generation changed (`added`: send
  ENTITY_META before the snapshot). On the client's C ticks: absent or re-used slot -> DEATH; visible but not in
  any list for 900 ticks -> LEFT_INTEREST; not visible for 900 ticks since last seen on a tier tick -> OUT_OF_VISION
  (30 s, +-0.5 s of C-tick granularity). A ghost that becomes visible again before that re-enters without ENTITY_META.
- Spectator (`spectator = true`): V = everything present, tiers follow the camera like a player (04 s13.3).
- Projectile entities (R0 B.22 A-112; roster indices 1,536-3,583, `SnapshotFrame.index_of_row`: rocket, bomb, siege
  shell, canister rows only): V = own team, or the shooter or target in V (`SnapshotCodec.c_vmask`, gen-checked);
  tiered by their own position like any entity; ENTITY_META before the first record. Swept every tick before selection
  (`ProjectileMembers`), no 30 s ghost: DEATH (absent / new generation), OUT_OF_VISION or LEFT_INTEREST is sent
  HOLD_TICKS after it first holds, and once a member is dead (whatever failed first) its index is neither listed nor
  admitted until HOLD_TICKS after that REMOVE, so
  the reliable ROSTER_REMOVE trails the last record and leads a recycled slot's (0-tick quarantine, A-20) next META
  and record by more than the 04 s15.1 BAD jitter spread; a failing member also leaves `c_set` at once.

## Invariants

- I1: `a`, `b`, `c` contain only slots present this tick and visible to the client's team, each at most once per
  tick across the three lists, every one in the client's roster (joined this tick or before); sizes <= the caps.
- I2: assign is a pure function of (frame, codec cache, client inputs, client state): same inputs, same lists.
- I3: no per-entity allocation; per tick and client a handful of list slices.
- I4: the 600 m disc of any point lies in its cell or ring 1 (cells are wider than 600 m; tested).
- I5 (NET-58): no list or `c_set` names a projectile index during its hold, and no projectile index is both removed
  and added in one tick; the client never parses a recycled projectile index with its previous entry (tested over
  LocalTransport TARGET and BAD, with targets leaving V just before impact: zero malformed snapshots, zero ROSTER_GAP
  requests; test_projectile_hold.gd: OUT_OF_VISION / LEFT_INTEREST, then death and a recycle inside the hold).

## Data owned

None. The tier constants are 04 s4.1 numbers (net constants, not sim balance); the governor changes the knobs.

## Performance budget

03 s4.2 row 12 "events + interest + encode + replay", 4.0 ms p95 for 8 clients (R0 B.7). `bench_snapshot`
mode=interest runs the canonical scene and schedule through real Interest (NET-08 dev-box numbers in `net/MODULE.md`
Performance budget and the PR; the pinned-runner gate is A-40 / A-62, TA-42).

## Test entry points

`godot/test/unit/net/test_interest.gd` (interest_test: A disc, forced, cap; B ring / ring 2 / cap; schedule; team
visibility and spectator; hysteresis; ghost retention, re-entry, expiry; DEATH, slot reuse, LEFT_INTEREST; ring
coverage; determinism), `godot/test/unit/net/test_projectile_roster.gd` (NET-58: visibility rule, no ghost, hold),
`godot/test/net/test_projectile_interest.gd` (NET-58: projectile pipeline, META bytes, LocalTransport TARGET / BAD),
`godot/test/net/test_interest_codec.gd` (with SnapshotCodec, RosterCodec and per-client
decoders: never MISSING_ROSTER, mirrors equal, caps, visibility, < 30 KB/s). Helper: `godot/test/net/interest_rig.gd`.
Benches: `test/perf/bench_snapshot.gd` (mode=interest), `test/perf/bench_events.gd` (mode=interest).

## Open items

- `needs net (NET-15):` fill `SnapshotFrame.gen` and `visible_mask` from `SimView`, call `begin_tick` after
  `prepare_tick`, send `added` as ENTITY_META before the tick's SNAPSHOT and `removed` as ROSTER_REMOVE, feed
  `EventAudience.cells` from `cells` and keep the server-side `Roster` per client in step with added / removed.
- `needs net (NET-07):` the rolling refresh picks from `c_set` and must skip entities no longer visible.
- Contract question: `CameraTier` is a wire enum of INTEREST_HINT; it could move to `Protocol` as a mirror.
