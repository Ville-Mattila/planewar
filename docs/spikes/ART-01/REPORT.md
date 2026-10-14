# ART-01 REPORT: S-ART-1 look-dev spike

| | |
|---|---|
| **Task** | ART-01 |
| **Spike** | S-ART-1 (07 s1.5, s3.1, s4.3 and the 07 s14 ART-01 row; renderer 03 s7 / TA-23) |
| **Branch** | `spike/ART-01-lookdev` from `c9045a8` |
| **Author / tier** | presentation (planet) engineer / Opus |
| **Date** | 2026-10-14 |
| **Owner gate decision** | |

## 1. Scope

Built:
- `src/presentation/shaders/moon_light.gdshaderinc`. It holds the 07 s1.5 model: wrap sun in `light()`, radial hemisphere ambient, earthshine, the day-side limb rim and global uniform `sun_dir`. It also has the colour-space helpers `ml_to_linear` and `ml_encode` (s3.1).
- `unit_lit.gdshader` and `unit_lit_instanced.gdshader`. Both use the body in `unit_lit.gdshaderinc`, which covers:
  - atlas swatch and 2-bit alpha class;
  - team paint and team glow;
  - emblem offset;
  - `build_progress`, `damage01`, `wreck`.

  The only difference is `#define UNIT_PARAM uniform` vs `instance uniform`.
- `src/presentation/planet/shaders/moon_surface.gdshader`. A first-pass moon material: mare to highland by `CUSTOM0` height01 and slope01, on the include.
- `MoonLight` (`presentation/planet/moon_light.gd`):
  - registers `sun_dir`;
  - builds the sun and the LDR environment;
  - keeps the light aligned with `sun_dir`;
  - loads the materials;
  - mirrors the constants as a CPU reference (`shade_linear`).
- `test/golden/world/lookdev_shot.tscn`, with views `sphere`, `pole`, `samples_day`, `samples_terminator` and `samples_night`. It includes in-render measurement probes and 12 primitive sample meshes (`lookdev_meshes.gd`).
- `goldens.json`, `test/perf/bench_instance_uniforms.gd` and `test_moon_light.gd`.
- Demo args `--lat/--lon/--yaw/--interim/--hud=0`.
- Fix to `unit_atlas.png.import`. It was generated from the LFS pointer, so it had `valid=false` and nothing imported. It also had `fix_alpha_border=true`, which repaints alpha-0 pixels, and every plain swatch is alpha 0. The UID is unchanged. A test asserts that the imported RGB stays intact under alpha 0.

Left out:
- Blender sample meshes (ART-04).
- Earth/sun sky (ART-15).
- 07 s3.1 terrain features (TA-24).
- Android-mid and web-mobile runs (HUM-06).

## 2. Harness

Dev PC: Godot 4.7.2, RTX 5070 Laptop with driver 610.74, Windows 11, 1280 x 720 window, Compatibility renderer. Two drivers were used:
- `opengl3` (GL 3.3);
- `opengl3_angle` (ANGLE on D3D11, the WebGL2 backend of Chrome on Windows).

```sh
godot --path godot --rendering-driver opengl3 res://test/golden/world/lookdev_shot.tscn -- --view=pole [--instanced] --shot=<png>
godot --path godot --rendering-driver opengl3 res://scenes/presentation/planet/planet_demo.tscn -- --lat=0 --alt=9000 --pitch=-89 --frames=300 --hud=0 --shot=<png>
godot --path godot --rendering-driver opengl3 --disable-vsync -s res://test/perf/bench_instance_uniforms.gd -- --n=255 [--material]
```

How the probes measure: each probe takes the mean of a 7 x 7 block, applies the exact sRGB decode, and divides by the linear albedo.
- Lit probes are compared with `MoonLight.shade_linear` for a level face.
- The two mare probes are also compared with the 07 target. Luminance uses Rec.709 weights.

## 3. Measurements

### 3.1 Godot 4.7.2 Compatibility colour space (drives the include design)

