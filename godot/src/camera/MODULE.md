# camera - MODULE.md

Contract for `godot/src/camera/**` (06 s5, 06 s13; UX-10). A change to "Public API" or "Invariants" is a
contract change: update the contract tests first, in the same PR (ADR-11); `tools/gen_module_api.py --check`
must pass; <= 300 lines. Section order follows `docs/templates/MODULE.md.template`. UX-10 lands the pure
math (`CamMath`, `OrbitMath`); the Node classes are tracked under "Open items".

| Field | Value |
|---|---|
| Responsibility | The camera rig: Chase, Tactical and Commander tiers, orbit and chase controllers, transitions, picture-in-picture, near/far policy. UX-10 owns only the static, unit-tested math behind them. Does not read the sim; reads presentation `ViewState`. Does not own input mapping (`input`) or HUD (`ui`). |
| Lane owner tier | Sonnet; Opus for UX-02 and UX-11 |
| May depend on | `core`, `presentation` (`tools/deps.json`) |
| Must never touch | `sim`, `net`, `content` loaders, `ui`, `input`; no hard-coded 6,000 (use `Sphere.PLANET_RADIUS`, D6) |
| Autoloads used | none |
| Status | UX-10 math implemented; controllers planned (UX-11, UX-13, UX-14) |

## Public API

Anything not listed is private (prefix `_`). Formulas: 06 s5.2 to s5.5. Basis convention (03): `f = -basis.z`,
`u = basis.y`, `r = basis.x`. Constants will move to `godot/content/ui/camera.json` when UX-02 records them.

```gdscript
class_name CamMath                    # all static; chase, transition and near/far math
const NEAR_BASE: float; const NEAR_PER_M: float; const NEAR_MAX: float          # 0.3, 0.004, 20 (R0 C2-28)
const NEAR_ALT_MIN: float; const NEAR_ALT_A0: float; const NEAR_ALT_SPAN: float; const NEAR_ALT_RISE: float
const FAR_PLANE: float                                                           # 40,000 m (ADR-02)
static func crit_damp(x: Vector3, v: Vector3, target: Vector3, omega: float, dt: float) -> PackedVector3Array   # [pos, vel]
static func crit_damp_f(x: float, v: float, target: float, omega: float, dt: float) -> Vector2                  # (pos, vel)
static func bank_angle(b: Basis, n: Vector3) -> float                            # > 0 = right wing down
static func perp(x: Vector3, d: Vector3) -> Vector3
static func smootherstep(t: float) -> float
static func vertical_weight(d: Vector3, n: Vector3) -> float
static func up_reference(d: Vector3, n: Vector3, u: Vector3) -> Vector3
static func roll_target(phi: float, k_roll: float) -> float
static func view_basis(d: Vector3, u_cam: Vector3) -> Basis
static func near_plane(h_cam: float) -> float                                    # default policy: clamp(0.3 + 0.004 h, 0.3, 20)
static func near_plane_orbit_alt(a_g: float) -> float                            # named alternative orbit_alt
static func near_lerp(n0: float, n1: float, s: float) -> float                   # interpolates ln(near)

class_name OrbitMath                  # all static; Tactical / Commander orbit on the sphere
const A_FLOOR: float; const A_CLEARANCE: float; const A_MAX: float; const TACTICAL_A_MAX: float
const THETA_BASE_DEG: float; const THETA_RISE_DEG: float; const THETA_MIN_DEG: float; const THETA_MAX_DEG: float
const Z_RISE_LO: float; const Z_RISE_HI: float; const Z_DELTA_FADE_HI: float
const DELTA_MIN_DEG: float; const DELTA_MAX_DEG: float; const PAN_SPEED_PER_M: float
static func altitude_min(g_f: float) -> float
static func zoom_z(a: float) -> float;  static func altitude_of_z(z: float) -> float
static func is_tactical(a: float) -> bool
static func theta_of(z: float, delta_deg: float) -> float                        # radians
static func solve_distance(f_len: float, theta: float, a: float) -> float        # closed-form D, |F + D w| = R + A
static func pose(d_f: Vector3, h: Vector3, f_len: float, a: float, theta: float) -> Transform3D
static func transport_heading(h: Vector3, d_old: Vector3, d_new: Vector3) -> Vector3
static func north_heading(d: Vector3) -> Vector3
static func heading_error(a: Vector3, b: Vector3, d: Vector3) -> float
static func ray_sphere_point(origin: Vector3, dir: Vector3, radius: float) -> Vector3
static func grab_pan(d_f: Vector3, h: Vector3, g0: Vector3, g1: Vector3) -> PackedVector3Array   # [d_f', h']
static func pan_speed(a: float, g_f: float) -> float
```

## Invariants

- K1: `OrbitMath.solve_distance` agrees with an iterative solve of `|F + D w| = R + A` to < 1 mm; the
  camera sits at `R + A` from the moon centre (`pose().origin.length()`).
- K2: `OrbitMath.pose` has an orthonormal basis (columns `x_cam, y_cam, z_cam`, determinant +1) for every
  unit `dF`, unit tangent `h` and `theta` in [25, 90] deg, including both poles and the cube edges and corners.
- K3: a 1 deg sweep of the focus across a pole, transporting `h` with `transport_heading`, never produces NaN
  and no frame-to-frame heading step above 2 deg.
- K4: `transport_heading` returns a unit vector tangent at `d_new`; identity when `d_old == d_new`; matches `Sphere.transport`.
- K5: `crit_damp` is exact for any `dt` (one step of `dt` equals two of `dt / 2`), converges and never
  overshoots a target approached from rest.
- K6: `near_plane(h)` = `clamp(0.3 + 0.004 h, 0.3, 20)` (R0 C2-28), continuous and monotonic;
  `near_plane_orbit_alt` is only the named alternative; far is 40,000 m.
- K7: `up_reference` and `view_basis` never return NaN, even for degenerate (parallel) inputs.
- K8: no function hard-codes the planet radius; `R` is `Sphere.PLANET_RADIUS`.

## Data owned

None. Pure static functions; no state, no Nodes, no signals. Constants will be read from
`godot/content/ui/camera.json` by the controllers (UX-02, UX-11, UX-13); the math classes take them as arguments or keep
the spec defaults as `const`.

## Events emitted / consumed

None for the math. The planned `CameraRig` emits `tier_changed` and `transition_finished` (06 s5.1; signals are
allowed in `camera` Nodes only, never in the static math classes).

## Performance budget

Per frame on the camera path: `OrbitMath.pose` + `CamMath.crit_damp` well under 10 us each on PC-mid; not on a
hot sim path (one camera, one call per frame). Measured by the UX-02 spike.

## Test entry points

- `godot/test/unit/camera/test_cam_math.gd` (K5, K6, K7, bank, roll, smootherstep)
- `godot/test/unit/camera/test_orbit_math.gd` (K1 to K4, poles and cube edges, grab pan, zoom and tilt curves)

## How to add X (recipes for the cheapest tier)

- A new camera formula: add a `static func` to `CamMath` or `OrbitMath`, list the signature above, add a test row,
  run `gen_module_api.py --check`. Keep each file <= 400 lines.
- A new tuning constant: spec default as `const`, then move to `camera.json` with the UX-02 record.

## Open items

- UX-11 `ChaseController`, UX-13 `OrbitController`, UX-14 `TransitionPlayer` and `NearFarPolicy` (RefCounted)
  consume this math. UX-02 records the final constants in `camera.json`.
- Near/far constants are `const` here until `camera.json` exists.
