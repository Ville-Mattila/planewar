# tools/moonbake

Offline moon baker (TA-15, docs/03 s8, R0 B.2). Python 3.12+, numpy only (`tools/requirements.txt`, `numpy==2.3.*`).
PNGs are written with stdlib `zlib` (no Pillow).

```
python -I tools/moonbake bake     <recipe.json> --out <dir> [--no-preview] [--ramp]
python -I tools/moonbake validate <recipe.json>            # schema, M1-M12, bakes in memory; exit 1 on a failure
python -I tools/moonbake preview  <recipe.json> --out <dir> # preview.png, faces_{height,slope,biome}.png, polar.png
python -I tools/moonbake check    <recipe.json>            # re-bake and compare with the committed meta.json (CI)
python -I tools/moonbake ramp     [--out P] [--ramps biome_ramps.json]   # moon_ramp.png hook (ART-14 / ART-31)
python -I tools/bake_check.py [MAP_DIR ...]   # CI bake-check (TA-17): every committed file == fresh bake, all maps
python tools/check_lfs.py                     # CI LFS check (TA-17): no Git LFS pointer where a blob is tracked
```

`python -I -m moonbake` from docs/03 cannot work (`-I` removes the working directory from `sys.path`), so the
directory is the entry point: `tools/moonbake/__main__.py` adds its parent to the path.

## Outputs (03 s8.3)
`face{0..5}.height.u16`, `.biome.u8`, `.slope.u8`, `.path.u8`, `features.json`, `meta.json` (+ `preview.png`).
Texel (x, y) samples u = x/(N-1), v = y/(N-1); the seam pass writes the lower face's value on every shared edge
texel and at the 8 corners (bit-identical on both faces; same for biome ids).

## Determinism (03 s8.6)
Integer-hash noise, a splitmix64 sub-RNG for scatter craters, heights rounded to 1 mm before the u16 quantise.
`meta.json` deliberately has no `bake_time_utc` (it would break byte-identical re-bakes); `recipe_sha256` hashes the
canonical JSON, so line endings cannot change it. `preview.png` is zlib output and is not hashed. `moon_ramp.png` uses
stored deflate blocks so its bytes do not depend on the zlib build.

## Decisions the spec left open
- Base noise is made 8-fold symmetric by folding each point into the wedge starting at `wedge_start_deg` and blending
  with the neighbouring fold inside a 3 degree band at the wedge borders (`terrain.base_height`).
- Stamps use the stage order of 03 s8.2; crater base height is the mean over an equal-area probe set measured on the surface as it is when that crater is stamped (regions and earlier craters applied); M12 caps the texel-to-texel step at 200 m; cold traps are
  `COLD_TRAP_DEPTH_M` (100 m) below their rim ring; M3 allows 2 % of cells above 10 degrees.
- M8 checks connectivity by flood fill on the 6 x 256^2 path grid (cross-edge steps through the mapping), not A*.
- M10 estimates the web pack as a delta-filtered, byte-plane-split zlib size (raw zlib of u16 heights is about 2.4x larger).
- M9 targets live in `biome_targets.json` (07 s9.4 table). M5 compares 7 rotated copies of 12 x 25 wedge sample points.
- `moon_ramp.png` is 64 columns (ramp value) x 16 rows (biome id, ids 8-15 magenta). It reads
  `godot/content/biome_ramps.json` when ART-14 adds it, else the 07 s2.1 palette.
- Check codes: M4a (lat) / M4b (depth), X1 (no node inside a flatten disc, 03 s8.2).

Tests: `python -m unittest discover -s tools/tests` (`test_sphere_parity`, `test_seams`, `test_moonbake`).

Prerequisites (TA-17, `tools/tests/gates.py`): numpy from `tools/requirements.txt`, and real LFS blobs under
`godot/content/maps/` and `godot/assets/textures/` (run `git lfs pull` in a fresh worktree). On a dev machine a missing
prerequisite skips the affected tests with a message; with `CI` set (GitHub Actions) it fails instead. `python -I`
ignores the user site-packages, so numpy installed per-user is invisible there and the numpy tests skip locally.
