# content - MODULE.md

Contract for `godot/src/content/**` (03 s15.3 as amended by R0 B.8 A-1 and A-8; ADR-14). Written by TA-06.
Status: implemented by TA-09 (all additions below the original contract are appends flagged "TA-09 append").
A change to "Public API" or
"Invariants" is a contract change: update the contract tests first, in the same PR (ADR-11);
`tools/gen_module_api.py --check` must pass (TA-27); <= 300 lines.

| Field | Value |
|---|---|
| Responsibility | Load, validate (schema-mirroring, fail-fast), index and hash all JSON defs of R0 B.1; expose typed `*Def` objects and the content hash; load `MapDef` metadata (not the terrain bytes: `sim/Terrain` does that). Applies doctrine modifiers as a pure function producing resolved views (`resolve_for_doctrine`); never mutates base defs. Does not know match state. |
| Lane owner tier | Sonnet (loader, Def classes; TA-09 absorbs 02's GD-06); Haiku (def files, schemas, `_doc` keys; 02's GD-01..05) |
| May depend on | `core` (`tools/deps.json`) |
| Must never touch | `sim`, `sim_ai`, `net`, `ui`, `presentation`; Nodes, except the `ContentDB` autoload node itself |
| Autoloads used | `ContentDB` (defined here, autoload, `extends Node`, no `class_name`: CLAUDE.md, D7 exemption), `Log` |
| Status | implemented (TA-09); API contract frozen 2026-10-10 |

## Public API

Field names are R0 B.1 names; def classes and file ownership are R0 B.1; amendments are R0 B.8 (A-1, A-8). TA-09 appends are
marked "TA-09". Anything not listed is private (prefix `_`). Def fields beyond the ones named here follow R0 B.1 verbatim
(see each `*_def.gd`); typed fields of the thin defs arrive when their consumers name them.