| Unshaded `ALBEDO` value | exact sRGB byte | Compatibility | Forward+ |
|---|---|---|---|
| 8/255 | 8 | 1 | - |
| 0.04 | 56 | 4 | 56 |
| 0.10 | 89 | 22 | 89 |
| 0.20 | 124 | 50 | 124 |
| 0.40 | 170 | 102 | 170 |
| 1.00 | 255 | 255 | 255 |

- Compatibility treats `ALBEDO` and `EMISSION` as **sRGB-encoded**. It decodes them with Godot's polynomial `x(x(0.3053x+0.6822)+0.01252)`, lights in linear, and re-encodes with an approximate pow. A 256-step LUT matches `l2s_approx(poly(x))` to within one level.
- `DIFFUSE_LIGHT` is linear: its LUT is the sRGB encode.
- `source_color` textures and uniforms arrive unconverted.
- The results are the same in an empty project, with `hdr_2d` on or off, and under ANGLE.

So a shader that writes linear constants renders far too dark. The interim TA-23 moon was near-black for this reason, and night mare came out at about -59 % luminance.

The include therefore:
- converts its inputs with `ml_to_linear`;
- writes `ALBEDO` and `EMISSION` through `ml_encode`, which inverts the polynomial with two Newton steps;
- puts ambient and earthshine in `EMISSION`, so the result is correct for any light count;
- keeps only the sun in `light()`.

### 3.2 Night mare and team colours (PC)

| Metric | Setup | Value | Notes |
|---|---|---|---|
| Night mare, Midnight Pole, rendered / albedo | GL 3.3, `moon_surface` | 0.267 / 0.357 / 0.626 | target 0.30 / 0.36 / 0.55 |
| same, error vs 07 | GL 3.3 | -10.9 / -1.0 / +13.9 %; **luminance -0.2 %** | band +-20 % |
| same, `unit_lit` with the `biome_mare_mid` swatch | GL 3.3 | identical bytes (31, 40, 65) | both materials agree |
| same, instance uniforms | ANGLE D3D11 | 0.267 / 0.373 / 0.626; **luminance +2.9 %** | |
| Before the colour-space fix | GL 3.3 | 0.079 / 0.135 / 0.378; luminance about -59 % | |
| CPU model | `MoonLight.night_pole_ratio` | 0.271 / 0.368 / 0.623; luminance +2.1 % | `EARTH_GAIN` 0.50 (07 anchor 0.55, -9 %) |
| 8 team glows vs 07 s2.2 hex | GL 3.3 + ANGLE; material + instance | **8 / 8 exact** | raw hex without `ml_encode`: Forest off by (-4, 0, -5) bytes |
| Apron hull_600 / mare ground vs model, luminance | day (lat 50) / terminator / night (lat -70) | -1.2 / -0.9; -4.1 / -2.0; -2.9 / -0.5 % | per channel within +-4.5 % |
| Day ground with the literal 07 rim at Chase height | GL 3.3 | +58.9 % vs model | the rim now fades in from 1.25x to 1.75x of R (about 1.5 to 4.5 km camera height) |

### 3.3 Instance uniforms

