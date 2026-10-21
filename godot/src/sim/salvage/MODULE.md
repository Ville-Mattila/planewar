# sim/salvage - MODULE.md

Contract for `godot/src/sim/salvage/**`: wrecks, salvage pods, tow slots and delivery credit (GD-19; 02 s13, 03 s5.7, R0
B.1 `economy.json`, R0 C3-17; A-21 split of `sim/MODULE.md`). A change to "Public API" or "Invariants" is a contract
change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | A dying ship, ground unit or finished structure leaves wrecks worth `wreck_fraction` of its Ore cost: one wreck for a unit, `ceil(value / salvage_pod_max_ore)` pods for a structure or the Core. A wreck lives `wreck_lifetime_s`, is hooked by a Hauler within tether reach (at most its `tow_slots`; Foundry 2) and is turned into Ore when its Hauler reaches a friendly Refinery. Not here: the tether follow motion, the 25 m / 8 m geometry, the towing turn-rate cap and "no collision while towed" (GD-37), path weights under wrecks, scoring points for salvage (GD-26), completing the HAUL order (the Hauler brain does, from SALVAGE_DELIVERED). |
| Lane owner tier | Sonnet against this file (Opus review) |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/`: `WorldDefs`, `SimEvents`; `sim/orders/` `OrderQueue`; `sim/economy/` `Economy`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (GD-19, 2026-10-21); `EconomyHub.on_death` spawns, `EconomyHub.step` runs `step` after production. No saved state of its own (W9): `SimSerialize.FORMAT` is unchanged |

## Public API

```gdscript
class_name Salvage extends RefCounted
enum Hook { OK, NOT_HAULER, NO_SLOT, BAD_WRECK, TOO_FAR }                    # try_attach outcomes
const CAUSE_EXPIRED: int                                                     # DEATH cause of an expired wreck: 1 (0 is DEBUG)
var orders: OrderQueue                                                       # set by SimWorld; the head standing order of a ship decides the auto-hook
var cap: int                                                                 # live wreck cap (`caps.wrecks`; 0 = the whole wreck range)
func _init(store: EntityStore, defs: WorldDefs, economy: Economy, events: SimEvents, terrain: Terrain, hz: int, wreck_cap: int)
static func value_of(defs: WorldDefs, def_id: int) -> int                    # W1: Ore value of the wrecks a def leaves (0 = none)
static func pods_of(value: int, pod_max: int) -> int                        # W2: ceil(value / pod_max), at least 1
static func pod_value(value: int, pods: int, i: int) -> int                  # W2: share of pod i (integers, differ by <= 1, sum = value)
func reach_m() -> float                                                      # W6: tether_len_m + tether_drop_m
func on_death(s: int, tick: int) -> int                                      # step 9, before the deferred free of slot `s`: spawns its wrecks, returns how many
func step(t: int) -> void                                                    # step 10: expiry, release, delivery, then the auto-hook
func towed_count(hauler: int) -> int                                         # wrecks whose link is this ship (slot) and flagged TETHERED
func tow_slots_of(hauler: int) -> int                                        # resolved ShipDef.tow_slots of a live ship slot, else 0
func try_attach(hauler: int, wreck: int) -> Hook                             # slots; sets link and F_TETHERED on both
func drop(hauler: int) -> int                                                # releases every wreck of the ship, returns the count
```

Constants come from `economy.json` (`wreck_fraction`, `wreck_lifetime_s`, `salvage_pod_max_ore`), `match_rules.json`
(`core_value`, `caps.wrecks`), `flight_common` (`tether_len_m`, `tether_drop_m`) and `ships.json` (`tow_slots`, resolved
per owner so the Foundry doctrine gives 2). Slots in the API are entity slots; `store.link` holds an EntityId.

## Invariants

- W1 Value. `value_of(def)` = `roundi(wreck_fraction x base Ore cost)` from the undoctrined defs (a Foundry unit leaves
  the same wreck as a Vanguard one); the Core (a structure with an `integrated_shield` and no Ore cost) uses
  `match_rules.core_value`; a def with no base value (Relay Station) leaves nothing. 02 s13 table: Dart 60, Lancer 120,
  Bomber 180, Scout 24, Hauler 80, Harvester 100, Siege Crawler 180, Pad 60, Autocannon 80, Flak 120, Missile Tower 140,
  Refinery 120, Shipyard 160, Outpost 180, Core 800. A site (`F_BUILDING`) and a wreck leave nothing.
- W2 Pods. A ship or ground unit leaves one wreck of the whole value. A structure leaves `pods_of(value)` pods
  (`ceil(value / salvage_pod_max_ore)`); pod i is worth `value / n` rounded down, plus 1 for the first `value mod n` pods:
  Shipyard 80 + 80, Outpost 90 + 90, Core 7 pods (two of 115, five of 114), a 120 Ore structure one pod.
- W3 The wreck. Created in step 9 of the tick the owner dies: kind WRECK, ALIVE, `def_id` = the source def, owner and
  team 255 (neutral), `hp` = the pod value in Ore, `spawn_tick` = the death tick, `radius` = source radius / pods, resting
  on the terrain surface under the death point (a flying ship's wreck is on the ground); several pods sit on a ring of
  radius 0.5 x the source radius around it, pod 0 first. WRECK_SPAWNED(a = wreck id, b = source def, value = pod Ore) per
  wreck, in pod order, emitted in step 9 before the dying entity's own RELEASED (C15) and DEATH. The wreck's `hash_cell` is 0 until the next step 7.
- W4 Lifetime. In step 10 of tick `spawn_tick + roundi(wreck_lifetime_s x tick_hz)` (90 s = 2,700 ticks at 30 Hz) the
  wreck is freed with DEATH(a = wreck id, b = 0, cause `CAUSE_EXPIRED`), towed or not; a tether on it ends with it.
- W5 Cap. At `cap` live wrecks no further wreck is created (no event); pods that do not fit are lost. A full wreck range
  (256 slots, quarantine included) behaves the same.
- W6 Tow slots and hook. A ship tows at most its resolved `tow_slots` (Hauler 1; Foundry sets 2; other ships 0).
  `try_attach(h, w)` returns OK and links when: h is a live ship, not DOCKED, below its slots; w is a live, free wreck;
  `|pos_h - pos_w| <= reach_m()`. It sets `link[w]` = h's EntityId, F_TETHERED on both and DIRTY_CONTROL; the failure
  order is NOT_HAULER, NO_SLOT, BAD_WRECK, TOO_FAR and a failure changes nothing. Step 10 hooks, for each live ship whose
  head standing order is HAUL with `HaulMode.TOW` and a free slot: the order's target first (when a wreck in reach), then,
  only while the ship already tows at least one wreck, the other free wrecks in reach in ascending slot order until its
  slots are full. A ship without such an order never hooks by itself. A tow never changes the wreck's position here (GD-37).
- W7 Release. In step 10 a wreck whose hauler is dead (or no longer a ship) is released: `link` 0, F_TETHERED off, the
  wreck stays where it is. A ship carries F_TETHERED exactly while `towed_count >= 1` (refreshed in the same pass after a
  release, delivery or expiry, and by `drop`). `drop(h)` releases all of h's wrecks.
- W8 Delivery. In step 10 a towed wreck whose hauler is within `radius(refinery) + reach_m()` (centre distance) of a
  finished (not a site) living structure of the hauler's team whose def has `docks > 0` (the Refinery) is delivered:
  `Economy.credit(team, round(hp), 0, owner of the hauler)` (so the cap clamps and the Ore ledger counts it),
  WRECK_SALVAGED(a = wreck id, b = hauler id, value = Ore) then SALVAGE_DELIVERED(a = hauler id, b = refinery id,
  value = Ore) with the hauler's team, and the wreck is freed without a DEATH. The Ore is the value, whatever the clamp
  kept. Wrecks are processed in ascending slot order.
- W9 State. Salvage keeps no saved state: everything is in `EntityStore` (`link`, `flags`, `hp`, `spawn_tick`), so a
  save / restore / continue at any tick of a wreck's life is byte-exact (S4) and expiry lands on the same tick. The
  Refinery list it caches is derived (rebuilt when `Economy.structure_epoch` or the structure count moves) and never saved.
- W10 Cost. `step` returns at once while no wreck lives; otherwise one pass over the wreck list plus one over the ships
  for the byte compare `order_kind == HAUL`; no Dictionary, no per-entity allocation.

## Data owned

Nothing of its own (W9): scratch lists `_gone`, `_touched`, the derived Refinery list and one `OrderSpec`.

## Events emitted / consumed

Emits WRECK_SPAWNED (19), WRECK_SALVAGED (20), SALVAGE_DELIVERED (28) and DEATH (1) with cause 1 for an expired wreck.
Consumes nothing.

## Performance budget

03 s4.2 row 10 (economy / production / build; the Economy row of `TickProfiler`, budget 0.8 ms). `step` is free while no wreck
exists (0.15 us). With 200 live wrecks (the Standard cap), 16 of them towed by 8 Foundry Haulers and 8 more Haulers holding a
TOW order: 62 us per `step` on a dev laptop, debug build (`test_salvage_perf.gd`, bound 200 us, PerfGate). `perf_tick.gd --full`
(120 idle wrecks): Economy row p50 0.029 -> 0.072 ms, p95 0.132 -> 0.217 ms (before / after this change).

## Test entry points

`godot/test/unit/sim/salvage/test_salvage_values.gd` (W1, W2, W3: the 02 s13 table, pod split, Shipyard 2 x 80, Core 7
pods, Foundry-independent value, sites and Relay Station leave nothing, ground placement, WRECK_SPAWNED fields),
`test_salvage_life.gd` (W4, W5: expiry at tick 2,700 exactly, DEATH cause, cap),
`test_salvage_tow.gd` (W6, W7, W8: slots 1 / 2, hook order and reach, auto-hook by order, release on death, delivery
credit, cap clamp, events, no hook without order),
`test_salvage_state.gd` (W9: save / restore / continue byte-exact mid-lifetime and mid-tow, FORMAT unchanged, refusal of a
changed FORMAT), `test_salvage_perf.gd` (W10 counters; PerfGate).

## How to add X (recipes for the cheapest tier)

- **A new wreck source:** nothing; any def with a base Ore cost leaves a wreck through `EconomyHub.on_death`.
- **The tether follow (GD-37):** move the wreck in step 5; where the tow state lives (`link[wreck]` here vs the R0 C3-17 `tether_target` side table) is pending the GD-19 Architect ruling.

## Open items

- Contract questions for the Architect (GD-19 PR): the attach and delivery radii are derived from `tether_len_m +
  tether_drop_m` (no explicit field in R0 B.1); a possessed Hauler has no hook trigger (no `PilotInput` button, no order);
  `SimView` has no accessor for a wreck's Ore value (`hp01` of a wreck is not meaningful); `DEATH` cause 1 is new.