```gdscript
# autoload: godot/src/content/content_db.gd, extends Node, no class_name
signal loaded(ok: bool)
const DEFS_ROOT: String; const MODS_ROOT: String
const K_SHIP: int; const K_GROUND: int; const K_STRUCTURE: int; const K_WEAPON: int; const K_PROJECTILE: int   # TA-09: = DefRanges.K_*
func load_all(root: String = DEFS_ROOT) -> Result                   # synchronous; emits loaded(ok); a failure leaves nothing loaded (N3)
func load_all_async(root: String = DEFS_ROOT) -> void              # same outcome; on web yields a frame between files
func is_loaded() -> bool
var rules: RulesDef;              var flight_common: FlightCommonDef;  var ground_common: GroundCommonDef
var ships: Array[ShipDef];        var ground_units: Array[GroundUnitDef];   var structures: Array[StructureDef]   # structures incl. towers
var weapons: Array[WeaponDef];    var projectiles: Array[ProjectileDef];    var doctrines: Array[DoctrineDef]
var economy: EconomyDef;          var match_rules: MatchRulesDef;           var modes: Array[ModeDef]
var slots_by_player_count: Dictionary                                # TA-09: modes.json "2"|"4"|"6"|"8" -> slot ids
var bot_promises: Array[BotPromiseDef];  var bot_profiles: Array[BotProfileDef];  var autopilots: Array[AutopilotDef]
var order_rules: OrderRulesDef;   var build_orders: Array[BuildOrderDef];   var assists: AssistDef
var scoring: ScoringDef;          var medals: Array[MedalDef];              var progression: ProgressionDef
var quality_tiers: Array[QualityTierDef];  var maps: Array[MapDef]
var wing: WingDef;  var callsigns: CallsignDef;  var barks: Array[BarkDef]   # FEAT-01: R0 B.1 (08 SL-2 / SL-3); null / empty when the file is absent (N8)
var supply_canister: SupplyCanisterDef                              # FEAT-01: commander_verbs.json (08 SL-5, candidate); null when absent (N8)
var missions: Array[MissionDef];  func mission(id: StringName) -> MissionDef   # [planned: GD-30] content/campaign/mNN_<id>.json (02 s16.3); empty until GD-30 (N8)
func def_index(id: StringName) -> int                               # def_id of an ENTITY def (ships, ground units, structures, towers); -1 if unknown
func weapon_index(id: StringName) -> int
func projectile_index(id: StringName) -> int                        # A-1: per-file namespaces; weapon `bomb` and projectile `bomb` coexist
func ship(def_id: int) -> ShipDef
func structure(def_id: int) -> StructureDef
func weapon(def_id: int) -> WeaponDef
func ground_unit(def_id: int) -> GroundUnitDef
func projectile(def_id: int) -> ProjectileDef
func kind_of(def_id: int) -> int                                     # K_* from the range (N2)
func resolve_for_doctrine(doctrine_id: StringName) -> ResolvedDefs  # pure; &"" = unmodified copies; unknown id = null
func content_hash() -> PackedByteArray                               # 32 bytes SHA-256 over the hash scope of R0 B.1
func content_hash_hex() -> String
func map(id: StringName) -> MapDef
func mode(id: StringName) -> ModeDef                                 # pvp_1v1, pvp_2v2, pvp_team, coop, custom, skirmish, campaign
func doctrine(id: StringName) -> DoctrineDef                         # TA-09; null when unknown
func caps(profile: StringName) -> CapsDef                            # &"standard" | &"reduced" | &"lite" (match_rules.json)
func load_mod_pack(dir: String) -> Result                            # STUB: user://mods/ only; overlays top-level *.json, re-validates, re-hashes

class_name Def extends RefCounted     # base
var id: StringName; var def_id: int; var status: StringName; var tags: PackedStringArray; var doc: String   # doc = the _doc key
var presentation: PresentationDef; var raw: Dictionary; var errors: Array[String]; var unknown: Array[String]   # TA-09
static func from_dict(d: Dictionary) -> Def
static func num(v: Variant) -> float                                 # TA-09: Variant -> float (0.0 for non-numbers)
static func flag(v: Variant) -> bool

class_name ShipDef extends Def        # fields as R0 B.1 (02 names), see ship_def.gd
static func from_dict(d: Dictionary) -> ShipDef
class_name FlightCommonDef extends RefCounted   # the top-level flight_common object of ships.json
var raw: Dictionary; var errors: Array[String]; var unknown: Array[String]
static func from_dict(d: Dictionary) -> FlightCommonDef
class_name GroundCommonDef extends RefCounted   # the top-level ground_common object of ground_units.json (A-63): turn rate, reverse speed / hold, slope speed loss
var raw: Dictionary; var errors: Array[String]; var unknown: Array[String]
static func from_dict(d: Dictionary) -> GroundCommonDef
class_name StructureDef extends Def   # structures.json and towers.json
var tower: Dictionary; var shield: Dictionary; var integrated_shield: Dictionary; var explode: Dictionary
static func from_dict(d: Dictionary) -> StructureDef
func is_tower() -> bool
class_name WeaponDef extends Def
static func from_dict(d: Dictionary) -> WeaponDef
class_name ProjectileDef extends Def
static func from_dict(d: Dictionary) -> ProjectileDef
class_name GroundUnitDef extends Def
static func from_dict(d: Dictionary) -> GroundUnitDef
class_name DoctrineDef extends Def
var modifiers: Array; var rules: Dictionary
static func from_dict(d: Dictionary) -> DoctrineDef
class_name RulesDef extends Def
static func from_dict(d: Dictionary) -> RulesDef
class_name MapDef extends Def
static func from_dict(d: Dictionary) -> MapDef
class_name EconomyDef extends Def
static func from_dict(d: Dictionary) -> EconomyDef
class_name MatchRulesDef extends Def
var caps: Dictionary                                                 # StringName -> CapsDef
static func from_dict(d: Dictionary) -> MatchRulesDef
class_name ModeDef extends Def        # JSON null fills NONE_S (-1.0): fill_after_s, core_exposure_s, hard_end_s
static func from_dict(d: Dictionary) -> ModeDef
class_name BotPromiseDef extends Def  # poles_by_s null = -1.0
static func from_dict(d: Dictionary) -> BotPromiseDef
class_name ScoringDef extends Def
static func from_dict(d: Dictionary) -> ScoringDef
class_name BotProfileDef extends Def  # thin: id / tags / raw until sim_ai names fields
static func from_dict(d: Dictionary) -> BotProfileDef
class_name AutopilotDef extends Def
static func from_dict(d: Dictionary) -> AutopilotDef
class_name BuildOrderDef extends Def
static func from_dict(d: Dictionary) -> BuildOrderDef
class_name MedalDef extends Def
static func from_dict(d: Dictionary) -> MedalDef
class_name QualityTierDef extends Def
static func from_dict(d: Dictionary) -> QualityTierDef
class_name OrderRulesDef extends Def
static func from_dict(d: Dictionary) -> OrderRulesDef
class_name AssistDef extends Def
static func from_dict(d: Dictionary) -> AssistDef
class_name ProgressionDef extends Def
static func from_dict(d: Dictionary) -> ProgressionDef
class_name WingDef extends Def          # FEAT-01: wing.json singleton (08 SL-2); typed fields as the SL-2 block
static func from_dict(d: Dictionary) -> WingDef
class_name CallsignDef extends Def      # FEAT-01: callsigns.json singleton (08 SL-3)
static func from_dict(d: Dictionary) -> CallsignDef
class_name BarkDef extends Def          # FEAT-01: one barks.json entry (08 SL-3 rule 3)
static func from_dict(d: Dictionary) -> BarkDef
class_name SupplyCanisterDef extends Def  # FEAT-01: commander_verbs.json `supply_canister` (08 SL-5, candidate)
static func from_dict(d: Dictionary) -> SupplyCanisterDef

class_name ResolvedDefs extends RefCounted
var doctrine_id: StringName; var ships: Array[ShipDef]; var ground_units: Array[GroundUnitDef]; var structures: Array[StructureDef]
var weapons: Array[WeaponDef]; var projectiles: Array[ProjectileDef]; var rules: Dictionary
var flip_cooldown_s_override: float; var hangar_blocks_rockets: bool; var reactor_unlock_s: float
func ship(def_id: int) -> ShipDef
func ground_unit(def_id: int) -> GroundUnitDef
func structure(def_id: int) -> StructureDef
func weapon(def_id: int) -> WeaponDef
func projectile(def_id: int) -> ProjectileDef
func serialise() -> String                                           # canonical text of every resolved def (N7)
class_name PresentationDef extends RefCounted   # mesh: String, far_mesh_node: StringName, vfx: PackedStringArray, sfx: Dictionary, pool: int, budget_tris: int
var mesh: String; var far_mesh_node: StringName; var vfx: PackedStringArray; var sfx: Dictionary; var pool: int; var budget_tris: int; var raw: Dictionary
static func from_dict(d: Variant) -> PresentationDef
class_name CapsDef extends RefCounted           # one caps profile of match_rules.json (A-8)
var id: StringName; var units: int; var structures: int; var projectiles: int; var wrecks: int; var slots: int
static func from_dict(profile: StringName, d: Dictionary) -> CapsDef

class_name DefRanges extends RefCounted         # TA-09: N2 range constants
const SHIP_BASE: int; const GROUND_BASE: int; const STRUCTURE_BASE: int; const WEAPON_BASE: int; const PROJECTILE_BASE: int; const END: int
const K_NONE: int; const K_SHIP: int; const K_GROUND: int; const K_STRUCTURE: int; const K_WEAPON: int; const K_PROJECTILE: int
static func kind_of(def_id: int) -> int
static func base_of(kind: int) -> int
static func size_of(kind: int) -> int
class_name ContentHash extends RefCounted       # TA-09: N1 canonicaliser, identical to tools/content_hash.py
static func hash_texts(files: Dictionary) -> PackedByteArray
static func included_names(names: Array) -> PackedStringArray
static func canonical(v: Variant) -> String
static func number_text(x: float) -> String
class_name ContentLoader extends RefCounted     # TA-09: pure build, no Log, no Nodes
static func build(texts: Dictionary, map_texts: Dictionary) -> ContentSet
class_name ContentSet extends RefCounted        # TA-09: one load's defs + indexes + hash + errors / warnings
var errors: Array[String]; var warnings: Array[String]; var content_hash: PackedByteArray
func ok() -> bool
class_name DoctrineResolver extends RefCounted  # TA-09: pure resolution
static func resolve(doctrine: DoctrineDef, ships: Array[ShipDef], ground: Array[GroundUnitDef], structures: Array[StructureDef], weapons: Array[WeaponDef], projectiles: Array[ProjectileDef]) -> ResolvedDefs
static func round_field(leaf: String, x: float) -> float
```

