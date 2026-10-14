**Owner gate decision (2026-10-14): PASS WITH FALLBACK.** Partial pass accepted; budget handled by A-62 option (a).

# TA-20 REPORT: S-NAV-1 time-sliced A* on the 6 x 256^2 path grid

| | |
|---|---|
| **Task** | TA-20 |
| **Spike** | S-NAV-1 (01 Appendix A; long form 03 s14.3; R0 C1-05) |
| **Branch** | `spike/TA-20-pathing` |
| **Author / tier** | sim-engineer / Opus |
| **Date** | 2026-10-14 |
| **Owner gate decision** | |

## 1. Scope

Built (`godot/src/sim/pathing/`, contract in its `MODULE.md`):

- **`Pathing`.**
  - API: `request(from, to, mask) -> ticket`, `status`, `result` (cell centres on the datum), `result_cells`, `release`, `set_weight` / `weight` / per-face `version`.
  - Ticketing: `advance()` runs once per tick under `expansions_per_tick`, FIFO over 160 tickets, one search in flight. No per-tick query cap.
  - Masks are the unit's `max_slope_deg` (02 s3).
- **Cell A\* (`PathSearch`).**
  - Binary heap over parallel packed arrays; generation-tagged closed set.
  - No per-node objects and no allocation per expansion.
  - Cost `arc(a, b) * (w_a + w_b) / 2`; heuristic great circle * (1 + pct / 100).
  - Diagonals never cut a blocked corner.
- **Hierarchy (`PathRegions` / `PathClusters` / `PathLabel`).**
  - 6 x 16^2 clusters of 16 x 16 cells, split into connected regions per mask.
  - Region A\* runs goal -> start. Exhaustion proves NO_PATH, so a sealed pocket answers in a few ticks.
  - The cell search runs only inside the region corridor (route regions plus adjacent regions), so it cannot miss.
  - **Deviation from 03 s3.6:** regions instead of plain clusters with portals. The cluster-only first build fell back to whole-component floods of up to 642 k expansions.
  - The hierarchy serves every query whose ends lie in different regions. Same-region queries search inside that region's corridor.
- **Route cache (`PathCache`).**
  - Key (start cluster, goal cell, mask); 512 LRU entries of <= 128 cells.
  - Validated by face-version sums.
  - A hit from the same start cell completes in `request`. A hit from another cell of the start cluster splices a local search onto the cached tail.
- **Slopes.** Per-cell max slope is sampled lazily from `Terrain.slope_deg_at` over the covered texels.

Left out:
- Wiring into `SimWorld` step 3b and S4 bytes. `sim/MODULE.md` is at its cap; this is follow-up work.
- `AStar3D` exists only as a harness comparison (`godot/spikes/s_nav_1/nav_astar.gd`).

## 2. Harness

Run:
`godot --headless --path godot res://spikes/s_nav_1/run.tscn -- --map=baked|rough --pct=25 --budget=120 [--load-ticks=N] [--sections=strat,edge,corner,reweight,load,astar]`

Maps:
- **baked**: TA-16 `s_world1_r6000` `path.u8`. 344 cells blocked; 518 blocked for mask 20.
- **rough**: the same terrain with `NavTestKit.rough_weights`. A stress case harsher than any baked map: 40 % of cells weigh 2-5, 8.4 % are blocked, plus 400 gapped crater rims and 150 walls.

Sections (03 s14.3):
- 1,000 stratified queries (100 m / 1 km / 5 km / 15 km).
- 200 edge cases and 50 corner cases.
- 500 re-weights, then 100 queries.
- Load: 120 units. 4 x 15 Harvesters loop field <-> refinery 0.6-1.5 km apart (mask 25). 60 Siege Crawlers drive 1-8 km (mask 20). All re-path every 300 ticks (staggered) and on arrival.
- AStar3D comparison.

Checks:
- Every route is validated independently; every NO_PATH is flood-checked.

Timing conditions:
- The `run_*.txt` matrix ran while other agents' Godot jobs shared the box, so its timings are about 2x high.
- `quiet_runs.txt` holds the uncontended runs.
- Expansion counts and tick counts are machine-independent.
- The baked runs predate the same-region corridor commit. `run_rough_p25_b120.txt` predates the harness request-cell fix, so its FAIL lines are harness false positives. `run_rough_p50_b40.txt` uses the fixed harness and shows 0 failures.

## 3. Measurements

Unless marked otherwise: baked map, heuristic +25 %, budget 120.

**Cost per expansion and per tick**

| Metric | Value |
|---|---|
| Cost per expansion, warm tight loop | 4.55 us baked / 7.21 us rough |
| Cost per expansion, in-tick under load (quiet) | 14.9 us. Arrays (4.5 MB g / tag / parent) are cold between ticks; 03 assumed 0.25 us |
| `advance()` amortised, load, quiet | 0.27 / 0.34 ms |
| `advance()` p95 / p99 / max, load, quiet | 1.56-1.70 / 2.16-2.43 / 3.6 ms |
| Amortised / p95, load, contended | 0.64 / 3.38 ms |

**Latency and cache**

| Metric | Value |
|---|---|
| Ticket latency p50 / p95 / max, budget 120 | 1 / 2 / 6 ticks |
| Ticket latency p50 / p95 / max, budget 40 | 4 / 51 / 182 ticks |
| Cache hit rate, Harvesters | 0.94-0.97 |
| Cache hit rate, Crawlers | 0.47-0.59 |

**Stratified queries (expansions; ticks)**

