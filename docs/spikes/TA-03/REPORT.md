# TA-03 REPORT: S-CI-1 clean-checkout CI

| | |
|---|---|
| **Task** | TA-03 |
| **Spike** | S-CI-1 (01 Appendix A; 03 s14.5) |
| **Branch** | `task/TA-03-ci` (PR #10), run 38058833762 |
| **Author / tier** | tools/CI engineer / Sonnet |
| **Date** | 2026-10-10 |
| **Owner gate decision** | PASS (Opus orchestrator signs off the soak result, 2026-10-10; stub scene only, re-run against TA-22's real sim) |

## 1. Scope

Built `ci.yml`, `nightly.yml`, composite action `.github/actions/setup-godot` (Godot 4.7.2-stable pinned, SHA-512 verified, cached), helper scripts in `.github/scripts` (gdUnit4 install, preset export with log gate, Android setup, soak slope, A/B, size gate, png_check, atlas_check, placeholder_icon), and test scenes: `godot/test/soak` (`soak_pr`, `SoakWorldStub`: 200 entities on a sphere), `godot/test/perf/perf_tick` (stub of S-SIM-1 until TA-22), `godot/test/golden/shot_main`.

Not built: pinned self-hosted runner (TA-42; the `perf-pinned` job is wired and skipped until `PERF_RUNNER=true`), REPO-06 commit lint, `validate_content` / `validate_scenes` / `gen_module_api` (not merged yet; their steps skip). gdUnit4 6.2.2 is installed per job, not vendored.

## 2. Harness

ubuntu-latest, official godot-builds assets (no godot-ci Docker image). PR jobs run in parallel: tools, godot-tests, export matrix (linux_server, windows_x64, web + size gate, linux_x64), android (debug AAB via Gradle, JDK 17), screenshot (Xvfb + llvmpipe: smoke-run of the exported linux_x64, then `--write-movie` of `res://test/golden/shot_main.tscn`), soak, ab-perf (PR only), v11-presets (ios_xcode, macos; when presets or `.github` change).

Soak: `godot --headless --path godot --fixed-fps 30 res://test/soak/soak_pr.tscn -- --minutes=10 --pace=realtime` (18,000 ticks, one per 33.3 ms of wall time, so 10 real minutes). `soak_slope.py` gates on the Theil-Sen slope of per-minute p95 (least squares also printed).

A/B: base and head side by side, head's harness copied into base, 7 interleaved runs per side, median p95, fail above +25 %; then base-vs-base x10 with the same 7 rounds.

## 3. Measurements

| Metric | Setup | Value | Unit | Notes |
|---|---|---|---|---|
| PR pipeline wall time | hosted | 10 m 19 s | | critical path = soak; other jobs <= 3 m |
| Soak step p95 per minute | stub, 200 entities | 318, 312, 308, 302, 316, 308, 318, 320, 322, 323 | us | p50 ~280 |
| Soak slope (Theil-Sen) | | +0.47 | %/min | least squares +0.41; earlier runs -1.41, -0.28 |
| Tick-gap p95 | | 33.36-33.38 | ms | slope +0.006 %/min |
| A/B head vs base | 7 rounds | -0.35 | % | earlier -1.34, +6.30, +0.29 |
| A/B base vs base | 10 x 7 rounds | max 1.72, median 0.69 | % | 10 x 3 rounds once hit 36.13 % |
| Web Brotli sum (q9) | stock template | 7,969,189 | B | wasm 7,889,576; js 64,438; pck 10,149; html 1,853; budget 20 MiB |
| Screenshot non-black ratio | 1280x720 | 0.0755 | | gate > 0.01 |
| Exports | | 3 / 4 / 4 / 2 / 48 / 13 / 5 | s | linux_server / linux_x64 / windows_x64 / web / android_aab / macos / ios_xcode |
| gdUnit4 6.2.2 | headless | 31 tests, 0 failures | | |

## 4. Pass / fail per criterion

| Criterion (verbatim) | Result | Evidence |
|---|---|---|
| Green on a clean checkout | PASS | run 38058833762, 11/11 jobs |
| soak slope of per-minute p95 < 2 %/min | PASS | +0.47 %/min |
| PR pipeline <= 15 min | PASS | 10 m 19 s |
| size gate prints the Brotli sum | PASS | `BROTLI_SUM_BYTES=7969189` |
| base-vs-base A/B noise < 25 % | PASS | max 1.72 % with 7 rounds; keep rounds >= 7 |

All 7 presets exported for real; no preset key changed. CI-only patches: placeholder `config/icon` and dummy iOS team id. iOS on Linux yields the Xcode project only.

## 5. Fallback taken or recommended

None needed. If hosted A/B noise returns, raise rounds or gate on the lower of p95 and mean; absolute gates belong to the pinned runner (TA-42).

## 6. Plan changes requested

- Project app icon (art task).
- ART-02: `build_palette.py --check` should compare pixels, not PNG bytes (Linux zlib differs); CI works around it.
- `project.godot` `directory_rules` exempts `res://addons` and `res://test` from warnings-as-errors; `test_mathx` uses `assert_vector` (TA-01/TA-05 files, changed in this PR).
- `tools/web_compress.py` absent, so the size gate uses the `brotli` CLI at q9.
- `validate_*` and `gen_module_api` steps are no-ops until those tools merge.

## 7. Notes for humans

`nightly.yml` and `perf-pinned` were only YAML-validated; run nightly once after merge via `workflow_dispatch` (watch ab-noise and v11-exports). Node 20 action deprecation warnings (checkout/cache/upload-artifact/setup-java v4). The R2 s10.6 stall was not reproduced in the stub scene. Nothing to file upstream.
