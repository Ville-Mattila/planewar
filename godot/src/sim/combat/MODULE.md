# sim/combat - MODULE.md

Contract for `godot/src/sim/combat/**`: tick-order step 9 weapon fire (02 s4.4 fire pipeline, R0 C2-23; GD-36) and damage,
the rules of 02 s4.3 (GD-08; R0 B.5 tick order; B.9 A-3, A-30). R0 B.9 A-21 split of `sim/MODULE.md`, which stays the home of every type other lanes may name (`SimEvent.Kind`
ordinals, `EntityStore`, Collision contacts). A change to "Public API" or "Invariants" is a contract change: contract tests
first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Weapon fire (GD-36): rate of fire on the tick grid, bursts, salvos and reloads, ammo / bomb / rocket draw, the unsupplied-tower rate, lock acquisition, spread, projectile spawn. Then the Contact records of step 8 become hit-point changes: the gun roll and structure / ground multipliers (rule 1), bomb kill radius, blast and Hangar immunity (2-3), rockets (4), flak (5), siege-shell blast, ramming (7), no friendly fire (8), HIT / BOMB_IMPACT / LOCK_ACQUIRED / LOCK_BROKEN events and the deferred-death marks. Then the fuses (rocket proximity, flak timed and early burst). Does not own tower aim, envelopes, AGL floor, flip lock break, in-flight lock loss or target priority (GD-09), the supply graph and refill (GD-18), power-ratio rate scaling (GD-13), shield domes (GD-10), terrain or landing damage (Docking, GD-15), Reactor explosions, wrecks or scoring. |
| Lane owner tier | Opus (sim lane); Sonnet for recipes against this file |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/`: `WorldDefs`, `SimEvents`, `CommandApplier`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads (D2, D3) |
| Autoloads used | None |
| Status | implemented (GD-08, 2026-10-14; GD-36 weapon fire and fuses, 2026-10-14) |

## Public API

Lane-internal: `SimWorld` composes one `Combat`; other lanes see its effects through `SimView` HP and the events. Not in
`tools/deps.json` named types.

```gdscript
class_name Combat extends RefCounted                                         # step 9; one per SimWorld
var fire: WeaponFire                                                         # GD-36; GD-18 writes fire.unsupplied
func step(tick: int, dice: Rng) -> void                                      # fire, then HIT / GROUND / RAM contacts in contact order, then fuses
func forget(s: int) -> void;  func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # every death of the tick; S4 bytes (fire state)
func detonate_bomb(pos: Vector3, owner_team: int, w: WeaponDef, p: ProjectileDef, attacker: int, tick: int, dice: Rng) -> void   # rules 2-3, as a fuse would fire it
static func roll_gun_damage(w: WeaponDef, target_kind: int, dice: Rng, extra_mult: float = 1.0) -> int   # rule 1; target_kind is EntityStore.K_*
class_name WeaponFire extends RefCounted                                     # GD-36 fire pipeline, run first in Combat.step
var lock_target: PackedInt32Array; var lock_time: PackedFloat32Array; var unsupplied: PackedByteArray   # per main-range slot; serialized
var tower_power: PackedFloat32Array                                          # GD-13: per team tower rate multiplier (0 = offline); set by SimWorld each tick, not state
func step(tick: int, dice: Rng) -> void;  func forget(s: int) -> void
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
class_name SeekerScan extends RefCounted                                     # lane-internal seeker scans (A-73 extraction from WeaponFire)
static func pick(store: EntityStore, pos: PackedVector3Array, tm: PackedByteArray, s: int, f: Vector3, mask: int, r2: float, cone: float) -> int
static func score(pos: PackedVector3Array, tm: PackedByteArray, s: int, f: Vector3, t: int, r2: float, cone: float) -> float
class_name FireTables extends RefCounted                                     # WeaponFire's flat tables: by def_id, by weapon, rows [owner * weapon_count + weapon]
const ALL_KINDS: int;  var prim: PackedInt32Array; var sec: PackedInt32Array; var mask: PackedByteArray; var tower: PackedByteArray
var w_kind: PackedByteArray; var w_proj: PackedInt32Array; var weapon_count: int; var bound: Array[ResolvedDefs]
var interval: PackedFloat64Array; var lock_s: PackedFloat64Array; var burst_n: PackedInt32Array; var burst_s: PackedFloat64Array; var shot_s: PackedFloat64Array
var salvo: PackedInt32Array; var cost: PackedInt32Array; var spread: PackedFloat64Array; var range2: PackedFloat64Array; var cone: PackedFloat64Array
var p_speed: PackedFloat64Array; var p_life: PackedFloat64Array; var p_eject: PackedFloat64Array
func bind(o: int, r: ResolvedDefs) -> bool                                   # copies owner o's resolved numbers; false when already bound
static func aim(fwd: Vector3, up: Vector3, spread_deg: float, dice: Rng) -> Vector3   # two range_f draws when spread_deg > 0
static func fuse_ticks(rel_p: Vector3, rel_v: Vector3, pd: ProjectileDef, hz: int, delay_s: float) -> int   # flak closest approach + delay, clamped
static func cone_cos(cone_deg: float) -> float                               # full apex angle -> half-angle cosine; 0 / 360 -> -1
class_name Blast extends RefCounted                                          # area rules: bomb, flak, siege shell
var friendly_fire: bool
func bomb(pos: Vector3, owner_team: int, attacker: int, w: WeaponDef, p: ProjectileDef, rng: Rng, tick: int) -> void
func flak(pos: Vector3, owner_team: int, attacker: int, w: WeaponDef, p: ProjectileDef, rng: Rng, tick: int) -> void
func shell(pos: Vector3, owner_team: int, attacker: int, w: WeaponDef, p: ProjectileDef, rng: Rng, tick: int) -> void
func hangar_docked(s: int) -> bool;  func bomb_mult(s: int, tick: int) -> float;  func edge_distance(pos: Vector3, s: int) -> float
static func rect_distance(rel: Vector3, fwd: Vector3, up: Vector3, hw: float, hh: float) -> float
class_name DamageSink extends RefCounted                                     # the one place HP changes
func standing(s: int) -> bool;  func damage(s: int, amount: float, attacker: int, tick: int) -> bool;  func destroy(s: int, attacker: int, tick: int) -> bool
```

## Invariants

- CB1: every random draw is on `SimWorld.rng` (S7), no fork, no other source: first the fire pass's spread (two `range_f` per projectile whose weapon has `spread_deg > 0`, in ships / ground / structures live-list order; none for a refused shot), then `Combat.roll_gun_damage`, one `range_i` per hit whose weapon has `damage_min < damage_max`, in Contact order and then fuse order; point ranges (bomb 400, rocket 40, rail 250, siege 120) draw nothing.
- CB2: weapons are the owner's doctrine-resolved defs (`WorldDefs.resolved(owner)`), indexed by the projectile's `weapon_def`; Combat applies no doctrine factor of its own (02 s4.3 rule 1, s7), so Foundry's x0.85 reaches ship mounts only (A-3).
- CB3: gun damage = `max(round(roll * mult), 1)` with `structure_mult` vs structures, `ground_mult` vs ground units, 1.0 vs ships; bomb damage to a structure also carries `bomb_mult` (roofed pad 0.25, Core after Exposure `core_bomb_mult_exposure`) inside the same single rounding.
- CB4: a ship whose bounding sphere is within `blast_radius_m` of a bomb detonation is destroyed (no HP arithmetic) unless it is DOCKED with `link` a live roofed-pad structure (Hangar). Ground units and structures use `blast_radius_structure_m`; structures by distance to the footprint rectangle (`footprint[0]` cells along `fwd x up`, `footprint[1]` along `fwd`, cell = `PLANET_RADIUS * PI / 2 / GRID_BUILD`). No falloff.
- CB5: nothing hostile is spared and nothing friendly is hurt: a projectile or blast never damages an entity of the shooter's team unless `MatchRules.friendly_fire`; ramming ignores teams. Wrecks take no damage.
- CB6: a projectile with a HIT contact acts only once armed (`lifetime_s - ttl >= arm_s` or `F_ARMED`); an unarmed one flies on. A GROUND contact always detonates (terrain cannot be passed). A consumed projectile is freed in the same step.
- CB7: a ship-ship RAM destroys both; a ship-structure RAM destroys the ship and deals its remaining HP to the structure; either already at 0 HP this tick is skipped. Invulnerable structures take nothing.
- CB8: `DamageSink` is idempotent on a 0-HP entity (two blasts in one tick never double-kill); HIT carries the rolled value (overkill included), a lethal hit or outright kill calls `CommandApplier.kill` for the end-of-step free.
- CB9: allocation-free per entity: no Dictionary / Array built in a per-entity loop; area queries allocate one `PackedInt32Array` per detonation (rare); the fire pass swaps the cooldown / ammo / dirty arrays out of the store for its writes, reads defs through `FireTables` rows and spawns through `ProjectileStore.spawn`, so no pool array is copied per shot.
- CB10 (rate): a weapon is due when its cooldown is within half a tick of 0; firing adds `1 / rof` (or `reload_s` after a `salvo`), keeping the remainder, so a Dart fires every 3 ticks (10 rps) and `gun_turret` shots fall 2-3 ticks apart with exactly 10 ticks per 4 spacings; a weapon at rest (cooldown 0) fires at once and a released or blocked trigger banks nothing. At most one shot (or salvo) per weapon per tick.
- CB11 (ammo): each projectile spends `ammo_per_shot` from `ammo` (ship primary, tower pool, ground unit) or `bombs` / `rockets` (ship secondary, by the weapon's kind); with too few rounds, or a full pool (rung 3), nothing spawns, nothing is spent and nothing is drawn. Spawn loads the doctrine-resolved counts (`CommandApplier` load-out). DOCKED ships and BUILDING structures never fire.
- CB12a (power, GD-13): a tower fires at `tower_power[team]` times its rate (02 s8.4); 0 (ratio below `tower_offline_ratio`) fires nothing and its cooldown holds.
- CB12 (burst, supply): a `burst` weapon fires up to `burst` rounds at `rof` in a window that reopens every `burst_interval_s` (5 rounds every 36 ticks for `gun_turret`); a tower with `fire.unsupplied` set runs every interval at 1 / `economy.unsupplied_rate_mult` (half the rounds per second).
- CB13 (lock): a weapon with `lock_time_s > 0` launches only at a target held, while the trigger is held, for `lock_time_s` (half-tick tolerance) inside `range_m`, the cone (`lock_cone_deg` = full apex angle; 0 or 360 = any direction), above the datum horizon, of a kind the mount may engage (towers: `target_kinds`; ships and ground units: ship, ground, structure), hostile and not neutral; losing it restarts the clock. LOCK_ACQUIRED (shooter, target) fires on the acquiring tick, LOCK_BROKEN when an acquired seeker lock is lost; a launched rocket carries the target and F_GUIDED.
- CB14 (fuses): after the contacts, an armed rocket whose sweep this tick passed within `fuse_radius_m` of its live target's bounding sphere bursts on that target only (rule 4); flak bursts at the tick in `ProjectileStore.target` (closest approach to the ship nearest its boresight + FLAK_FUSE_DELAY_S, clamped to [arm_s, lifetime - 1 tick]; end of life without a target) or, armed, within `fuse_radius_m` of a hostile ship's bounding sphere (rule 5). Fuses run over `ProjectileStore.live` in ascending order, a function of state alone (S4).

## Data owned

`WeaponFire.lock_target` / `lock_time` / `unsupplied` (per main-range slot, cleared by `forget` on death, serialized after Collision's state: `SimWorld` S4 format 4). Everything else lives in the stores: HP, `last_damage_tick`, `attacker`, `dirty`, `ammo`, `bombs`, `rockets`, `cd_primary` (shot or salvo cooldown), `cd_secondary` (secondary cooldown, or the burst window of a burst weapon) in `EntityStore`; the flak burst tick in `ProjectileStore.target`; the roll stream in `SimWorld.rng`. Also read: `ships.json` `primary` / `secondary`, `ground_units.json` `weapon` / `ammo`, `towers.json` `tower.weapon` / `ammo_pool` / `target_kinds`. Defs read: `weapons.json`, `projectiles.json`, `structures.json` (`footprint`, `pad_roofed`, `invulnerable`), `match_rules.json` (`core_bomb_mult_exposure`), doctrine `hangar_blocks_rockets`.

## Events emitted / consumed

Emits HIT (target, attacker, damage as value, target team), BOMB_IMPACT (attacker, -, position, kill radius as value, shooter team), LOCK_ACQUIRED and LOCK_BROKEN (shooter, target, target position, 0, shooter team); DEATH is `CommandApplier.resolve_deaths`'s. Reads the FIRE1 / FIRE2 bits of the input slots. Consumes Collision contacts C_HIT, C_GROUND, C_RAM; C_TERRAIN and C_PAD are Docking's / GD-15's.

## Performance budget

03 s4.2 row 9 (combat 1.2 ms p95 at 1,200 entities + 2,000 projectiles; "8 us per hit, 4 us per fire"). Cost: one pass over the armed entities' trigger bits plus the shots, the Contacts plus one `Spatial.ids_near` per area detonation, and one pass over the live projectiles for the fuses (ring-1 cells, no allocation, per armed flak shell). A seeker holding the trigger with no candidate scans its kind lists every tick (O(entities) per seeker: the human worst case; bots hold fire on a target); a flak aim scan runs only for a salvo that can leave. `perf_tick.gd --full` (harness 3) fires ~130 guns, the gun and flak towers and 8 idle seekers; numbers in the GD-36 PR.

## Test entry points

`godot/test/unit/sim/combat/test_combat_rules.gd` (CB1-CB3, roll distribution, doctrine fold), `godot/test/unit/sim/combat/test_combat_world.gd` (every rule through `SimWorld.step`, scenario C-09), `godot/test/unit/sim/combat/test_combat_determinism.gd` (CB1, S4 resume), `godot/test/unit/sim/combat/test_weapon_fire.gd` (CB10-CB13: 10 rps, ammo and empty, bombs, load-out, bursts, unsupplied 50 %, salvo, lock timing), `godot/test/unit/sim/combat/test_seeker_scan.gd` (SeekerScan score), `godot/test/unit/sim/combat/test_fuses.gd` (CB14), `godot/test/unit/sim/combat/test_fire_determinism.gd` (CB1 with spread, S4 mid-lock / mid-burst, fire-state bytes); fixtures `fire_test_kit.gd`.

## How to add X (recipes for the cheapest tier)

- **A projectile kind's effect:** add its `ProjectileStore` kind branch to `Combat._projectile` and an area method to `Blast`; test one rule per behaviour in `test_combat_world.gd`.
- **A weapon on a new mount:** give the def its weapon field and map it in `FireTables._init`; the fire pass needs no branch unless the projectile kind launches differently (`WeaponFire._shoot`).
- **A damage multiplier from data:** read it in `Blast.bomb_mult` (or `Combat.roll_gun_damage` for a weapon field); never type the number (ADR-09).

## Open items

- R0 B.12 (`docs/reviews/R0-amendments-05.md`): the def fields exist (`structures.structure_bomb_mult`, `projectiles.fuse_delay_s`, `economy.unsupplied_rate_mult`, A-66); TA-56 reads them through `WorldDefs` (`bomb_mult_by_def`, `fuse_delay_s`, `unsupplied_rate_mult`; absent = 1.0 / 0 / 1.0) and deleted `ROOF_BOMB_MULT`, `UNSUPPLIED_RATE_MULT`, `FLAK_FUSE_DELAY_S` and their `d6_allow.txt` entries. `needs content:` typed `StructureDef.structure_bomb_mult`, `ProjectileDef.fuse_delay_s`, `EconomyDef.unsupplied_rate_mult`, `RulesDef.vision_hz` fields; the sim reads `Def.raw` once at `WorldDefs._init` until then. Precedence (TA-56): a def `structure_bomb_mult` other than 1.0 wins over the Core's Exposure factor in `Blast.bomb_mult`; no shipped def sets it on the Core, so 02 s4.3 rule 3 is unaffected. A-74 ratified every GD-36 interpretation (burst tick in `target`, `ttl` = lifetime, `burst_interval_s` start-to-start, `lock_cone_deg` full apex, muzzle and velocity rules; 03 s3.3 corrected). A-75: a GROUND contact detonates unarmed (02 s4.3 rule 3); siege shells damage ships inside `blast_radius_m` (02 s4.3 rule 10); DEATH cause stays `DEATH_CAUSE_DEBUG` until GD-20 names causes.
- Tower aim and slew, envelopes, AGL floor, flip lock break, in-flight lock loss, target priority: GD-09. Supply graph and refill (writes `fire.unsupplied`): GD-18. Power-ratio scaling: GD-13. Shield domes (rule 6, `shield_intercept`): GD-10. Reactor explosion with its owner's structure death; terrain / landing damage with GD-15.
