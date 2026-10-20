# tools/art

Colour pipeline checks (ART-02). Source of truth: `tools/blender/palette.json`.

## Commands

```
python tools/art/cvd_check.py --selftest                    # CIEDE2000 vs Sharma et al. 2005 reference pairs
python tools/art/cvd_check.py tools/blender/palette.json    # threshold check, exit 1 on failure
python tools/blender/build_palette.py                       # regenerate godot/assets/textures/unit_atlas.png
python tools/blender/build_palette.py --check               # exit 1 if the committed atlas is stale
```

Standard library only (Python 3.10+). Thresholds are hard-coded in `cvd_check.py` (R0 C1-11, 07 s2.3):
team vs team >= 20 normal and >= 11.0 under each CVD (Machado 2009, severity 1.0); slots 0-3 >= 15;
slots 0-1 >= 40; team vs `hull_700` and UI plate >= 20; relation colours (ally/enemy/self) >= 20 under every
vision type, mutually and against `hull_500`-`hull_800` and the UI plate.

## Import pipeline (ART-05, docs/07 s4.6-4.7)

```
python tools/art/validate_glb.py godot/assets/models            # V01-V15; JSON on stdout, `file: Vnn fail: ...` on stderr, exit 0/1
python tools/art/validate_glb.py a.glb --quiet --report r.json
python tools/art/write_import.py godot/assets/models            # writes <asset>.glb.import from glb.import.template
python tools/art/write_import.py godot/assets/models --check    # CI: exit 1 on a missing or stale .import
```

- `asset_budgets.json` (schema `tools/schemas/asset_budgets.schema.json`, tools-only, not a content def): class and per-asset
  triangle ceilings (07 s5.1), file-size limits, scale-chart sizes (`size_m` = [X, Y, Z] in Blender axes; structures' height is
  above ground, the foundation skirt is not counted), required hardpoints / parts / Far mesh (`<PascalId>Far`, e.g. `ShipDartFar`).
  Hardpoint lists are minimums. Ships always need `HP_Nose`, `HP_Tail`, `HP_Gear_0..2` (V11). V03 sums all meshes including Far.
  Open points: 07 s5.1 says 14 props but lists 13 ids (13 are in the file); `wreck_*` models go to `assets/models/props/`.
- `validate_glb.py` reuses `tools/blender/lib/pw_core.run_checks` (the same rules `pw.finalize()` runs in Blender) and adds the
  glb-only V02, V05, V08, V13 plus the per-asset requirements. Pure Python (struct + json), no Blender, no numpy.
- `glb.import.template`: key names captured from a Godot 4.7.2 headless import (`.glb.import` it wrote), values set per 07 s4.6.
  uid and cache hash derive from the `res://` path, so output is reproducible and Godot leaves the file unchanged.
- `godot/assets/_pipeline/post_import_asset.gd`: `HP_*` -> `Marker3D`; hull `visibility_range_end` = Far swap distance
  (935 S / 24 px), Far `begin`/`end` = swap / hide (935 S / 3 px), `S` = longest horizontal extent; no shadows on props, wrecks,
  projectiles and Far meshes; `unit_lit.tres` assigned if it exists (v1 uses `UnitMaterialCache`, ART-03); triangle count printed, over-budget warned.
  `godot/tools/check_post_import.gd` asserts the result on an imported glb.
- Tests: `python -m unittest tools/tests/test_validate_glb.py tools/tests/test_art_import.py` (the Godot part needs `GODOT_BIN`
  or `godot` on PATH, otherwise skipped). CI job `art-import` runs them and validates every committed model.

## CI wiring (for TA-03)

TA-03 creates the workflows. Add these steps (no dependencies to install) to the art/tools job, triggered on
changes to `tools/blender/palette.json`, `tools/art/**`, `tools/blender/build_palette.py` or
`godot/assets/textures/unit_atlas.png`:

```
python tools/art/cvd_check.py --selftest
python tools/art/cvd_check.py tools/blender/palette.json
! python tools/art/cvd_check.py tools/art/fixtures/palette_bad.json   # negative fixture must be rejected
python tools/blender/build_palette.py --check
```

The `!` line fails the job if the checker *accepts* the bad file. A non-zero exit from any other line fails the build.

`tools/art/fixtures/palette_bad.json` is a deliberately broken palette (Coral moved next to Amber, relation
colours too close under deuteranopia). Keep it failing.