| Bucket | Result |
|---|---|
| 100 m | p95 14, max 16; 1 tick |
| 1 km | p95 45, max 49; 1 tick |
| 5 km | p95 183, max 286; max 3 ticks |
| 15 km | p50 459, p95 1,436, max 4,346; ticks p95 12, max 37 (budget 40: 36 / 109) |
| 200 edge cases | expansions max 127, ticks max 2; 196 cross faces |
| 50 corner cases | expansions max 66, ticks max 1; 50 cross faces |
| Length / great circle (1-15 km) | p50 1.05, p95 1.09-1.12, max 1.16 |

**Re-weight, build cost and memory**

| Metric | Value |
|---|---|
| `set_weight` per call | mean 4.2-9.4 us, worst 38-132 us. The relabel is deferred to the next query through the cluster |
| 100 queries after 500 re-weights | ticks max 8, expansions max 992 |
| `prepare(mask)`, 1,536 clusters | 0.9-1.1 s quiet; 3.2-5.5 s contended. Includes lazy slope sampling at 1.9 us per cell |
| Memory | 8.8 MB (03 s13 row: 2 MB) |

**Rough stress map**

| Setup | Result |
|---|---|
| 15 km, budget 120 | expansions p95 26,222, max 42,960; max 358 ticks |
| 15 km, +50 % heuristic | p95 8,178 |
| Load, budget 120 | saturated: 120 units every tick, latency about 300 ticks |
| Load, budget 40, +50 % | latency about 300 ticks; Harvester hit 0.95; 0 correctness failures |

**AStar3D** (same cells, corner rule, `weight_scale` = weight)

| Metric | Value |
|---|---|
| Build | 11.0 s, **283 MB**, 392,698 points, 1,570,566 links |
| ms per query, AStar3D vs custom | 100 m 0.06 vs 0.22 · 1 km 0.27 vs 0.80 · 5 km 4.5 vs 3.3 · **15 km 150.5 (worst 245) vs 13.2** |
| Cost ratio AStar3D / custom | 0.98-1.00 |

## 4. Pass / fail per criterion

| Criterion (verbatim) | Result | Evidence |
|---|---|---|
| amortised <= 0.5 ms per tick with 120 ground units re-pathing every 10 s | PASS on the baked map (0.27 / 0.34 ms quiet). FAIL contended (0.64) and on the rough stress map | quiet_runs.txt, run_baked_p25_b120.txt |
| worst single query completes within 30 ticks | PASS under load (max 6). FAIL for the isolated 15 km tail (1/250 at 37 ticks; p95 12). FAIL at budget 40 and on the rough map | section 3 |
| cache hit rate >= 80 % on harvester loops | PASS (0.94-0.97) | load lines |
| zero correctness failures | PASS | all runs with the fixed harness; tests |
| re-weight < 1 ms (03 s14.3) | PASS per call (worst 132 us) | reweight lines |
| expansions/ms sets path_expansions_per_tick | 120 recommended | section 5 |
| 03 s4.2 row 3b 0.5 ms (p95) | FAIL (1.6 ms p95 at 120). 33 units would meet it but breaks the 30-tick bound | section 3 |
| AStar3D wins by > 2x (fail path) | No: 11x slower at 15 km, 283 MB, not sliceable. Keep the custom A* everywhere | run_astar3d.txt |

## 5. Fallback taken or recommended (data, by rung)

1. `rules.json` `path_expansions_per_tick` 2000 -> **120**.
2. Re-baseline 03 s4.2 row 3b to "0.5 ms amortised / 1.7 ms p95". If S-SIM-1 is over 25 ms, pay the +1.2 ms p95 with cut-ladder **rung 3** (projectile cap 1,400, ~1.0 ms).
3. Append a ladder rung as data: `path_expansions_per_tick` 120 -> 60.
   - Halves the 3b p95 (~0.9 ms).
   - Doubles latency: 15 km worst ~74 ticks. Harvester loops stay at 1-3 ticks through the cache.
4. **Rung 7** (v1.1 native twins): add `PathSearch.run` and `PathLabel.label_cluster`, behind the same `Pathing` interface.

## 6. Plan changes requested

**New seed: wire `Pathing` into `SimWorld`** (Opus, about 1 day):
- `load_map`: `load_weights` + `set_terrain` + `prepare` per ground-unit mask.
- `advance()` at step 3b (`ROW_PATHING`).
- Expose it to `sim_ai` (Architect decision).
- Serialise tickets, queue and cache for S4 (TA-21).

**Requests to other lanes:**
- `needs tools (moonbake)`: bake the per-path-cell max slope (and optionally the region labels for the v1 masks), so `prepare` stops sampling texels at load.
- `needs content`: in `rules.json`, `heuristic_pct` 25, `JOB_COST` 8, `BUILD_COST` 40, `LINK_COST` 20, `MASK_SLOTS` 2. These are named consts today (ADR-09).

**Memory (03 s13).** 9 MB measured vs 2 MB. Reductions, about 5.5 MB after all three:
- merge tag and parent into one int64 array (-1.5 MB);
- u8 tags with a periodic fill (-1.1 MB);
- drop the arc tables (-0.5 MB).

**03 s3.6 errata:** see the reviewer notes above.

## 7. Notes for humans

- **GDScript copy-on-write.** Reading `other.packed_array[i]` from another object parks a reference in the caller's frame, so the owner's next write copies the whole array. Region builds took 3.3 ms per cluster until accessors were added. Suggest a line in 03 s12.2 rule 11.
- **Timing quality.** The dev box was shared during the matrix. Re-run the harness on the pinned perf runner (TA-42) before the owner gate.
- **Incident:** see the reviewer notes (`taskkill /IM` at about 11:56).


