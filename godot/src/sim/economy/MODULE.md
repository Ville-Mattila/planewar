# sim/economy - MODULE.md

Contract for `godot/src/sim/economy/**`: the economy core of tick-order step 10 (TA-19; 02 s8; R0 C2-14, C3-08;
A-21 split of `sim/MODULE.md`). A change to "Public API" or "Invariants" is a contract change: contract tests first,
same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | The team pools (`PlayerTable.team_ore` / `team_ice`), storage caps (sum of `storage_ore` / `storage_ice`), power ratio, payment (`try_pay`) with the early share lock, refunds, credit with the cap clamp, the Core trickle, and the LOW_POWER / STORAGE_FULL notices. Not here: Harvester cycles, Refinery docks, Extractors, salvage and the Core shield (GD-xx; `credit(..., player)` is their seam), placement (`sim/build/`), queues (`sim/production/`). |
| Lane owner tier | Sonnet against this file (Opus review) |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/`: `WorldDefs`, `PlayerTable`, `SimEvents`, `StateIO`; `sim/build/` `Build` for the ledgers) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (TA-19, 2026-10-14); `EconomyHub` calls `step` from `SimWorld` step 10 |

## Public API

```gdscript
class_name Economy extends RefCounted
enum Pay { OK, LOCKED, SHORT }                                               # try_pay outcomes
func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, hz: int, events: SimEvents, build: Build)
static func solar_factor(up: Vector3, sun_dir: Vector3, on_plateau: bool, band_deg: float, plateau_mult: float) -> float   # 02 s8.4
static func harvest_trip_time(d: float, def: GroundUnitDef) -> float          # 02 s8.2, without the dock queue wait
func power_ratio(team: int) -> float;  func stockpile(team: int) -> Vector2i;  func caps(team: int) -> Vector2i   # x Ore, y Ice
func try_spend(team: int, ore: int, ice: int) -> bool                        # all or nothing
func credit(team: int, ore: int, ice: int, player: int = -1) -> void         # clamps to caps, STORAGE_FULL once per episode; player >= 0 books `Build.delivered_ore`
func try_pay(player: int, ore: int, ice: int) -> Pay                         # SHORT (pool), LOCKED (early share lock), else spends and grows `Build.spent_ore`
func refund(player: int, ore: int, ice: int) -> void                         # credit + lowers `Build.spent_ore` (S12 cancels)
func mark_dirty() -> void;  func step() -> void                              # step 10: cache refresh, Core trickle
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # S4: caches, trickle remainder, notice flags
```

Constants come from `economy.json` (`core_trickle_ore_per_s`, `solar_band_deg`, `solar_plateau_mult`, `early_share_*`, ...).

## Invariants

- E1 Pools never exceed the caps through `credit` and never go negative through `try_spend` / `try_pay`; a failed spend changes nothing.
- E2 `power_ratio(team) = min(1, supply / demand)`, 1 at zero demand; supply and demand are the signed `power` of the team's finished structures, a Solar Array scaled by `solar_factor` (fixed sun +Z, no Plateau yet). `LOW_POWER` (event + ALERT) fires once per drop below 1.
- E3 Caps, power and Core counts are cached and refresh when the live-structure count changes and on `mark_dirty` (BUILD_DONE, deaths), at the start of `step` or on the first read. The cache is saved, so a restored world refreshes on the same ticks (S4).
- E4 The Core trickle is `core_trickle_ore_per_s` per finished Core to its owner, accumulated in Ore-ticks (exact for whole rates), credited through `credit` (so the cap clamps it and the ledger counts it).
- E5 The early share lock has one definition, `Build.lock_blocks`; `try_pay` consults it, so BUILD starts, PRODUCE starts and `can_place` agree.
- E6 `add_player` adds `start_ore` / `start_ice` per player to the team pool (C2-14).

## Data owned

Per team: power ratio, Ore / Ice caps, notice flags. Per player slot: finished Core count, trickle remainder. The pools themselves are `PlayerTable`'s.

## Events emitted / consumed

Emits LOW_POWER, ALERT (LOW_POWER, STORAGE_FULL). Consumes nothing; `Construction` and `Production` call `try_pay` / `refund`.

## Performance budget

03 s4.2 row "economy" 0.8 ms p95: a no-op between refreshes (array reads for 8 players); the refresh is O(structures) when the structure set changes.

## Test entry points

`godot/test/unit/sim/economy/test_economy.gd`: start kit, per-player start Ore, pay / refund / ledger, early share lock, caps clamp, power ratio, solar factor, trip time, trickle, determinism.
