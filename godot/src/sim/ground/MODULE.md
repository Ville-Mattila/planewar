# sim/ground - MODULE.md

Contract for `godot/src/sim/ground/**`: tick-order step 5 for ground units (03 s5.3; TA-38; R0 C2-09, C2-11).
R0 B.9 A-21 split of `sim/MODULE.md`, which stays the home of `PilotInput` (ground meaning of the axes), `EntityStore` and
`Terrain`. A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Input-driven motion of every live `K_GROUND` entity, possessed or AI-driven alike (both write the entity's input slot): heading rate from `yaw`, forward speed from `thrust` x the 02 slope factor, BRAKE stop and delayed reverse, great-circle displacement, path-weight and max-slope blocks, terrain snap. Not: choosing the input (a brain in `sim_ai` follows `Pathing` routes), collisions with other bodies (`Collision`), mining / unloading, vision. |
| Lane owner tier | Sonnet against this file; Opus reviews (sim lane) |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/` `WorldDefs`, `InputSlots`; `sim/pathing/` `Pathing`, `PathGrid`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG, clocks (D2, D3) |
| Autoloads used | None |
| Status | implemented (TA-38, 2026-10-14); `SimWorld` step 5 calls it after `ShipMotion` |

## Public API

`SimWorld` composes one `GroundMotion`; other lanes see only its effects (`SimView.pos`, `fwd`, `up`, `vel`). Lane-internal otherwise.

```gdscript
class_name GroundMotion extends RefCounted
func _init(store: EntityStore, inputs: InputSlots, defs: WorldDefs, terrain: Terrain, pathing: Pathing)   # pathing may be null: weights never block
func step(_t: int, dt: float) -> void                                        # step 5: every live ground unit, ascending slot order
const RESNAP_TICKS: int                                                      # 8: idle units re-snap this often (power of two)
static func speed_factor(slope_deg: float, max_slope_deg: float, loss: float) -> float   # max(0, 1 - loss x slope_deg / max_slope_deg); 1 when max_slope_deg <= 0
```

Constants come from the `ground_common` block of `ground_units.json` (A-63, like `flight_common`: `ground_turn_rate_dps` 40,
`ground_reverse_speed_mps` 3, `ground_reverse_hold_s` 0.5, `ground_slope_speed_loss` 0.6; `GroundCommonDef`) and `ground_units.json` (`ground_speed`, `ground_speed_loaded`, `max_slope_deg`, `bounding_radius`).

## Per-unit state and input meaning

- Input slot: `thrust` 0..1 = fraction of top speed (`ground_speed_loaded` while `cargo > 0` and the def has one); `yaw` -1..1 =
  heading rate fraction, + = left (counter-clockwise seen from above); `buttons & BRAKE`; the other axes are ignored.
- BRAKE = stop at once (no inertia; thrust is ignored). Held for `ground_reverse_hold_s` (the tick on which the held time reaches
  it, within half a tick, and every tick after) the unit reverses at `min(ground_reverse_speed_mps, ground_speed)` x the slope
  factor. Releasing BRAKE resets the hold. The hold is `EntityStore.timer_b` of a ground unit (ship repair / structure capture
  use it elsewhere; the field is free for ground).
- Written each tick: `pos` = `dir x (R + height_at(dir) + bounding_radius)`; `up` = `terrain.normal_at(dir)`; `fwd` = unit heading in
  the radial tangent plane at `dir` (exactly perpendicular to `pos`; the tilted body basis is presentation's, from `up`); `vel` =
  `fwd x signed speed`, zero when the step was refused or the unit is stopped. `fwd` that is zero or radial is replaced by local north.
- Slope source is the baked `slope.u8` via `Terrain.slope_deg_at_dir` (the source `Pathing` masks use). The speed uses the slope
  where the unit stands; a step is refused when the slope there exceeds `max_slope_deg` and is steeper than where the unit
  stands (so a unit on ground that is too steep, e.g. after a Build change, can always leave), or when the path cell it would
  enter has weight 0 / 255 and is not the cell it stands in.

**Deviation from 03 s5.3 (climb-out):** the doc blocks motion onto terrain steeper than `max_slope_deg`; here a unit already on such
ground may still step to ground that is no steeper, and while it stands on slope > `max_slope_deg` its speed factor is floored at
`1 - ground_slope_speed_loss` (0.4), because the plain 02 factor reaches 0 at `max_slope_deg / loss` and the unit would be stuck.
The 02 formula is exact everywhere the unit stands within its limit (`speed_factor` itself is unfloored).

## Invariants

- G1: displacement per tick is exactly `speed x dt` along the heading's great circle (datum radius), with
  `speed = top x clamp(thrust) x speed_factor(slope)`; `speed_factor` is the 02 formula (`test_speed_factor_is_the_02_formula`,
  `test_slope_scales_the_distance_travelled_exactly`).
- G2: no tick ends with the unit on a refused step; a unit never enters terrain steeper than `max_slope_deg` nor a blocked path
  cell, and never freezes inside one (`test_terrain_steeper_than_max_slope_stops_the_unit`, `test_a_unit_on_too_steep_ground_can_always_climb_out`,
  `test_impassable_path_weight_blocks_but_the_cell_a_unit_stands_on_does_not`).
- G3: BRAKE stops in the same tick; reverse starts only once BRAKE has been held `ground_reverse_hold_s`, never faster than
  `ground_reverse_speed_mps` (`test_brake_stops_at_once_and_reverses_only_after_the_hold`, `test_releasing_brake_resets_the_hold`,
  `test_reverse_speed_never_exceeds_the_reverse_cap_or_the_slope_factor`).
- G4: after every step `|pos| = R + height_at + bounding_radius` within 1 cm, `up` = `normal_at(dir)`, `fwd` unit and perpendicular
  to `pos` (`test_snap_follows_the_cradle_surface_within_a_centimetre`, `test_a_unit_without_input_settles_onto_the_surface`).
  A moving unit re-snaps every tick; a stationary one on its first two ticks and every `RESNAP_TICKS` (8) ticks, staggered by slot
  (`test_an_idle_unit_is_re_snapped_within_the_resnap_period`), so its pose can lag a terrain change by up to 8 ticks. A unit with
  no input stays put to within one float32 ulp of `|pos|` (re-snap jitter, about 0.5 mm).
- G5: motion is a rotation of the direction, so cube edges need no special case: a straight drive and a followed `Pathing` route
  across an edge move `<= speed x dt + |dh|` per tick, no jump (`test_straight_drive_across_a_cube_edge_has_no_jump`,
  `test_a_pathing_route_across_a_cube_edge_is_followed_to_the_goal`).
- G6 (S4, determinism): the only state is `pos`, `fwd`, `up`, `vel`, `timer_b` in `EntityStore` and the input slots, all in the
  bytes; identical inputs give identical bytes and a save / restore mid-drive continues identically
  (`test_same_inputs_give_identical_bytes`; `test_ground_state.gd`).

## Data owned

None: all state is in `EntityStore` and `InputSlots`. No allocation per tick or per unit (the four position arrays are taken
into locals once per tick and assigned back).

## Events emitted / consumed

None.

## Performance budget

03 s4.2 row 5 (kinematics, ships + ground): 3.5 ms for 400 ships + 200 ground units. `perf_tick.gd --full` (400 ships, 200 ground units, mostly idle, dev laptop under load, 1,800 ticks), kinematics row mean / p95 ms: before 12.86 / 20.04, with
GroundMotion re-snapping every unit every tick 16.59 / 24.63 (+3.7 ms, 18 us per unit), with the 8-tick idle re-snap 11.62 / 22.28 (within run-to-run noise of
the baseline; total tick mean 52.7 / 52.2 / 43.5 ms). A moving unit costs about 3 x an idle re-snap (slope, height and normal samples).

## Test entry points

`godot/test/unit/sim/ground/test_ground_motion.gd` (G1-G6, fixtures: a slope-stub `Terrain`, the cradle map, `Pathing` on cradle),
`godot/test/unit/sim/ground/test_ground_state.gd` (S4 at world level, flat datum and cradle).

## How to add X (recipes for the cheapest tier)

- **A ground unit kind:** add it to `ground_units.json` with `ground_speed`, `max_slope_deg`, `bounding_radius`; no code changes.
- **Retune turning or reverse:** edit the `ground_common` fields above (and the schema bound if it falls outside).