Resolution semantics (02 s7): `weapon_mount` selectors address weapons only; `ids` / `tags_any` address ships, ground
units and structures/towers (all present keys must match). A modifier skips defs that lack the dotted field. Rounding is
applied once per touched field: `cost_*` to 5, `hp` / damage / counts to 1, everything else to 0.1, halves up.
`rules.flip_cooldown_s_override` is applied to every resolved ship's `flip_cooldown_s`; `hangar_blocks_rockets` and
`reactor_unlock_s` are exposed on `ResolvedDefs`. `resolve_for_doctrine(&"")` returns unmodified copies; an unknown id
returns null (and logs). Required def files: the 12 in `godot/content/defs/` today; the rest of R0 B.1 (doctrines,
bot_profiles, autopilots, order_rules, build_orders, assists, medals, progression, quality_tiers) load when present.
`load_mod_pack` is a stub: it overlays the pack's top-level `*.json` over the stock texts (same name replaces), re-validates and
re-hashes; only `user://mods/...` is accepted; manifests, signing and the lobby hash check are not implemented.

Other Def classes named in R0 B.1 (`EconomyDef`, `MatchRulesDef`, `ModeDef`, `BotPromiseDef`, `BotProfileDef`,
`AutopilotDef`, `OrderRulesDef`, `BuildOrderDef`, `AssistDef`, `ScoringDef`, `MedalDef`, `ProgressionDef`,
`QualityTierDef`, and per R0 B.9 A-15 `WingDef`, `CallsignDef`, `BarkDef`, `SupplyCanisterDef`, `MissionDef`) extend
`Def` or `RefCounted` as their B.1 row says; their fields are listed in R0 B.1 / 02 s16.3 / 08 only. TA-09 declares every
class and loader; the field lists of the four FEAT-01 classes (`WingDef`, `CallsignDef`, `BarkDef`, `SupplyCanisterDef`,
FEAT-01 schemas and files, landed) and of `MissionDef` (GD-30 missions) are appends to the class, never a rename.

