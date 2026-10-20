# Gain-tuning harness (AI-06)

Headless sweep of `FlightGains` (AI-05) and `LandingParams` (AI-09) keys under both `lift_model` values, a CSV
report, and the best gain set per model. Test code only: it reads `test/sim/ai/ai05_params.json` and
`ai09_params.json` as the baseline and never writes them. Adopting a recommended set is a content change
(`autopilots.json`, AI-19), not part of this harness.

```sh
python tools/gain_sweep.py --out reports/gain_sweep                  # full sweep, ~15-25 min on a laptop
python tools/gain_sweep.py --out reports/quick --stages base,confirm --seeds 20   # smoke, seconds
python tools/gain_sweep.py --summarise godot/test/tuning/reports                  # print a stored run
"$GODOT_BIN" --headless --path godot res://test/tuning/gain_sweep.tscn -- --out=/abs/dir [options]
```

Run `--import` once on a fresh checkout (the wrapper does it with `--import`).

## What is measured per candidate

| Family | Scenario | Metrics |
|---|---|---|
| step | AI-05 acceptance steps (turn +-30, climb 15, dive -15, mixed 20/10) for all five ship classes | steps outside 2.0 s / 15 % overshoot (dive under `damping_only`: 2.6 s / 20 %, R0 B.12 A-68), worst time, worst overshoot |
| dive | Dart, 10-45 degrees nose-down, 100-300 m above flat ground, deck-hold + PULL_UP rig (`TerrainFlightRig`), 12 s | terrain contacts (about 1 % at the anchors under `speed_scaled`) |
| landing | SC-04 geometry: 2-4 km out, 150-450 m, random bearing and heading, `LandingPilot` RETURN, 180 s | docked within R0 B.5 limits and without a scrape (A-70), crashed, median gate-to-dock, mean ticks with throttle < 0.2 in APPROACH / TRANSITION |

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