| Metric | Setup | Value |
|---|---|---|
| Renders with exact per-instance team colour | GL 3.3; ANGLE D3D11 | yes; yes |
| Global uniform buffer (Godot's "Maximum items supported") | GL 3.3, ANGLE | 4,096 vec4 (64 KB UBO; the 65,536 setting is clamped) |
| Instances that fit | GL 3.3, ANGLE | **255** (the 256th errors). 16 slots per instance, plus 1 for `sun_dir` |
| At the WebGL2 minimum UBO of 16 KB | derived | 63 |
| Frame, 255 boxes: instance vs per-team material | GL 3.3 / ANGLE | 2.02 vs 2.19 ms / 0.71 vs 0.72 ms |
| Frame, 1,000 boxes per-team material | GL 3.3 / ANGLE | 2.51 / 1.37 ms |

### 3.4 Planet renderer with `moon_surface` (TA-23 demo, PC, HIGH tier, vsync off, 1,170 frames, 2 runs)

| View | moon_surface p50 / p95 ms | interim p50 / p95 ms |
|---|---|---|
| Day, 150 m | 3.70-3.97 / 6.06 | 7.61-7.84 / 8.33 |
| Orbit, 9 km | 1.90-1.97 / 2.72-2.78 | 2.66-2.78 / 3.33-3.70 |
| Boost path, 160 m/s at 30 m | 3.70 / 4.76-5.56 | 3.70-4.17 / 3.70-6.06 |

- There is no measurable cost on PC; the spread is GPU clock noise.
- Chunk build p50 is 1.03-1.16 ms and p95 1.67-1.88 ms. The mesher is unchanged.
- LOW boost path at vsync: 1,770 frames, p50 6.94 / p95 7.26 ms, build p95 1.80 ms.
- `ml_encode` costs two pows and two Newton steps per output. Android-mid cost is PENDING HUMAN.

## 4. Pass / fail per criterion

| Criterion (verbatim) | Result | Evidence |
|---|---|---|
| Golden screenshots on PC, Android-mid, Web-mobile | **PC PASS** (local, GL 3.3 + ANGLE). **Android-mid PENDING HUMAN (HUM-06).** **Web-mobile PENDING HUMAN (HUM-06).** **llvmpipe PENDING ci** | goldens.json, screenshots |
| instance uniforms work on WebGL2 and Adreno or fallback chosen | **Fallback chosen.** Instance uniforms work on GL 3.3 and ANGLE, but the capacity (255 / 63) is below `entity_views_cap` (200 / 400 / 800). A real WebGL2 export was not possible (ci-owned presets; no local templates). Adreno is PENDING HUMAN | s3.3 |
| night mare luminance within 20 % of Section 1.5 targets | **PASS** (PC): -0.2 % / +2.9 % | s3.2 |

## 5. Fallback taken or recommended

Use the 07 s4.3 fallback, extended to state. This is a data and wiring choice and does not split code paths.
- `unit_lit.gdshader` takes team and state as material uniforms.
- ART-03 adds a material cache keyed by (team, state bucket):
  - 8 teams x (healthy, 3 damage steps, wreck);
  - per-instance duplicates only while `build_progress < 1`.
- Draw calls do not change, because Compatibility draws each `MeshInstance3D` separately either way.
- `unit_lit_instanced` stays for small bounded sets of at most 32 instances, such as the possessed unit and ghosts. Every instance whose material declares instance uniforms reserves 16 slots.

**`quality_tiers.json`: no change.** `sun_shadows` still works (`ATTENUATION` in `light()`). If Android-mid is fill-bound on `ml_encode`, the fix belongs in the shader (one Newton step or a LUT), not in tier data.

## 6. Plan changes requested

- **needs ci:**
  - loop `goldens.json` in nightly `golden-screenshots`, or fold it into TA-35;
  - add `[shader_globals] sun_dir` to `project.godot`;
  - add a web preset or feature that boots `lookdev_shot.tscn`, for WebGL2 on HUM-06 devices.
- **needs assets:** `moon_ramp.png.import` has the same `valid=false` / `fix_alpha_border=true` problem.
- **07 patches (Architect):**
  - s1.5: the include path is `godot/src/presentation/shaders/` (code, not an LFS asset); earthshine gain is 0.50; the rim is height-faded.
  - s4.3: the fallback above.
  - New note: Compatibility treats `ALBEDO` / `EMISSION` as sRGB, so shaders use `ml_to_linear` / `ml_encode`.
- **TA-24:** build `moon_terrain` on the include. Run LUT samples through `ml_to_linear` and outputs through `ml_encode`. Retire `moon_surface` and `planet_chunk`.
- **ART-03:** library and material cache.
- **ART-15:** sky.
- **ART-04:** real sample meshes.

## 7. Notes for humans

- **Possible upstream issue for a human to file:** Compatibility's ALBEDO/EMISSION round trip is not identity near black, because the decode polynomial and the encode pow disagree there. Repro: `ALBEDO = vec3(0.04)` unshaded renders byte 4, and Forward+ renders 56.
- The literal 07 rim washes out dark terrain near the horizon at Chase and Tactical heights. It is now faded by camera height. Owner taste check (HUM-09).
- On HUM-06 devices, run `goldens.json` and record:
  - the `LOOKDEV_NIGHT_TARGET` lines;
  - the team-glow bytes;
  - `bench_instance_uniforms.gd --n=300`, to read the "Maximum items" value.


