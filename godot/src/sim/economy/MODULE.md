# sim/economy - MODULE.md

Contract for `godot/src/sim/economy/**`: the economy core of tick-order step 10 (TA-19; 02 s8; R0 C2-14, C3-08;
A-21 split of `sim/MODULE.md`). A change to "Public API" or "Invariants" is a contract change: contract tests first,
same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | The team pools (`PlayerTable.team_ore` / `team_ice`), storage caps (sum of `storage_ore` / `storage_ice`), power ratio, payment (`try_pay`) with the early share lock, refunds, credit with the cap clamp, the Core trickle, and the LOW_POWER / STORAGE_FULL notices. The supply network (`SupplyNet`: Pylon graph, supplied flags, tower ammo refill; GD-18). Not here: Harvester cycles, Refinery docks, Extractors and salvage (GD-xx; `credit(..., player)` is their seam); the shield domes and the Core shield are `sim/combat/` `ShieldDomes` (GD-10), which reads `shield_recharge_mult`, `tower_rates`, `try_spend`, `structure_epoch` and `SupplyNet.is_supplied`, placement (`sim/build/`), queues (`sim/production/`). |
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
var structure_epoch: int                                                     # (GD-18) counts mark_dirty calls; derived, not state
func mark_dirty() -> void;  func step() -> void                              # step 10: cache refresh, Core trickle
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # S4: caches, trickle remainder, notice flags
class_name SelfRepair extends RefCounted                                     # GD-16, 02 s6.3; EconomyHub.repair, run in step 10 after Economy
var unsupplied: PackedByteArray                                              # per entity slot, derived: `EconomyHub` copies `SupplyNet.unsupplied` in before each repair pass (empty = every structure supplied)
func _init(store: EntityStore, defs: WorldDefs, economy: Economy, hz: int)
func rate_hp_s(max_hp: float) -> float;  func step(tick: int) -> void   # whole sim seconds only
class_name SupplyNet extends RefCounted                                      # GD-18, 02 s5.4; EconomyHub.supply, run in step 10 before SelfRepair
var unsupplied: PackedByteArray                                              # per entity slot: 1 = finished structure outside the network (derived, sized InputSlots.ENTITY_SLOTS)
var rebuilds: int                                                            # full graph rebuilds so far (diagnostic)
var refill: bool                                                             # false stops the tower refill (test fixtures)
func _init(store: EntityStore, defs: WorldDefs, hz: int)
func step(tick: int, epoch: int) -> void                                     # rebuild when `epoch` (Economy.structure_epoch) or the structure count moved, then refill supplied towers
func is_supplied(slot: int) -> bool                                          # unsupplied[slot] == 0
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
- E8 Supply network (GD-18, 02 s5.4): roots are finished, living Cores and Outposts; a finished Relay Pylon links when its centre is within its team's connected node's `build_radius` (great-circle on the datum sphere, `dot >= cos(r / R)`, node radius from the owner's resolved def). A finished structure is supplied when a connected node of its team covers its centre (a root or linked Pylon covers itself; a teammate's network counts, an enemy's never). Sites and dead structures are never nodes and read 0. `unsupplied` is derived from the store, never saved (S4); `SimWorld` copies it into `fire.unsupplied` (saved with Combat, the same bytes) each step 10, so the cut shows in the fire pass of the next tick.
- E9 Updates run in step 10 only when `Economy.structure_epoch` moved (every `mark_dirty`: BUILD_DONE, deaths, start kit) or the structure count changed. The finished live structures are diffed against the last pass: a node (Core, Outpost, Pylon) added or removed rebuilds the graph (nodes sorted by team and x, band search; ~1.0 ms at the 02 s5.4 limit of 296 nodes + 504 structures), a consumer added or removed only evaluates or clears its own flag (~0.1 ms). So a Pylon killed in step 9 unsupplies its downstream on that tick's step 10. Contract: any code that changes a structure finished state, team, owner or position (capture, sell, relocation, tests) must call `Economy.mark_dirty` itself and, if it changes a node, do so for the node; an in-place change that keeps entity id and finished state is not seen.
- E10 Refill: a supplied, finished tower gains `floor(m (t + 1) / (hz 1000)) - floor(m t / (hz 1000))` rounds on tick `t` (m = `ammo_refill_per_s` x 1000 rounded), capped at `ammo_pool`; unsupplied towers keep their pool and never refill. No accumulator. Unsupplied towers fire at `economy.unsupplied_rate_mult` (WeaponFire), the Shield Projector reads `is_supplied` (GD-10), `SelfRepair` skips unsupplied structures. `SimView.supply01(id)` = tower `ammo / ammo_pool` (0 for sites, non-towers, dead ids).

## Data owned

Per team: power ratio, Ore / Ice caps, notice flags. Per player slot: finished Core count, trickle remainder. The pools themselves are `PlayerTable`'s.

## Events emitted / consumed

Emits LOW_POWER, ALERT (LOW_POWER, STORAGE_FULL). Consumes nothing; `Construction` and `Production` call `try_pay` / `refund`.

## Performance budget

03 s4.2 row "economy" 0.8 ms p95: a no-op between refreshes (array reads for 8 players); the refresh is O(structures) when the structure set changes. GD-18 adds the tower refill per tick (supplied towers only, ~50 us at 140 towers), a change diff (~90 us at 504 structures) when the structure set changes and a node rebuild (~1.0 ms at the limit) when a node changes (bench_supply.gd).

## Test entry points

`godot/test/unit/sim/economy/test_supply_net.gd` (GD-18): root radius, Pylon chain, mid-chain cut on the next tick, root loss and relink, sites do not link, lone Pylon, Outpost root, teammate / enemy, refill to the pool and exact fractional ticks, unsupplied no refill and half rate, rebuild only on change, S4 + determinism.
`godot/test/unit/sim/economy/test_economy.gd`: start kit, per-player start Ore, pay / refund / ledger, early share lock, caps clamp, power ratio, solar factor, trip time, trickle, determinism.
`godot/test/unit/sim/economy/test_power.gd` (GD-13): solar factor at -1 / 0 / +0.25 / +1 degrees and on the Plateau, sun path, fade at night, ratio math, tower / shield rates, C-12, LOW_POWER wire, S4 + determinism with a moving sun.
`godot/test/unit/sim/economy/test_self_repair.gd` (GD-16): rate floor, delay, Ore payment, hit restarts the delay, pause without Ore, unsupplied / site exclusions, S4 + determinism.
`godot/test/unit/sim/economy/test_stockpiles.gd` (GD-11): caps, 60 Ore/min trickle, try_spend atomicity, STORAGE_FULL once per crossing, S4 flags, determinism, EventCodec round trip of the alert.
