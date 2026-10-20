# sim/orders - MODULE.md

Contract for `godot/src/sim/orders/**` (R0 B.9 A-21 split of `sim/MODULE.md`; R0 C2-06; 05 s3). Written by AI-01 against
`docs/templates/MODULE.md.template`. A change to "Public API" or "Invariants" is a contract change: contract tests first, same
PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines. `OrderSpec` and its enums are the R0 B.3 frozen
enumerations; they grow by appending here and in `sim/MODULE.md`, never by reorder.

| Field | Value |
|---|---|
| Responsibility | The order vocabulary as data: `OrderSpec` (value form), the `orders` side table with the standing and pending queues and the `order_kind` head cache in the entity store, the validity table read from `order_rules.json`, and the byte form used by `SimWorld.serialize`. Does not execute orders (that is the `sim_ai` brains), does not apply `Command.ORDER` (SimWorld intake), does not own the 04 ORDER wire codec (NET-04). |
| Lane owner tier | Sonnet (against this file); Opus reviews |
| May depend on | `core` (`EntityId`), `content` (`OrderRulesDef`, `ShipDef`, `GroundUnitDef`, `StructureDef`, `DefRanges`), `sim` (`EntityStore`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, no signals, no `Thread` |
| Autoloads used | None (callers pass `ContentDB` arrays into `OrderRules.bind`) |
| Status | implemented (AI-01); `SimView.order_head/pending_order/order_issuer` and `Command.ORDER` intake land with TA-18 / AI-15 |

## Public API

```gdscript
class_name OrderSpec extends RefCounted                                      # one order as a value; also the reused scratch OrderQueue.read fills
enum Kind { MOVE = 0, PATROL = 1, ATTACK = 2, ESCORT = 3, HARVEST_HERE = 4, HAUL = 5, RETURN = 6, HOLD = 7, GUARD = 8, SUPPLY_DROP = 9, PATROL_ROUTE = 10, ATTACK_VIA = 11 }   # 9 = SL-5 gate, 10-11 reserved v1.x
enum HaulMode { FERRY = 0, TOW = 1, CAPTURE = 2 }
enum EscortMode { FORM = 0, FOCUS = 1, BREAK = 2 }                           # SL-2
const FLAG_QUEUE := 1; const FLAG_PREPEND := 2; const FLAG_LOW := 4; const FLAGS_CLIENT := 5   # PREPEND is system-only
const KIND_COUNT := 12; const KIND_RESERVED_FIRST := 10; const KIND_NAMES: PackedStringArray   # lower-case JSON names by ordinal
const WIRE_HEADER_BYTES := 9; const WIRE_MAX_BYTES := 256; const WIRE_MAX_POINTS := 16; const WIRE_MAX_IDS := 32; const ESCORT_TRAILER_BYTES := 6; const ESCORT_SLOT_NONE_WIRE := 0xFF   # 04 s2.5 ORDER layout
var kind: Kind; var target: int; var point: Vector3; var points: PackedVector3Array
var haul_mode: HaulMode; var escort_slot: int; var focus: int; var escort_mode: EscortMode   # escort_* = SL-2 (08), -1 / 0 / FORM by default
var flags: int; var issuer: int; var issue_tick: int; var progress: int
static func make(order_kind: Kind, order_target: int = 0, order_point: Vector3 = Vector3.ZERO, order_flags: int = 0) -> OrderSpec
static func kind_name(k: int) -> String;  static func kind_from_name(n: String) -> int      # -1 when unknown
static func is_reserved(k: int) -> bool                                      # 10, 11
static func wire_size(count: int, point_count: int, order_kind: int = -1) -> int;  static func fits_wire(count: int, point_count: int, order_kind: int = -1) -> bool   # ESCORT adds ESCORT_TRAILER_BYTES (R0 B.14 A-85)
func copy_from(o: OrderSpec) -> void;  func equals(o: OrderSpec) -> bool

class_name OrderQueue extends RefCounted                                     # the `orders` side table + head cache; one per SimWorld
enum Push { OK, FULL, NO_POINTS, BAD_SLOT, BAD_SPEC }
const QUEUE_MAX := 8; const STANDING := 0; const PENDING := 1; const SLOTS := 1280   # SLOTS = EntityId.WRECK_SLOT_MIN: main-range slots only
const BLOCK_POINTS := 16; const BLOCK_COUNT := 1280; const NO_BLOCK := -1
var limit: int                                                               # <= QUEUE_MAX, from order_rules.json queue_max
func _init(store: EntityStore)
func reset() -> void                                                         # empties both queues of every slot and the point pool; does not touch the store
func count(slot: int, which: int) -> int;  func free_blocks() -> int
func push(slot: int, which: int, spec: OrderSpec) -> Push                    # QUEUE append / PREPEND front / else replace
func restore(slot: int, which: int, spec: OrderSpec) -> Push                 # append as given, flags untouched (deserialize)
func read(slot: int, which: int, i: int, out: OrderSpec) -> bool             # fills `out`, no allocation once `out.points` is sized
func kind_at(slot: int, which: int, i: int) -> int                           # EntityStore.NONE_U8 when absent
func head_issuer(slot: int) -> int;  func head_tick(slot: int) -> int        # standing head: -1 / 0 when empty
func progress(slot: int, which: int, i: int) -> int;  func set_progress(slot: int, which: int, i: int, value: int) -> bool
func pop_head(slot: int, which: int) -> bool;  func remove_at(slot: int, which: int, i: int) -> bool
func clear(slot: int, which: int) -> void;  func clear_slot(slot: int) -> void   # clear_slot: both queues, call when the entity is freed
func commit_pending(slot: int) -> bool                                       # release: pending replaces standing; false if none pending
func resync_heads() -> void                                                  # rewrite `order_kind` from the standing heads (after restore)
func head_cache_ok() -> bool                                                 # debug/test: cache == head kind (or NONE_U8) for every slot

class_name OrderQueueCodec extends RefCounted                                # deterministic bytes for SimWorld.serialize; not the 04 wire layout
const FORMAT := 1
static func serialize(q: OrderQueue) -> PackedByteArray
static func deserialize(q: OrderQueue, bytes: PackedByteArray) -> bool       # false: queues emptied, nothing applied

class_name OrderRules extends RefCounted                                     # order_rules.json (OrderRulesDef.raw) + validity
enum Verdict { OK, UNKNOWN_KIND, RESERVED_KIND, DISABLED_KIND, NOT_ALLOWED, BAD_FLAGS, BAD_POINTS, BAD_HAUL_MODE, BAD_ESCORT }
var queue_max: int; var patrol_points_min: int; var patrol_points_max: int; var escort_slot_max: int
var arrival_radius_ship_m: float; var arrival_radius_ground_m: float; var default_move_agl_m: float; var ghost_timeout_s: float
var attack_gun_duration_s: float; var patrol_engage_radius_m: float; var escort_engage_radius_m: float
var hold_orbit_radius_m: float; var guard_orbit_radius_m: float; var guard_engage_radius_m: float
var haul_defended_fail_s: float; var no_pad_loiter_altitude_m: float; var no_pad_retry_s: float
static func from_def(d: OrderRulesDef) -> OrderRules
static func malformed(v: Verdict) -> bool                                    # true -> REJECTED_MALFORMED, else REJECTED_INVALID_ORDER
func bind(ships: Array[ShipDef], ground: Array[GroundUnitDef], structures: Array[StructureDef]) -> void   # once at load_map
func allows(kind: int, def_id: int) -> bool;  func kind_enabled(kind: int) -> bool
func validate(spec: OrderSpec, def_id: int, from_client: bool) -> Verdict
```

## Invariants

- O1: Kind, HaulMode, EscortMode ordinals and the three flag bits are frozen (R0 B.3); `KIND_NAMES` is indexed by ordinal.
- O2: Each queue holds at most `min(limit, 8)` orders; `push` with QUEUE returns `FULL` at the cap and changes nothing; PREPEND at the cap drops the tail; replace never fails for capacity.
- O3: `EntityStore.order_kind[slot]` equals the kind of the standing head, or `NONE_U8` when the standing queue is empty, after every `OrderQueue` call that returns (`head_cache_ok()` is the test oracle). Nothing else writes `order_kind`.
- O4: Every standing mutation sets `DIRTY_CONTROL` on the slot (the head is replicated); pending mutations do not. `resync_heads` sets no dirty bits.
- O5: A queue only ever holds specs that `push` or `restore` accepted (kind < 12, <= 16 points); a failed call leaves the table unchanged (`NO_POINTS` frees nothing, takes nothing).
- O6: Patrol waypoints live in `BLOCK_COUNT` blocks of `BLOCK_POINTS`; every block is owned by exactly one record or is on the free stack; `clear_slot`, `pop_head`, `remove_at`, replace and `deserialize` return blocks. Exhaustion is `NO_POINTS` (caller answers `REJECTED_CAP`).
- O7: The owner of the entity store calls `clear_slot(slot)` when it frees an entity; slot reuse then starts with empty queues.
- O8: `OrderQueueCodec.serialize` output is a function of the table state alone (ascending slot, standing then pending); `deserialize(serialize(q))` reproduces every field bit-exactly (points as f32) and the free-block count.
- O9: `OrderRules.validate` is pure and world-free. Order of checks: unknown kind, reserved kind (10-11, never enabled), kind disabled in `enabled_kinds` (9 until the SL-5 gate), flags (client: QUEUE and LOW only; QUEUE and PREPEND together never), points (PATROL 2..8, all other kinds 0), `haul_mode` only with HAUL, escort fields only with ESCORT and in range, then the per-class table. Towers (defs with a `tower` block) accept ATTACK, HOLD, GUARD only; every other structure accepts nothing (V-ORD, C2-06).
- O10: `malformed()` verdicts are layout errors (REJECTED_MALFORMED in 04 V-ORD); the rest are REJECTED_INVALID_ORDER. Target liveness, team, visibility and ghost age are the caller's checks against `SimView`.
- O11: No per-call allocation in `push`, `read` (with a sized `out.points`), `pop_head`, `commit_pending`; `validate` allocates nothing.

## Data owned

- Side table `orders` (this module): `_n[slot*2+which]` counts and 13 packed record arrays of `SLOTS*16` entries, plus the patrol point pool (`BLOCK_COUNT*16` Vector3 and a free stack). About 0.7 MB. `SimWorld` serializes it through `OrderQueueCodec`.
- `EntityStore.order_kind` (owned by `sim`, written only here, O3).
- `godot/content/defs/order_rules.json` + `tools/schemas/order_rules.schema.json` (content: `OrderRulesDef`, keeps the dictionary in `raw`; `OrderRules.from_def` reads it).

## Events emitted / consumed

None. `ORDER_OVERRIDDEN` and `PENDING_ORDER` alerts are raised by `sim/control` and `SimWorld` intake, not here.

## Performance budget

Not on the tick path by itself: calls happen on commands and brain completions. `push` is O(8) record moves; `read` copies <= 16 points. `head_cache_ok`, `resync_heads` and `OrderQueueCodec` scan 1,280 slots and are for tests, load and serialize only (03 s4.2 serialize row). Measured by `perf_tick.gd` once AI-15 wires the intake.

## Test entry points

`godot/test/unit/sim/orders/test_order_queue.gd` (queues, cap, head cache, pending, patrol pool, determinism, codec round-trip), `godot/test/unit/sim/orders/test_order_rules.gd` (class matrix, towers, reserved kinds, flags, wire size), `tools/tests/test_validate_content.py` (schema count 17).

## How to add X (recipes for the cheapest tier)

- **An order kind (appended):** add the ordinal to `OrderSpec.Kind` here and in `sim/MODULE.md`, its name to `KIND_NAMES`, its name to the schema enum, `enabled_kinds` and the classes' `allowed_kinds` in `order_rules.json`, completion/failure rules in 05 s3.2; add a validity test row in `test_order_rules.gd`; raise `KIND_COUNT`. Extend 04's payload only if the C2-06 layout cannot carry it.
- **A class's allowed kinds:** edit `allowed_kinds` in `order_rules.json` (key = def id, or `tower`); update the matrix test.

## Open items

- NET-04 / NET-16: ORDER codec and `ProtocolValidator` call `OrderRules.validate`. The wire header is 9 bytes (04 s2.5 field list; R0 B.16 A-91 corrects the printed `8 +`): a 32-id selection carries at most 14 points (249 B), 15 is refused (257 B); a 32-id ESCORT is 143 B.
- Content: `OrderRulesDef` could expose typed fields instead of `raw`.
- AI-15: ORDER intake in SimWorld (apply to the queue, `REJECTED_*` mapping, ghost-age and visibility checks).
