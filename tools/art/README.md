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