## Invariants

- N1: `content_hash()` equals the SHA-256 that `tools/validate_content.py` computes for the same files (03 s9.2, TA-08; vector test).
- N2: def_id ranges: ships 0-255, ground 256-511, structures and towers 512-1023, weapons 1024-1279, projectiles
  1280-1535. `kind_of` is pure arithmetic. `def_index` searches the entity ranges only; `weapon_index` and
  `projectile_index` search their own range (A-1).
- N3: load fails (`Result` failure, `loaded(false)`) on any schema violation; the game never runs on partially
  loaded content.
- N4: defs are immutable after `loaded(true)`; no setter exists; `resolve_for_doctrine` returns copies.
- N5: every `presentation.mesh` path exists in the export (checked by `validate_scenes.gd`).
- N6: `load_all` on PC-mid completes in <= 150 ms for the v1 def set (~400 entries).
- N7: `resolve_for_doctrine` is pure: same input gives byte-identical serialised output; 02's rounding rule applied once.
- N8 (R0 B.9 A-15): a def file that R0 B.1 lists but whose feature has not shipped (`wing`, `callsigns`, `barks`,
  `commander_verbs`, `quality_tiers`, `campaign/*`) loads as `null` / empty when the file is absent; a present file must
  validate (N3). Every other B.1 file is required.

