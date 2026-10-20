# Gain-tuning harness (AI-06)

Headless sweep of `FlightGains` (AI-05) and `LandingParams` (AI-09) keys under both `lift_model` values, a CSV
report, and the best gain set per model. Test code only: it reads `test/sim/ai/ai05_params.json` and
`ai09_params.json` as the baseline and never writes them. Adopting a recommended set is a content change
(`autopilots.json`, AI-19), not part of this harness.

```sh
python tools/gain_sweep.py --out reports/gain_sweep                  # full sweep, ~15-25 min on a laptop
python tools/gain_sweep.py --out reports/quick --stages base,confirm --seeds 20   # smoke, seconds
python tools/gain_sweep.py --summarise godot/test/tuning/reports                  # print a stored run (or one sweep CSV)
python tools/gain_sweep.py --given godot/test/tuning/ai38_given.json --stages confirm --dive-leg-m 0   # A-88 replay (AI-39; ai38 rows, AI-41)
"$GODOT_BIN" --headless --path godot res://test/tuning/gain_sweep.tscn -- --out=/abs/dir [options]
```

Run `--import` once on a fresh checkout (the wrapper does it with `--import`). Every flag of the scene's usage line
(`gain_sweep.gd`) is forwarded by the wrapper; `--dive-leg-m` and `--given` (AI-39) are two of them. `--summarise`
prints the AI-38 columns (`dive_unrecoverable`, `dive_hits_recoverable`, `land_thrust_zero_*`) and prints `n/a` for a
run whose CSV predates them (the committed `reports/sweep.csv` is the AI-06 layout).

## What is measured per candidate

| Family | Scenario | Metrics |
|---|---|---|
| step | AI-05 acceptance steps (turn +-30, climb 15, dive -15, mixed 20/10) for all five ship classes | steps outside 2.0 s / 15 % overshoot (dive under `damping_only`: 2.6 s / 20 %, R0 B.12 A-68), worst time, worst overshoot |
| dive | Dart, 10-45 degrees nose-down, 100-300 m above flat ground, deck-hold + PULL_UP rig (`TerrainFlightRig`), 12 s along a 2 km waypoint line (AI-38) | terrain contacts; on confirm runs also `dive_unrecoverable` (starts no open-loop pull-up saves, see below) and `dive_hits_recoverable` |
| landing | SC-04 geometry: 2-4 km out, 150-450 m, random bearing and heading, `LandingPilot` RETURN, 180 s | docked within R0 B.5 limits and without a scrape (A-70), crashed, median gate-to-dock, mean ticks with throttle < 0.2 in APPROACH / TRANSITION, longest throttle-0 run (`land_thrust_zero_run_max`) and longest APPROACH throttle-0 run while the wing cannot carry the weight (`land_thrust_zero_unsupported_run_max`) |

`score` (lower is better) = 100 x landing failure fraction + 50 x dive contact fraction + 5 x failed steps + 0.1 x
median gate-to-dock + worst overshoot. Seed `k` is the same start state for every candidate.

## Stages (per model)

`base` the anchors; `oat` each key x {0.6, 0.8, 1.25, 1.6}; `greedy` the improving moves combined best-first;
`random` jitter of three random keys around the best (seeded); `confirm` baseline and best at the full seed count
(200 landings + 200 dives by default, under 2 minutes per candidate headless); `cross` each model's best set under the
other model (does one set serve both lift laws, A-68).

Files: `sweep.csv` (one row per evaluation), `landing_failures.csv` (per failed landing of the confirm stage: outcome,
end phase, speed, AGL, lowest throttle and ticks below 0.2 in APPROACH / TRANSITION), `best_gains.json`.
`--given=FILE` evaluates a hand-written `{model: {flight, landing}}` set at the confirm size.

Limits: landings are the Dart on flat ground (the AI-09 SC-04 geometry); the other classes are covered by the step
family only.

## AI-38: scenario change and the physical bound

**Steep-dive scenario changed.** AI-06 drew the waypoint line as 5 % of the way to a random far point (63-600 m); the
rig stops when it reaches its last waypoint (150 m radius), so about 40 of 200 dives ended at tick 0 and many more before
the dive was decided. The line is now `DIVE_LEG_M` = 2 km (12 s of flight; the harness definition, R0 B.15 A-88); start
states are unchanged. `--dive-leg-m=0` replays the AI-06 line for comparisons only. **Bound (R0 B.15 A-88):** `SweepScenarios.dive_recoverable` flies each start
open-loop from tick 0 with a fixed nose elevation 0, 5, ..., 90 degrees (wings level, thrust above the horizon) and with
`Assist.pull_up`; a start none of these saves is "unrecoverable": no constant-elevation pull-up from tick 0 and not the
PULL_UP law avoids contact (a closed-loop law could in principle differ; a knife-edge pull on the side damping was also
tried by hand and saved none). Under `damping_only` 17 of the 200 starts are; under `speed_scaled` none. The A-88
acceptance counts contacts among the recoverable starts: 0 / 183 after AI-38.

Recommended set (`recommended_gains.json` `damping_only`, used for both models: `ai38_given.json`), 200 seeds, seed 606:

```sh
python tools/gain_sweep.py --out reports/ai38_new --given godot/test/tuning/ai38_given.json --stages confirm --failures 200
python tools/gain_sweep.py --out reports/ai38_legacy --given godot/test/tuning/ai38_given.json --stages confirm --dive-leg-m 0
```

**AI-41:** `--given recommended_gains.json` does not reproduce the speed_scaled rows below: it flies speed_scaled on
that file's own `speed_scaled` set (score 2.525, longest throttle-0 run 246 ticks, median gate-to-dock 24.8 s) instead
of the shared `damping_only` set (3.165, 179, 30.6 s). The steer code is not the cause: ded8b4e, the AI-38 rebase and
main give identical rows for the same file, and `test_flight_controller_equivalence.gd` holds `track_velocity` bit
for bit to the ded8b4e law.

| | old scenario before | old scenario after | new scenario before | new scenario after |
|---|---|---|---|---|
| speed_scaled dive contacts | 2 | 0 | 8 | 0 |
| damping_only dive contacts (unrecoverable 17) | 11 | 10 | 20 (3 recoverable) | 17 (0 recoverable) |
| landings docked, speed_scaled / damping_only | 200 / 200 | 200 / 200 | 200 / 200 | 200 / 200 |
| damping_only median gate-to-dock, mean low-throttle ticks | 32.7 s, 125 | 31.1 s, 88 | 32.7 s, 125 | 31.1 s, 88 |
| damping_only longest unsupported throttle-0 run (ticks) | 84 | 0 | 84 | 0 |
| step failures (A-68 limits), both models | 0 | 0 | 0 | 0 |

Files: `reports/ai38/{before,after}_{legacy,new}_sweep.csv` (before = this harness on the pre-AI-38 controller laws),
`reports/ai38/{before,after}_new_landing_failures.csv` (the 200 failed damping_only landings at the AI-05 anchors, which
still do not dock: lead_max 80; longest unsupported throttle-0 run 131 ticks before, 0 after).
