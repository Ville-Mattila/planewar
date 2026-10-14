# sim/combat - MODULE.md

Contract for `godot/src/sim/combat/**`: tick-order step 9 damage, the rules of 02 s4.3 (GD-08; R0 B.5 tick order; B.9 A-3,
A-30). R0 B.9 A-21 split of `sim/MODULE.md`, which stays the home of every type other lanes may name (`SimEvent.Kind`
ordinals, `EntityStore`, Collision contacts). A change to "Public API" or "Invariants" is a contract change: contract tests
first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Turns the Contact records of step 8 into hit-point changes: the gun roll and structure / ground multipliers (rule 1), bomb kill radius, blast and Hangar immunity (2-3), rockets (4), flak (5), siege-shell blast, ramming (7), no friendly fire (8), HIT / BOMB_IMPACT events (9) and the deferred-death marks. Does not own weapon fire, ammo, fuse timing, lock rules, tower targeting (GD-36, GD-09), shield domes (GD-10), terrain or landing damage (Docking, GD-15), Reactor explosions, wrecks or scoring. |
| Lane owner tier | Opus (sim lane); Sonnet for recipes against this file |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/`: `WorldDefs`, `SimEvents`, `CommandApplier`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads (D2, D3) |
| Autoloads used | None |
| Status | implemented (GD-08, 2026-10-14); replaces the interim projectile frees of `SimWorld._step_combat` |

## Public API

Lane-internal: `SimWorld` composes one `Combat`; other lanes see its effects through `SimView` HP and the events. Not in
`tools/deps.json` named types.

```gdscript
class_name Combat extends RefCounted                                         # step 9; one per SimWorld
var rng: Rng                                                                 # SimWorld hands over its own Rng before each step (S7)
func step(tick: int) -> void                                                 # HIT / GROUND / RAM contacts of the last Collision.step, in contact order
func detonate_bomb(pos: Vector3, owner_team: int, w: WeaponDef, p: ProjectileDef, attacker: int, tick: int) -> void   # rules 2-3, as a fuse would fire it
static func roll_gun_damage(w: WeaponDef, target_kind: int, dice: Rng, extra_mult: float = 1.0) -> int   # rule 1; target_kind is EntityStore.K_*
class_name Blast extends RefCounted                                          # area rules: bomb, flak, siege shell
const ROOF_BOMB_MULT: float                                                  # 0.25 (needs content: structure_bomb_mult)
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

- CB1: the only random draw is `Combat.roll_gun_damage` on `SimWorld.rng` (S7), one `range_i` per hit whose weapon has `damage_min < damage_max`, in Contact order; point ranges (bomb 400, rocket 40, rail 250, siege 120) draw nothing. No fork, no other source.
- CB2: weapons are the owner's doctrine-resolved defs (`WorldDefs.resolved(owner)`), indexed by the projectile's `weapon_def`; Combat applies no doctrine factor of its own (02 s4.3 rule 1, s7), so Foundry's x0.85 reaches ship mounts only (A-3).
- CB3: gun damage = `max(round(roll * mult), 1)` with `structure_mult` vs structures, `ground_mult` vs ground units, 1.0 vs ships; bomb damage to a structure also carries `bomb_mult` (roofed pad 0.25, Core after Exposure `core_bomb_mult_exposure`) inside the same single rounding.
- CB4: a ship whose bounding sphere is within `blast_radius_m` of a bomb detonation is destroyed (no HP arithmetic) unless it is DOCKED with `link` a live roofed-pad structure (Hangar). Ground units and structures use `blast_radius_structure_m`; structures by distance to the footprint rectangle (`footprint[0]` cells along `fwd x up`, `footprint[1]` along `fwd`, cell = `PLANET_RADIUS * PI / 2 / GRID_BUILD`). No falloff.
- CB5: nothing hostile is spared and nothing friendly is hurt: a projectile or blast never damages an entity of the shooter's team unless `MatchRules.friendly_fire`; ramming ignores teams. Wrecks take no damage.
- CB6: a projectile with a HIT contact acts only once armed (`lifetime_s - ttl >= arm_s` or `F_ARMED`); an unarmed one flies on. A GROUND contact always detonates (terrain cannot be passed). A consumed projectile is freed in the same step.
- CB7: a ship-ship RAM destroys both; a ship-structure RAM destroys the ship and deals its remaining HP to the structure; either already at 0 HP this tick is skipped. Invulnerable structures take nothing.
- CB8: `DamageSink` is idempotent on a 0-HP entity (two blasts in one tick never double-kill); HIT carries the rolled value (overkill included), a lethal hit or outright kill calls `CommandApplier.kill` for the end-of-step free.
- CB9: allocation-free per entity: no Dictionary / Array built in a per-entity loop; area queries allocate one `PackedInt32Array` per detonation (rare).

## Data owned

None persistent: `Combat` keeps references only; HP, `last_damage_tick`, `attacker` and `dirty` live in `EntityStore`, the roll stream in `SimWorld.rng` (serialized with the world, S4). Defs read: `weapons.json`, `projectiles.json`, `structures.json` (`footprint`, `pad_roofed`, `invulnerable`), `match_rules.json` (`core_bomb_mult_exposure`), doctrine `hangar_blocks_rockets`.

## Events emitted / consumed

Emits HIT (target, attacker, damage as value, target team) and BOMB_IMPACT (attacker, -, position, kill radius as value, shooter team); DEATH is `CommandApplier.resolve_deaths`'s. Consumes Collision contacts C_HIT, C_GROUND, C_RAM; C_TERRAIN and C_PAD are Docking's / GD-15's.

## Performance budget

03 s4.2 row 9 (combat 1.2 ms p95 at 1,200 entities + 2,000 projectiles). Cost is proportional to Contact count plus one `Spatial.ids_near` per detonation; no per-entity scan. Not yet on `perf_tick.gd` (no weapon fire until GD-36 produces contacts at scale).

## Test entry points

`godot/test/unit/sim/combat/test_combat_rules.gd` (CB1-CB3, roll distribution, doctrine fold), `godot/test/unit/sim/combat/test_combat_world.gd` (every rule through `SimWorld.step`, scenario C-09), `godot/test/unit/sim/combat/test_combat_determinism.gd` (CB1, S4 resume).

## How to add X (recipes for the cheapest tier)

- **A projectile kind's effect:** add its `ProjectileStore` kind branch to `Combat._projectile` and an area method to `Blast`; test one rule per behaviour in `test_combat_world.gd`.
- **A damage multiplier from data:** read it in `Blast.bomb_mult` (or `Combat.roll_gun_damage` for a weapon field); never type the number (ADR-09).

## Open items

- `ROOF_BOMB_MULT` 0.25 is 02's literal: needs content, a `structure_bomb_mult` field in `structures.json` + schema (R0 B.1 owner). Until then it is a named constant.
- Interpretation to confirm (02 s4.3 is silent): siege-shell blasts damage ships too (inside `blast_radius_m`); rockets have no proximity burst here (a rocket acts on the entity its sweep hits; the 4 m proximity fuse and flak's timed burst are GD-36); DEATH cause stays the interim `DEATH_CAUSE_DEBUG`.
- Shield domes (rule 6, `shield_intercept`) are GD-10; weapon fire GD-36; tower targeting GD-09; Reactor explosion with its owner's structure death; terrain / landing damage with GD-15.