## Data owned

Typed `Def` arrays built by `load_all`; the content hash bytes; a `ResolvedDefs` per doctrine, produced on request by
`resolve_for_doctrine` (never stored back into a base def). JSON files read from `res://content/defs/` and `user://mods/<id>/` only. Presentation
files (`sfx.json`, `vfx_prewarm.json`) and `chat_filter.json` are read but excluded from the hash (R0 B.1).

## Events emitted / consumed

`loaded(ok: bool)` (signal, emitted once per load; App boot waits on it, APP-01). No `SimEvent`, no `Command`.
Consumers: `sim` and `net` read defs and the hash through this API; neither writes them.

## Performance budget

PC-mid, `load_all` <= 150 ms for ~400 entries (N6). `resolve_for_doctrine` is a per-match call, not per tick.
Scenario: planned perf test (TA-09), not yet on disk.

## Test entry points

Existing (checked by check_deps D10): `tools/tests/test_validate_content.py` (CONTRACT-0 def schemas and namespace rule),
`godot/test/unit/content/test_content_db.gd` (loads the real defs, N3, N4, caps, modes, dangling refs, `flight_common.brake_fade_mps` and A-29..A-35 fields, N6 gate),
`godot/test/unit/content/test_content_hash.gd` (N1 vector and Python cross-check), `godot/test/unit/content/test_def_ranges.gd`
(N2, A-1 `bomb` both ids), `godot/test/unit/content/test_doctrine_resolve.gd` (N7, 02 s7 examples, base defs unchanged).

Planned (plain text until the file exists): godot/test/perf/perf_content.gd (N6 on the pinned runner, TA-42).

## How to add a unit (Haiku recipe)

1. Add an entry to `godot/content/defs/ships.json` (or the matching file) copying the nearest class and editing stats
   within schema bounds (02 names, R0 B.1); `status: "candidate"` until 02 promotes it.
2. Set `presentation.mesh` to an existing placeholder mesh until 07 delivers.
3. Run `python tools/validate_content.py`.
4. Run `godot/addons/gdUnit4/runtest.sh -a res://test/unit/content -c -rd reports`.
5. PR with the `_doc` line. No GDScript change is needed: `def_index` picks the next free index in the class range.
   A new unit in the v1 roster still needs an 01 amendment (01 s12 brief 02).

## Open items

- R0 B.9 A-15 (`docs/reviews/R0-amendments-02.md`) settles `WingDef`, `CallsignDef`, `BarkDef`, `SupplyCanisterDef`,
  `MissionDef` and the N8 optional-file rule; TA-09 (merged) did not implement them yet: follow-up task, with the def files.
- R0 B.9 appends the loader must read (follow-up to TA-09): `flight_common.brake_fade_mps` (A-13) is read (TA-45, sim PR);
  the A-29..A-35 flight fields are read (TA-48, sim PR); still open: `ModeDef.pause_scope` / `caps_web_mobile` (A-16, A-17), `StructureDef.launch_pad` (A-19);
  `quality_tiers.json` and its schema come from TA-47 (A-22, Haiku), before TA-31.
- `BotProfileDef`, `AutopilotDef`, `BuildOrderDef`, `MedalDef`, `QualityTierDef`, `OrderRulesDef`, `AssistDef`,
  `ProgressionDef` are thin (id / tags / `raw`); typed fields are appends when sim_ai / ui / TA-31 name them. `MapDef` is id + `raw`.
- Open: the mod-pack loader is a stub (see Public API). `doctrines.json` (GD-07) ships vanguard, bulwark, foundry; `flip_cooldown_s_override` applies to all ships as 02 s7 states.
- Open: N5 (mesh paths exist in the export) stays with `validate_scenes.gd`; the loader does not check files.
- TA-27: `tools/gen_module_api.py --check` must cover this file's Public API block once `content_db.gd` implements it.
- `godot/src/content/` has no `class_name` on `ContentDB` by design; 03 s15.3 draft wrote `class_name ContentDB`,
  which this file corrects (autoload rule).
