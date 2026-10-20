# tools/audio (ART-22, docs/07 s8.4)

Stdlib-only offline SFX pipeline. Mono, 22.05 kHz, PCM16 WAV.

- `sfxgen.py <recipe.json>... [--out DIR] [--validate]` renders recipes (`tools/schemas/sfx_recipe.schema.json`) to `<id>.wav` + `<id>.json` metadata. Deterministic by `seed` (own splitmix64 PRNG). `"loop": true` cross-fades the tail into the head (`loop_crossfade_ms`).
- `analyze.py <wav> [--loop] [--lufs T --lufs-tol N] [--centroid LO HI] [--duration LO HI] [--recipe R]` prints peak, clipped samples, DC, duration, LUFS (BS.1770), spectral centroid, loop seam ratio; exit 1 and `file:1:` lines on a problem (clipping, peak above -1 dBFS, DC > 0.01, > 4 s, bad loop seam, target misses).
- Recipes live in `tools/audio/recipes/<sfx_id>.json` (ART-23/24). Test fixtures: `tools/tests/fixtures/audio/`. Tests: `tools/tests/test_sfx_audio.py`.
