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
| Status | implemented (TA-19, 2026-10-14); `EconomyHub` calls `step` from `SimWorld` step 10; power effects, moving sun and Plateau seam GD-13 (2026-10-15). Planned: maps carry no Plateau data yet, so `set_plateaus` is never fed by the loader and the Plateau multiplier is dormant in matches |

## Public API

```gdscript
class_name Economy extends RefCounted
enum Pay { OK, LOCKED, SHORT }                                               # try_pay outcomes
func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, hz: int, events: SimEvents, build: Build)
static func solar_factor(up: Vector3, sun_dir: Vector3, on_plateau: bool, band_deg: float, plateau_mult: float) -> float   # 02 s8.4
static func harvest_trip_time(d: float, def: GroundUnitDef) -> float          # 02 s8.2, without the dock queue wait
func power_ratio(team: int) -> float;  func stockpile(team: int) -> Vector2i;  func caps(team: int) -> Vector2i   # x Ore, y Ice
func try_spend(team: int, ore: int, ice: int) -> bool                        # all or nothing
func credit(team: int, ore: int, ice: int, player: int = -1) -> void         # clamps to caps, STORAGE_FULL once per crossing (re-armed when the pool is below the cap); player >= 0 books `Build.delivered_ore`
func try_pay(player: int, ore: int, ice: int) -> Pay                         # SHORT (pool), LOCKED (early share lock), else spends and grows `Build.spent_ore`
func spend_locked(player: int, ore: int) -> bool                             # (GD-17) the early share lock would forbid `ore` more; auto-replenish checks it before queuing
func refund(player: int, ore: int, ice: int) -> void                         # credit + lowers `Build.spent_ore` (S12 cancels)
var sun_period_s: float                                                      # 0 = fixed sun +Z, > 0 moving (EconomyHub copies MatchRules.sun_period_s)
func set_clock(tick: int) -> void;  func set_plateaus(centres: PackedVector3Array) -> void   # moving-sun refresh clock; unit-vector Plateau centres (GD-13)
func production_speed(team: int) -> float                                    # max(production_min_speed, ratio)
func tower_rates() -> PackedFloat32Array                                     # per team: ratio, 0 below tower_offline_ratio; cache only (step 9 safe)
func shield_recharge_mult(team: int) -> float                                # ratio, 0 = dome down below tower_offline_ratio (GD-10 reads)
func mark_dirty() -> void;  func step() -> void                              # step 10: cache refresh, Core trickle
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # S4: caches, trickle remainder, notice flags
class_name SelfRepair extends RefCounted                                     # GD-16, 02 s6.3; EconomyHub.repair, run in step 10 after Economy
var unsupplied: PackedByteArray                                              # per entity slot, derived: GD-18 writes (empty = every structure supplied)
func _init(store: EntityStore, defs: WorldDefs, economy: Economy, hz: int)
func rate_hp_s(max_hp: float) -> float;  func step(tick: int) -> void   # whole sim seconds only
class_name SunPath extends RefCounted                                        # GD-13; GD-33 adds phase and the terminator crossing
static func dir_at(period_s: float, t_s: float) -> Vector3                   # +Z when period_s <= 0, else turning about X once per period from +Z
static func on_plateau(up: Vector3, centres: PackedVector3Array, radius_m: float) -> bool   # arc distance on the datum sphere
```

Constants come from `economy.json` (`core_trickle_ore_per_s`, `solar_band_deg`, `solar_plateau_mult`, `early_share_*`, ...).

## Invariants

- E1 Pools never exceed the caps through `credit` and never go negative through `try_spend` / `try_pay`; a failed spend changes nothing.
- E2 `power_ratio(team) = min(1, supply / demand)`, 1 at zero demand; supply and demand are the signed `power` of the team's finished structures, a Solar Array scaled by `solar_factor` (sun from `SunPath`: fixed +Z, or turning about X once per `sun_period_s` with the solar factor re-read each sim second; Plateau multiplier where `set_plateaus` says). `LOW_POWER` (event + ALERT) fires once per drop below 1.
- E2a Effects (02 s8.4): production speed `max(production_min_speed, ratio)`; tower rate = ratio, 0 below `tower_offline_ratio` (SimWorld hands `tower_rates()` to `WeaponFire.tower_power` before step 9); Shield Projector recharge = ratio, dome down below it; construction is never scaled. The moving sun adds no state: it derives from the tick. A refresh at any other moment (a structure change mid-second) uses the sun of the current tick, and the solar factor is otherwise re-read only on whole sim seconds. `tower_rates()` returns a per-call-refilled buffer that `WeaponFire.tower_power` shares by copy-on-write (read-only for the fire pass, never state).
- E3 Caps, power and Core counts are cached and refresh when the live-structure count changes and on `mark_dirty` (BUILD_DONE, deaths), at the start of `step` or on the first read. The cache is saved, so a restored world refreshes on the same ticks (S4).
- E4 The Core trickle is `core_trickle_ore_per_s` per finished Core to its owner, accumulated in Ore-ticks (exact for whole rates), credited through `credit` (so the cap clamps it and the ledger counts it).
- E5 The early share lock has one definition, `Build.lock_blocks`; `try_pay` consults it, so BUILD starts, PRODUCE starts and `can_place` agree.
- E6 `add_player` adds `start_ore` / `start_ice` per player to the team pool (C2-14).
- E7 Self-repair (GD-16): a finished, supplied structure with `tick - last_damage_tick >= self_repair_delay_s` heals `min(missing, max(self_repair_min_hp_s, self_repair_frac_per_s * hp))` (A-80) HP on each whole sim second and pays `ceil(missing * repair_ore_per_hp) - ceil((missing - heal) * repair_ore_per_hp)` Ore through `try_spend` (a whole repair costs `ceil(total HP * repair_ore_per_hp)`, never more); an unpayable second is skipped (pause). Sites, dead and unsupplied structures never repair. No accumulator and no saved state: the result is a function of the store and the tick (S4).

## Data owned

Per team: power ratio, Ore / Ice caps, notice flags. Per player slot: finished Core count, trickle remainder. The pools themselves are `PlayerTable`'s.

## Events emitted / consumed

Emits LOW_POWER, ALERT (LOW_POWER, STORAGE_FULL). Consumes nothing; `Construction` and `Production` call `try_pay` / `refund`.

## Performance budget

03 s4.2 row "economy" 0.8 ms p95: a no-op between refreshes (array reads for 8 players); the refresh is O(structures) when the structure set changes.

## Test entry points

`godot/test/unit/sim/economy/test_economy.gd`: start kit, per-player start Ore, pay / refund / ledger, early share lock, caps clamp, power ratio, solar factor, trip time, trickle, determinism.
`godot/test/unit/sim/economy/test_power.gd` (GD-13): solar factor at -1 / 0 / +0.25 / +1 degrees and on the Plateau, sun path, fade at night, ratio math, tower / shield rates, C-12, LOW_POWER wire, S4 + determinism with a moving sun.
`godot/test/unit/sim/economy/test_self_repair.gd` (GD-16): rate floor, delay, Ore payment, hit restarts the delay, pause without Ore, unsupplied / site exclusions, S4 + determinism.
`godot/test/unit/sim/economy/test_stockpiles.gd` (GD-11): caps, 60 Ore/min trickle, try_spend atomicity, STORAGE_FULL once per crossing, S4 flags, determinism, EventCodec round trip of the alert.
