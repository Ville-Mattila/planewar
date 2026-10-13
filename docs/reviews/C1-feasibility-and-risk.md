# C1 - Critic review: technical feasibility, performance and risk

| | |
|---|---|
| **Project** | PLANEWAR (codename) |
| **Document** | C1 - Stage-2 critic review, lens: feasibility, performance, risk |
| **Status** | Review v1 (stage 2 review) |
| **Date** | 2026-10-09 |
| **Inputs** | 01 (spine), 02-08 stage-2 drafts, R1/R2/R3 research |
| **Output** | Issues C1-01..C1-26 (each with docs, severity, likelihood, impact, required fix), a reconciled server tick budget, a consolidated risk register, and the five riskiest assumptions mapped to the spikes that retire them |

**Severity.** Blocker: the plan cannot be executed as written, or a hard platform constraint is violated. Major: a contradiction, missing piece or wrong number that would cause rework. Minor: clarity or polish.
**Likelihood / impact.** H/M/L, judged for "if the docs ship unchanged".

---

## 0. Verdict in one paragraph

The architecture is sound in shape: server-authoritative SoA sim, one control path, tiered codec, baked terrain and data-driven content. It is also well suited to agent lanes. Five things will not work as written:

1. **Offline Skirmish on web and mobile.** It runs the whole server sim, 7 Commander bots and the client renderer on one thread. No document budgets this and no spike tests it.
2. **The server tick budget does not close.** The docs' own unit costs exceed 25 ms once three items are counted: the projectile-terrain test, A* queries and per-client codec work. S-SIM-1 cannot detect this because it uses stubs sized to the assumed budget and runs on a desktop core rather than the VPS.
3. **Gun aim under CF transport.** Slugs carried along the curve miss a co-altitude target that is aimed at visually: by 13 m at 400 m and 53 m at 800 m.
4. **The CF flight model has no lift.** Level flight at cruise needs about 29 degrees of nose-up angle of attack. Separately, 03 and 05 disagree on landing attitude.
5. **Planet meshing on single-threaded web and mobile.** GDScript chunk builds cost several times the 2 ms/frame web budget, so Chase flight at boost speed outruns the LOD.

The bandwidth proof checks out arithmetically. The backend is feasible, but it is heavy to operate for a small team. Contract drift between 02/03/04/05/07 is the main agent-execution risk.

---

## 1. Arithmetic checks performed

| Item | Doc | Result |
|---|---|---|
| Per-step tick budget sums to 25.0 ms | 03 s4.2 | Sum correct (0.8+0.4+5.5+2.4+3.0+2.0+1.6+4.2+1.2+0.8+1.1+2.0 = 25.0). **Row-internal arithmetic fails twice.** Step 8 is 2,000 x 4 x 0.4 us + 600 x 2 us + 300 x 0.4 us = 4.5 ms against a 4.2 budget, and it omits the projectile-vs-terrain test (2,000 x `height_at` at 2 us = 4.0 ms). Step 12 is 8 x (40 + 100 + 67) x 1.5 us = 2.5 ms (or 3.7 ms as written, with B at full rate) against a 2.0 budget. |
| Server tick split | 04 s7 vs 03 s4.2 | Inconsistent. 04 gives sim 18 ms + snapshots 4 ms + 2 ms; 03 gives events+snapshots+replay 2.0 ms and the sim the rest. 04 s4.1 says tiering costs "about 1 ms per client" (8 ms for 8 clients), but 04 s7 says 0.2 ms per client. |
| AI budget | 05 s10 vs 03 s4.2 | 05: 6.0 ms (act 3.2, think 1.8, commander 0.7, threat 0.3). 03: 7.9 ms (think 5.5 + act 2.4). Compatible, but **A* is counted by neither**: 03 says "inside the 5.5 ms think slice", 05 says "counted in sim Pathing". The S-NAV-1 pass bar is a 5 ms median per query, at 2 (03) or 4 (05) queries per tick. |
| Bandwidth proof 24,035 B/s | 04 s4.6 | Every row recomputed; the sum is correct. Assumption gaps: RTT about 100 ms (residuals grow with RTT), and DR has no gravity term (bombs are not "~0 bytes"). See C1-19. |
| POS_SMALL range | 04 s3.4 | i8 x 12.5 cm = **+-15.9 m** (U: +-31.75 m), not "+-1.6 m / +-3.2 m". |
| Depth precision table | 03 s7.6 | Correct: `z^2/(near*2^24)` reproduces 0.10 m at 1,100 m with near 0.7 and 0.58 m at 14 km with near 20. |
| Chunk memory, 72 KB per chunk | 03 s7.3 | Correct. |
| Mobile frame draws 380-430 vs 400 | 07 s5.3 | Correct; ART-A1 is justified. |
| Replay 59 KB/s raw, 18-26 MB per 30 min | 04 s13.1 | Plausible; the target is tight, as the doc says. |
| Cost, EUR 900/yr | 04 s12.4 | Arithmetic correct. The CPU assumption is wrong (C1-08). |
| Level-flight equilibrium | 01 s3.1.1, 03 s5.3 | With `k_up = 0.1`, holding altitude at about 108 m/s needs **theta ~ 29 deg** nose-up. Check: T cos(theta) = k_up v sin^2(theta) and T sin(theta) + k_up v sin(theta) cos(theta) = g give theta = 30 deg, T = 3.1 m/s^2 and a vertical term of 6.2 m/s^2. The result does not depend on `a_thrust`. |
| Slug curvature miss | 01 s3.1.1/3.1.3, 02 s4.2, 03 s5.4 | A transported slug keeps its flight-path angle to the local horizontal. Aimed along the line of sight at a co-altitude target at distance d, it misses low by about d^2/(2R): **13 m at 400 m, 35 m at 650 m (05 `fire_range_m`), 53 m at 800 m.** The Dart bounding radius is 6 m. |
| Chunk build cost | 03 s7.4 | 03 claims "about 1.2 ms on PC-mid", but the 1,225 `height_at` calls alone cost 2.45 ms at 03's own 2 us figure (s6.2). |

---

## 2. Issues (most severe first)

### C1-01 Blocker. Offline Skirmish/Campaign on web and mobile runs server sim + 7 bots + client on one thread, with no budget and no spike
**Docs:** 01, 03, 05, 06, 02 | **Likelihood H, impact H**

- **Workload.** 01 s9.3 runs offline modes as an in-process `ServerSession`. 03 s11.1 forbids threads everywhere, and the 01 Q2 web funnel is "Skirmish vs AI".
- **Sim cost.** Scaling 03 s4.2's own optimistic unit costs to Reduced caps (640 entities, 1,000 projectiles) gives about 12 ms per tick on a 3 GHz native core. That is about 36 % of a core at 30 Hz.
- **Platform scaling.**
  - GDScript in wasm is expected to run 1.5-2.5x slower (unmeasured; R2 s4.2 has no benchmark). That makes web-desktop 18-30 ms per tick, which already exceeds a 16.7 ms frame before any rendering.
  - Android-mid and web-mobile are roughly 0.4-0.5x a desktop core. There the sim alone needs 25-60 ms per tick, so 30 ticks/s is impossible and the clock slips (03 s12.3).
  - Native mobile at 640 entities holds one big core at 70 %+ for 25 minutes, and thermal throttling follows.
- **Gaps in the docs.** Only 05 s10 gives an AI budget for this case (3.5 ms). No other doc budgets the in-process case. S-WEB-1 (03 s14.4) runs 200 ships with no sim. 01 s9.3 also routes offline play through `NetSimView`, which means the snapshot codec encodes and decodes in-process. 03 s10.1 instead says `LocalSimView`.

**Mitigation the docs should adopt.**
1. Add a spike, S-WEB-2 "in-process skirmish": `ServerSession` + `ClientSession` + renderer + 1/3/7 Normal bots at Reduced caps, measured on web-desktop, web-mobile, Android-mid native and iPhone 11.
2. Add a **Lite** caps profile for single-thread offline play.
3. Make offline play read `LocalSimView` directly, with no codec.
4. Allow the native mobile offline server to run on one worker thread. This is an ADR-06/03 D3 amendment, and web keeps Lite caps.

### C1-02 Blocker. The server tick budget does not close, and S-SIM-1 as specified cannot reveal it
**Docs:** 03, 04, 05, 01 | **Likelihood H, impact H**

Unbudgeted or under-budgeted items:
1. Projectile-vs-terrain test, about 4 ms (03 s6.1 row 2 is not in s4.2).
2. A* queries: 2-4 per tick at a 5 ms median, counted by nobody (see C1-05).
3. Snapshot tiering and encode. 03 s4.2 step 12 is over its own row. 04 s4.1 says 1 ms per client for tiering alone. A realistic GDScript encode (smallest-three bit packing, DR residual against the per-client baseline, baseline write-back) is 3-6 us per evaluated record, against 1.2-1.5 us assumed. That is about 1,650 evaluations per tick for 8 clients.
4. The 10 Hz replay frame: about 450 records on every third tick. The 10 s tier-C keyframe encodes 700 records for one client on its tick. Both are spikes that land in p95.
5. `Spatial` rebuilds `Dictionary[int, PackedInt32Array]` every tick, which is allocation-heavy in GDScript.

The S-SIM-1 harness (03 s14.1) uses a stub autopilot sized to "~30 us", 1.5 ms of Commander busy-work and a stub codec "writing 8/6/4 bytes per entity". It therefore measures the assumptions, not the code. It runs on a desktop "3 GHz class" core, not on the shared-vCPU VPS that production uses (C1-08).

**Mitigation (re-baselined budget in Section 3).**
- S-SIM-1 runs the real `SnapshotCodec` + `Interest` + `ReplayWriter` once NET-06/NET-08 exist, or a codec prototype with the real record formats.
- It also runs the real projectile-terrain test and time-sliced A*, on the target VPS SKU with 6 concurrent instances.
- Use a shared per-tick quantisation cache and a flat counting-sort hash.
- Make cut-ladder rungs 1-3 the expected default, not a contingency.

### C1-03 Major. CF-transported gun slugs miss what the player aims at
**Docs:** 01, 02, 03, 05, 06 | **Likelihood H, impact H**

- **What the docs say.** 02 s4.2 says "All projectiles are CF-transported". 03 s5.4 transports slugs and drops gravity "so no lead/drop sight is needed" (03 AR-4).
- **What happens.** Transport keeps a slug's flight-path angle to the local horizontal constant. A target at the same altitude sits below the boresight by d/(2R) radians. A slug aimed at it visually therefore misses low by about d^2/(2R): 13 m at 400 m, 35 m at the autopilot's 650 m `fire_range_m`, and 53 m at the 800 m range.
- **Who is affected.**
  - Autopilot lead solvers using straight-line intercept (05 s6, `aim_lead`).
  - Turrets aiming along the chord (02 s4.4, 700 m Autocannon).
  - The rail slug at 2,500 m: sagitta 520 m.
  - Human aim on every input class.
- **Why it slips through.** S-FLIGHT-1's balloon targets at short range would not expose it.

**Mitigation:** slugs, flak shells and rail slugs fly **straight in the world frame** (no transport, no gravity). This is also cheaper: no `Sphere.transport` per projectile per tick. Bombs stay CF + g with the bomb sight, and rockets stay guided.

### C1-04 Major. The CF model has no lift: level cruise needs ~29 deg angle of attack, and landing attitude is contradictory
**Docs:** 01, 02, 03, 05, 06, 07 | **Likelihood H, impact H**

**(a) Angle of attack.**
- The only vertical "grip" in 01 s3.1.1 is body-up damping `k_up = 0.1 /s`. Equilibrium (Section 1) needs about 29 deg nose-up at about 108 m/s, whatever `a_thrust` is.
- The thrust efficiency fade means a ship cannot hold altitude at exactly `v_cruise`, so the TA-12 acceptance "level flight at cruise holds altitude +-1 m over 60 s" is ill-posed.
- 05 s5.2 quietly absorbs this with an integrator clamped at +-0.5, which may saturate.
- A nose-high cruise attitude undermines "feels like a plane" (P2). It also makes the chase camera's head-up rule and the boresight disagree with the flight path.

**(b) Landing attitude.**
- 03 s6.4 tests `fwd.dot(up_pad)` "within 25 degrees of perpendicular to the pad normal", which is a level landing.
- 05 s5.5 and OQ-1 read 01 as a tail-down powered landing, with the thrust axis within 25 deg of the normal.
- 06 s6.4 shows "pitch from pad normal".
- With forward-only thrust and `k_up` damping, a level landing at <= 15 m/s horizontal cannot arrest sink. Only a nose-high or tail-down landing is physically possible in the current model.

### C1-05 Major. A* query cost is unbudgeted and the per-tick query caps disagree
**Docs:** 03, 05 | **Likelihood H, impact M-H**

- The S-NAV-1 pass bar is a 5 ms median and 20 ms worst per query (03 s14.3, 01 App. A).
- 03 s3.6 allows 2 queries per tick, while 05 s5.7 allows 4 per tick.
- At the pass bar, 2 queries are 10 ms: 40 % of the tick, which neither budget counts.
- Harvester routes are highly repetitive (field to refinery), so caching is the natural fix.

### C1-06 Major. GDScript chunk meshing cannot keep up on single-thread web and mobile in Chase at boost speed
**Docs:** 03, 01 | **Likelihood M-H, impact H** (visible LOD holes or hitches in the core flight experience)

**Build cost.** Per chunk: 1,225 `height_at` (2.45 ms at 03's own 2 us), 1,221 `face_uv_to_dir` (two `tan` + normalize), normals, then packing four arrays and `add_surface_from_arrays` (0.4 ms). Realistic costs are 4-8 ms on PC-mid, 6-12 ms on web-desktop and 10-20 ms on Android-mid. 03 assumes 1.2 / 2.5 / 3 ms.

**Demand.** The web ms cap is 2.0 ms per frame. At a 10 ms build that is about 6 builds/s at 30 fps, and the scheduler as written ("a build that would exceed it waits") would never start one at all. At 160 m/s boost, the 370 m depth-6 split ring advances one 147 m chunk every 0.9 s, which needs about 9 builds per second.

### C1-07 Major. The possessed unit is rendered at 30 Hz tick poses (judder at 60 fps)
**Docs:** 03, 04, 06 | **Likelihood H, impact M-H**

- `EntityViewPool.set_local_override(id, p, b)` (03 s10.1) takes the predicted state from `Prediction`, which advances once per `_physics_process` (30 Hz).
- `physics_interpolation=false` (03 s1.1), and nothing interpolates the predicted ship between ticks.
- At 110 m/s that is a 3.7 m step every other frame, and the chase camera follows the ship. This is the one object the player stares at.

### C1-08 Major. Server CPU is validated on a desktop core but deployed on shared vCPUs (6 matches per 8-vCPU CPX-class host)
**Docs:** 01, 03, 04 | **Likelihood H, impact H** (ticks over budget in production, or a doubled host count)

- **Testing vs production.** S-SIM-1 measures one 3 GHz desktop core (03 s14.1). 04 s12.4 prices "CPX-style shared vCPU" hosts with 6 warm + 1 spare GDScript processes per 8 vCPUs.
- **Expected shortfall.** Shared vCPUs are hyperthreads with steal time. Six or seven saturating processes on 8 threads (about 4 physical cores) typically deliver 55-75 % of a boosting desktop core per thread. A 25 ms desktop p95 then becomes about 33-45 ms in production.
- **Oversubscription.** The spare process (04 s9.2) allows 7 concurrent PLAYING matches.

### C1-09 Major. Four of eight start slots sit exactly on cube-face seams
**Docs:** 01, 03, 07 | **Likelihood H, impact M**

- **Geometry.** ADR-03 points +X at slot 0, and the 03 s2.5 equatorial faces are centred at longitudes 0/90/180/270. Slots at 45 deg steps (01 s5.7) put slots 1, 3, 5 and 7 exactly on cube edges.
- **What crosses the seams.** Every Core footprint, build grid, flatten disc, path cell, hash cell and depth-6 chunk at those bases straddles two faces.
  - 03 s3.6 footprints are "axis-aligned cell rectangles" within a face.
  - The renderer's flatten sites and skirts meet seams.
  - Interest-cell ENU encoding switches cells.
- **Consequences.** Half the bases exercise every edge-case path while the other half exercise none. That is a bug magnet and a fairness concern (P5). 07 s9.1 edits a wedge "between bases at lon 0 and 45", which builds the problem in.

### C1-10 Major. Contract drift between docs will produce incompatible code from parallel lanes
**Docs:** 02, 03, 04, 05, 07, 01 | **Likelihood H, impact M-H**

Conflicts found (each will create a schema, def or API mismatch the first time two lanes integrate):

| # | Conflict | Resolution to apply |
|---|---|---|
| a | ShipDef field names: 02 s2.2 (`v_cruise, v_boost, boost_duration_s, v_dive_max, a_thrust, pitch_rate_dps, yaw_rate_dps, roll_rate_dps, flip_duration_s, flip_cooldown_s`, `k_side`/`k_up` per ship, `flight_common`) vs 03 s5.1/s9.2 (`cruise, boost_speed, boost_s, dive_max, rate_pitch, flip_s`, `k_side`/`k_up` in `rules.json`) | 02 names win (02 owns values). 03 s5.1, s5.3 pseudocode and s9.2 rename. `k_side`/`k_up` are per-ship fields with `rules.json` defaults. |
| b | Dart `a_thrust`: 02 = 24, 03 = 45 m/s^2 | 02 wins. 03 s5.1 cites 02. |
| c | `step_ship` signature: 01 s9.4 `(p, v, b, input, def, dt)`, 03 s5.2 `(s: ShipState, input, def, rules, terrain, dt)`, 04 s5.3 calls the 01 form | 03 form is canonical. 04 s5.3 pseudocode updated. 01 s9.4 note "superseded by sim/MODULE.md". |
| d | Slug gravity: 02 s4.2 `gravity: true`; 03 s5.4 none | Per C1-03: no gravity, no transport. |
| e | Rail: 02 1,500 m/s with 1.7 s flight (counter = jinking); 03 s5.4 4,000 m/s hitscan-equivalent | 02 wins (design counter). 03 s5.4 updated. |
| f | Map ids: 02 Halcyon Mare/Shatter Belt/Rimewater; 03 TA-16 `equinox_8` + two unnamed; 07 `cradle/anvil/glassfield` | 07 ids (`cradle`, `anvil`, `glassfield`) as directory ids. 02's names become `name_key` display names, mapped one-to-one by role (balanced/rugged/open). |
| g | Recipe schema and baker: 03 s8.1 (`features[]`, `start_slots[]`, CLI `python -I -m moonbake bake`, outputs `face{f}.height.u16`) vs 07 s9.1 (`symmetry`, `regions`, `craters.scatter`, `poles`, `boulder_fields`, CLI `tools/moonbake/bake.py --validate --preview`, outputs `heights_f{f}.u16`) | 03 owns the schema, CLI and file names. 03 s8.1 adds 07's `symmetry`, `craters.scatter`, `boulder_fields` and `poles` blocks. 07 s9.1/9.2 rewritten to 03 names. 07's M1-M10 checks become `moonbake validate` rules. |
| h | Terrain shader: 03 `planet_material.gdshader`; 07 `moon_terrain.gdshader` + `moon_light.gdshaderinc` | 07 names. |
| i | Path queries per tick: 03 2, 05 4 | Per C1-05 (node-expansion budget). |
| j | Who calls AI: 04 s7 `_bots.tick()` before `_world.step()`; 03 s4.1/05 s1.3 AI think inside `SimWorld.step()` via `set_ai_hook` | 03/05 win. 04 s7 step 4 becomes `_world.step()` only. |
| k | Adjutant command: 05 s8 "TOGGLE_ADJUTANT on TOGGLE_AUTO_REPLENISH" vs 05 AR-1 `SET_ADJUTANT`; absent from 04 s2.5 | `SET_ADJUTANT` (05 AR-1) added to 04 s2.5 and 03 `Command.Kind` (append-only). |
| l | Offline view: 01 s9.3 `NetSimView` over `LocalTransport`; 03 s10.1 `LocalSimView` | Per C1-01. |
| m | Landing attitude: 03 s6.4 vs 05 s5.5 | Per C1-04. |
| n | Palette atlas 2,048^2 (01 s8.2, 03 s9.3, s11.2) vs 256^2 (07) | 07 wins; 03 updated. |

### C1-11 Major. Test gates that cannot pass, or will flake on shared CI runners
**Docs:** 06, 07, 03, 04 | **Likelihood H, impact M** (agents chase red CI or disable gates)

1. 06 A11Y-01 requires CIEDE2000 >= 20 between team colours under simulated deuteranopia/protanopia/tritanopia. 07 s2.3's search found that the best 8-colour set reaches **12.0**, which makes 20 unattainable for 8 slots.
2. Perf gates run on GitHub-hosted shared runners, whose single-thread variance is commonly 10-25 %:
   - nightly ">20 % vs 7-day median" (ADR-11, 03 s4.4);
   - S-CI-1 soak `p95(min 10) <= 1.5 x p95(min 1)`;
   - `dual_listener_test` "p95 tick within budget" (04 s15.2);
   - `snapshot_budget_test` (deterministic, fine).
3. TA-12's level-flight criterion (C1-04).

### C1-12 Major. Backend operational load is heavy for a small team, and one component is not available as specified
**Docs:** 04, 01 | **Likelihood M, impact M-H**

- **The stack.** v1 runs Nakama + Postgres + FleetManager + FleetAgent + Caddy x2 + Prometheus + Loki/Promtail + Grafana + object storage + backups + key rotation (24 h HMAC) + a deletion cascade with cron retries.
- **Moderation console.** 04 s10.7 relies on a "Nakama console custom page". The open-source Nakama console offers no documented way to add custom pages (verify; treat as unavailable).
- **Estimates.** S-BACKEND-1 is sized at 3 days for Sonnet.
- **No restore test.** No task tests restoring Postgres from `pg_dump`.

### C1-13 Major. 08's v1 shortlist adds about 35 tasks of new sim/AI/UI surface before core feasibility is proven
**Docs:** 08 | **Likelihood M, impact M-H** (schedule)

- **New surface.** SL-2 (ESCORT/formation), SL-4 (route recorder plus AGL hold), SL-5 (rendezvous guidance, canisters as HP-bearing projectiles) and SL-6 (meteors, Almanac schedule in save/replay/start state) each add sim/AI surface, codec fields and perf load.
- **No perf accounting.** None of these has a line in the 03 s4.2/05 s10 budgets.

### C1-14 Major. No device profiling path for iOS from a Windows-only owner
**Docs:** 01, 03, 06 | **Likelihood M, impact M**

- **The gap.** 03 s12.1 plans Xcode Instruments for iOS, and iOS-mid is a first-class 30 fps target. Q10 defers a physical Mac, and GitHub macOS runners cannot run Instruments against a device. The S-IOS-1 pass bar is only "installable on a device".
- **The Xcode requirement.** R3 s1 requires Xcode 26+ / iOS 26 SDK for uploads since 2026-04-28, while ADR-12 pins `macos-15`. Unverified: whether the macos-15 image ships Xcode 26.
- **The privacy manifest.** R3 marks the Godot iOS template's `PrivacyInfo.xcprivacy` as unconfirmed.

### C1-15 Minor. Tier-C keyframe bursts (13.3 KB) cause head-of-line stalls on WebSocket clients
**Docs:** 04 | **Likelihood M, impact L-M**

Per client every 10 s, a 700 x 19 B reliable burst (04 s4.3) sits ahead of channel-2 snapshots on the single TCP stream. On a 1-2 Mbit/s mobile web link that is a 50-100 ms freeze, repeating every 10 s, in the predicted unit's corrections.

### C1-16 Minor. 03's web audio and memory plan contradicts 07
**Docs:** 03, 07 | **Likelihood H, impact L**

- **03.** s11.2 plans a 25 MB raw / ~20 MB Brotli `audio.pck`, and s11.3 reserves 120 MB of decoded PCM on web (also 03 R6).
- **07.** s8.3 specifies SFX <= 5 MB decoded, music as a separate pack <= 4 MB (mono 48 kbps Ogg), and `playback_type = STREAM` for music on web.

### C1-17 Minor. ART-A1 should be accepted, and 03's tier table aligned
**Docs:** 07, 03, 01 | **Likelihood H, impact L**

07's frame budget (380-430 draws) proves ART-A1. 03 s7.9 already moves to MultiMesh icons beyond 1,800-2,500 m, but its s13 "Entity views cap 400" on Low keeps the conflict.

### C1-18 Minor. POS_SMALL range misstated; DR omits gravity; bandwidth proof is single-RTT
**Docs:** 04 | **Likelihood H, impact L**

- **POS_SMALL range.** 04 s3.4 says "range +-1.6 m / +-3.2 m". At i8 x 4 quanta (12.5 cm / 25 cm), the true range is +-15.9 m / +-31.75 m.
- **Dead reckoning.** DR is `pos + vel * dt` with no `-g n` term, so bombs and falling wrecks cost 5 B per A/B tick, not "~0".
- **Single RTT.** The proof assumes the baseline is about 3 ticks old (100 ms RTT). At 150-250 ms (01 s8.3) and 3-5 % loss, baselines are 6-10 ticks old, so more records go POS_LARGE (+3 B).

### C1-19 Minor. `Spatial` rebuilds a `Dictionary[int, PackedInt32Array]` per tick
**Docs:** 03 | **Likelihood M, impact M** (folded into C1-02's budget)

03 s3.2/s3.6 rebuilds the hash as a dictionary of up to about 600 packed arrays per tick. That allocates and appends through Variant boxing, and it violates 03's own rule 12.2-2 in spirit. In Godot 4, packed arrays inside a Dictionary are copy-on-write values, so `dict[k].append(x)` does not mutate the stored array. That is a correctness trap as well as a cost.

### C1-20 Minor. Web heap: `INITIAL_MEMORY` 512 MB is risky on 2-4 GB Android devices
**Docs:** 03 | **Likelihood M, impact M** (tab crash at boot on low-end devices)

03 s11.3 sets 512 MB initial with growth allowed. Chrome on low-RAM Android can refuse large up-front wasm reservations.

### C1-21 Minor. Web time-to-gameplay estimate vs Poki behaviour
**Docs:** 06, 03 | **Likelihood M, impact L**

06 s9.1 estimates 16.5 s to gameplay on 20 Mbit/s. R3 s4 records that Poki players leave after about 10 s of loading. The estimate also leaves out wasm compile on web-mobile, which is slower.

### C1-22 Minor. Process pool can oversubscribe the host
**Docs:** 04 | **Likelihood M, impact M**

04 s9.2 keeps 6 warm + 1 spare that "starts when 5 are allocated". The spare can then be allocated, giving 7 playing matches on 8 vCPUs alongside Caddy (TLS for WS), agent and exporters.

### C1-23 Minor. Client CPU budget omits snapshot decode and prediction on mobile and web
**Docs:** 03 | **Likelihood M, impact L-M**

03 s10.2's per-frame budget lists planet, builds, entity sync, pools, UI and render. It leaves out `ClientSession.tick()`:
- decode of about 200-300 records per tick (with ENTITY_META held records);
- `NetSimView` interpolation for up to 1,000 entries;
- prediction replay of about 6 `step_ship` calls per snapshot.

On Android-mid GDScript this is plausibly 2-4 ms per tick.

### C1-24 Minor. Hard-coded radius regex and literal lint will misfire
**Docs:** 03 | **Likelihood M, impact L**

03 s12.4 D6 flags the regex `6000(\.0)?` anywhere in `src/**`. It will match legitimate numbers, such as an ore amount of `6000` in campaign scripts, `60000` ms constants, or the 6,000 m Commander icon band in 03 s7.9 if it is written as a literal. Agents will learn to evade the lint rather than fix the code.

### C1-25 Minor. Sustained thermal load on mobile online matches is untested
**Docs:** 06, 03 | **Likelihood M, impact M**

No spike runs a 25-minute session on Android-mid or iPhone 11. S-UX-1 is 10 minutes and S-WORLD-1 uses scripted 30 s paths. The downshift logic (03 s13, 06 s9.3) exists, but nobody measures whether Low tier is sustainable.

### C1-26 Minor. WebSocket-only web clients and fairness in mixed lobbies
**Docs:** 04, 06 | **Likelihood M, impact M**

- **Untested path.** S-NET-1 allows "WS clients may be native builds". A real browser main thread (rendering + decode + prediction on one thread) under 3 % loss with TCP head-of-line blocking is never measured, yet the web is the funnel and plays cross-play against ENet clients.
- **Matchmaking ignores it.** Queue keys (04 s10.4) separate input class but not transport.

---

## 3. Re-baselined server tick budget (proposal for 03 s4.2)

These are honest unit costs for typed GDScript. They are estimates until S-SIM-1 reruns with real code.

| Step | 03 budget | Proposed budget | Basis |
|---|---|---|---|
| 1 Poll + decode | 0.8 | 0.8 | unchanged |
| 2 Commands | 0.4 | 0.4 | unchanged |
| 3-4 AI think + act (05 s10) | 7.9 | 6.0 | 05's itemised budget with governor |
| A* (time-sliced) | 0 (uncounted) | 0.5 | C1-05 expansion budget |
| 5 Kinematics | 3.0 | 3.0 | unchanged |
| 6 Projectiles | 2.0 | 2.5 | straight-line slugs (C1-03) save `transport`; about 1.2 us x 2,000 |
| 7 Spatial | 1.6 | 1.2 | flat counting sort (C1-19) |
| 8 Collision incl. projectile-terrain | 4.2 | 5.0 | 4.5 as computed + 0.5 with the relief prefilter |
| 9 Combat | 1.2 | 1.2 | unchanged |
| 10 Economy/Production/Build | 0.8 | 0.8 | unchanged |
| 11 Vision | 1.1 | 1.1 | unchanged |
| 12 Events + interest + encode + replay | 2.0 | 4.0 | shared quantisation cache; tier C per team |
| **Total** | **25.0** | **26.5** | Over budget before measurement. Cut-ladder rungs 1-2 (03 s4.3) save about 2.3 ms and should be the **default** `sim_budget_profile`, not the contingency. |

This total is for a desktop 3 GHz core. On shared vCPUs (C1-08), multiply by 1.3-1.6 unless the host SKU changes.

---

## 4. Consolidated risk register (feasibility lens)

| # | Risk | L | I | Early signal | Mitigation (doc) | Retired by |
|---|---|---|---|---|---|---|
| K1 | Server tick > 25 ms p95 at 1,200 entities + 8 clients | H | H | S-SIM-1 (real codec) p95 | C1-02 budget; cut ladder default; caps 70/player; native twins v1.1 (Q6) | S-SIM-1 (amended) |
| K2 | Shared-vCPU hosts deliver 55-75 % of desktop single-thread | H | H | 6-instance soak on target SKU | C1-08 dedicated vCPU or 4 matches/host | S-SIM-1 + S-BACKEND-1 on target SKU |
| K3 | Offline web/mobile skirmish unplayable on one thread | H | H | S-WEB-2 sim ms/tick | C1-01 Lite caps, LocalSimView, native worker thread | S-WEB-2 (new) |
| K4 | CF flight feels wrong (nose-high cruise, landing attitude) | H | H | S-FLIGHT-1 AoA telemetry, questionnaire | C1-04 lift term A/B; landing decision | S-FLIGHT-1 (amended) |
| K5 | Guns miss under transport; aim solvers inconsistent | H | H | long-range hit test | C1-03 straight-line slugs | unit test + S-FLIGHT-1 |
| K6 | Web/mobile chunk meshing too slow for boost flight | M-H | H | ms/chunk on web-mobile | C1-06 texel-direct mesher, GPU displacement variant | S-WORLD-1 / S-WEB-1 (amended) |
| K7 | Predicted ship judders at 60 fps | H | M-H | S-FLIGHT-1 at 60 fps | C1-07 render-time interpolation | S-FLIGHT-1 |
| K8 | A* starves the tick | H | M-H | S-NAV-1 expansions/ms | C1-05 sliced A*, caching | S-NAV-1 (amended) |
| K9 | Contract drift breaks lane integration | H | M-H | first cross-lane PR | C1-10 CONTRACT-0 gate | TA-00 / CONTRACT-0 |
| K10 | CI gates unpassable or flaky (CVD threshold, perf noise) | H | M | red nightlies | C1-11 | CI-PERF runner |
| K11 | Cube-seam bases breed placement/render bugs and unfairness | H | M | seam test failures | C1-09 slot offset | 03 unit tests + S-WORLD-1 Z8 |
| K12 | Backend ops overload a small team | M | M-H | incident count, S-BACKEND-1 overrun | C1-12 minimal stack, runbook, restore drill | S-BACKEND-1 |
| K13 | WS-only web clients feel worse under loss | M | M | S-NET-1 browser numbers | C1-26 browser in spike; v1.1 WebRTC | S-NET-1 (amended), S-NET-2 |
| K14 | iOS perf unprofiled; Xcode/runner mismatch | M | M | first TestFlight | C1-14 Mac mini before beta | S-IOS-1 (amended) |
| K15 | Mobile thermal throttling in 25-min matches | M | M | 25-min device soak | C1-25 | S-UX-1 (amended) |
| K16 | Scope creep from 08 before the core is proven | M | M-H | roadmap burn-down | C1-13 gate | roadmap (09) |
| K17 | Web heap / audio decode blowup | M | M | S-WEB-1 heap peak | C1-16, C1-20 | S-WEB-1 |

---

## 5. The five riskiest assumptions and the spike that retires each

| Rank | Assumption | Why it is the riskiest | Spike that retires it (with the amendment it needs) |
|---|---|---|---|
| 1 | **A GDScript sim + AI + codec fits 25 ms p95 on one production vCPU at 1,200 entities, 2,000 projectiles and 8 clients** (ADR-06, 01 s8.4) | Everything else (caps, hosting cost, Q6 "no native code") hangs on it. The budget is already over on paper (Section 3), and the planned spike measures stubs on the wrong hardware. | **S-SIM-1**, amended per C1-02/C1-08: real codec/interest/replay, real projectile-terrain test, real time-sliced A*, run as 6 concurrent instances on the target VPS SKU. |
| 2 | **Offline Skirmish/Campaign can run in-process on single-thread web and on mobile** (01 s9.3, 01 Q2 web funnel) | The web funnel and the mobile free tier both depend on it. Back-of-envelope numbers say it fails by a factor of 2-4 on web-mobile, and no spike covers it. | **S-WEB-2 (new)**, per C1-01: in-process `ServerSession` + bots + client renderer on web-desktop, web-mobile, Android-mid and iPhone 11, at Lite and Reduced caps. |
| 3 | **The CF model feels like a plane and supports Triplane-style gunnery and landing** (P2, 01 s3.1) | Pillar P2 is the identity of the game. The model as written needs ~29 deg cruise AoA, misses aimed shots by tens of metres beyond 400 m, and has contradictory landing attitudes. | **S-FLIGHT-1**, amended per C1-03/C1-04/C1-07: A/B lift variants, straight-line slugs with targets at 200-800 m, render-time interpolation at 60 fps, both landing attitudes tested. |
| 4 | **GDScript planet meshing on single-thread web and mobile keeps up with Chase flight at boost speed** (ADR-04) | It is visible every second of flight on the weakest platforms. The cost estimate is 3-8x optimistic. | **S-WORLD-1 + S-WEB-1**, amended per C1-06: CPU-mesher vs GPU-displacement variants, boost path on web-mobile, holes/hitch metric. |
| 5 | **WebSocket-only browser clients give acceptable possessed-unit feel and fair cross-play under 3 % loss** (ADR-07, v1 web on WS) | The web is the acquisition funnel. TCP head-of-line blocking on the browser main thread is untested, and C1-15 keyframe bursts make it worse. | **S-NET-1**, amended per C1-26: at least 2 real browser clients (desktop + Android Chrome) under netem `TARGET`/`BAD`, with reconciliation error and frame-time stalls measured; feeds the S-NET-2 WebRTC priority decision. |

Honourable mention: **contract drift across 12+ parallel lanes** (C1-10). It is retired not by a spike but by a CONTRACT-0 gate before lanes open.

---

## 6. Summary of required spike amendments (for the roadmap)

| Spike | Amendment |
|---|---|
| S-SIM-1 | Real codec/interest/replay/A*/projectile-terrain; 6 concurrent instances on the target VPS SKU; report desktop and VPS figures. |
| S-WEB-2 (new, P0) | In-process skirmish on web and mobile at Lite/Reduced caps; sets the Lite cap values. |
| S-FLIGHT-1 | Lift A/B; straight-line slugs at 200-800 m targets; 60 fps interpolation; both landing attitudes; 2 recorded opponent passes for gunnery. |
| S-WORLD-1 / S-WEB-1 | Mesher variants; boost-path pass criterion; Z8 cube-seam base scene. |
| S-NAV-1 | Expansions/ms and amortised per-tick bar instead of a 5 ms median per query; cache hit rate on harvester loops. |
| S-NET-1 | Real browser clients; 150/250 ms columns. |
| S-BACKEND-1 | 5 days; restore drill; moderation admin page. |
| S-IOS-1 | Xcode >= 26 check; privacy manifest; device frame-time log. |
| S-UX-1 | 25-minute sustained-load run on Android-mid. |
| CONTRACT-0 (gate) | Reconcile C1-10 before lanes open. |

---

## 7. Required fixes per issue (for the reviser agents)

| Issue | Required fix (doc, section, change) |
|---|---|
| C1-01 | **(1) Lite caps.** 01 s8.1: add a **Lite** caps column for single-thread offline play (web; mobile until S-WEB-2 passes): <= 4 player slots, 30 units + 30 structures per player, 600 live projectiles, 60 wrecks. 8-slot offline is native PC/Deck only. 02 s14: default web/mobile Skirmish to 1v1/2v2. **(2) Offline view.** 01 s9.3: replace "The client renders from a NetSimView exactly as online" with "Offline, the client reads a LocalSimView of the in-process SimWorld directly (no snapshot encode/decode); the SimView contract test keeps behaviour identical." **(3) Native offline thread.** 03 s11.1/s12.4 D3: allow `Thread` only in `src/app/offline_host.gd` on non-web builds, running `ServerSession.tick()` on a worker (ADR-06/ADR-14 amendment). **(4) New spike.** 03 s14 + 01 App. A: add S-WEB-2. Pass bars: web-desktop 1v1 Normal at Reduced caps, p5 >= 45 fps; web-mobile 1v1 Lite, p5 >= 25 fps; Android-mid native 25 min at 30 fps without downshift. **(5) AI budget.** 05 s10: tie the 3.5 ms web AI budget to Lite caps, with autopilot think period 15 ticks offline on web. |
| C1-02 | **(1) Budget table.** Replace 03 s4.2 with the C1 Section 3 table: add "8b projectile vs terrain" with prefilter `if (len(p) - R) > RELIEF_MAX + radius: skip`, add "A* 0.5 ms", set step 12 to 4.0 ms, and make the default `sim_budget_profile` = rungs 1-2 of s4.3. **(2) S-SIM-1.** 03 s14.1: run with the real NET-06/NET-08 codec + interest + replay writer and real `Pathing`, on the target VPS SKU as 6 concurrent instances. Pass = each instance p95 <= 25 ms. **(3) 04 s7.** Delete the phase budget numbers and reference 03 s4.2. **(4) 04 s4.1.** Replace "about 1 ms per client" with the shared-cache design. `SnapshotCodec.prepare_tick(view)` quantises every visible entity once per tick (cell, e/n/u, quat_s3 full+coarse, vel, hp, flags) into packed arrays. C tiers are computed per team. Per-client work is gap + integer residual against the baseline. The replay writer reads the same cache. |
| C1-03 | **01 s3.1.3** (Guns bullet): append "Slugs, flak shells and rail slugs fly straight lines in the world frame (no parallel transport, no gravity); bombs and siege shells are CF-transported and fall under g; rockets are guided." Qualify 01 s3.1.1 item 2 accordingly (ADR amendment request). **02 s4.2**: set `gravity` false for `slug_light`, `slug_heavy`, `flak_shell` and `rail_slug`; add a `transport` column (true only for `bomb` and `siege_shell`); replace "All projectiles are CF-transported like ships" with the 01 sentence. **03 s5.4**: SLUG/FLAK/RAIL become `p += v*dt` with no transport; add unit test `test_slug_hits_coaltitude_target` (shooter at 300 m AGL, target at the same altitude at 200/400/650/800 m, fired along the line of sight: all hit). **05 s6** aim lead and **02 s4.4** turret aim: use straight-line intercept. **06 s6.3**: the gun reticle is the straight boresight. |
| C1-04 | **(a) Lift.** File a 01 s3.1.1 amendment: `k_up_eff = k_up_glide + (k_up_flight - k_up_glide) * clamp(v_fwd / v_cruise, 0, 1)^2`, with `k_up_glide` 0.1 /s (free-fall numbers unchanged) and `k_up_flight` 1.0 /s (anchor 0.6-1.5). This gives about 3 deg cruise AoA. 03 s5.3 implements both laws behind `rules.lift_model` (`damping_only` or `speed_scaled`) for an S-FLIGHT-1 A/B. 02 s2.2 adds `k_up_flight` per ship. 03 TA-12: replace the level-flight criterion with "autopilot-held level flight at 0.9 x v_cruise holds altitude +-1 m for 60 s; steady AoA reported, <= 6 deg under speed_scaled". **(b) Landing attitude** (owner decision; default tail-down per 05 s5.5). Rewrite 03 s6.4's attitude clause to "`fwd.angle_to(up_pad) <= landing_safe_pitch_deg` (thrust axis within 25 deg of the pad normal)". 02 `flight_common.landing_safe_pitch_deg` is documented as the thrust-axis angle. 06 s6.4 gauge reads "nose from vertical". 07 recipe cards get tail landing gear. S-FLIGHT-1 tests both readings. |
| C1-05 | **03 s3.6 and 05 s5.7**: replace "2 per tick" and "4 per tick" with one rule. Time-sliced A* with `rules.path_expansions_per_tick` (anchor 2,000; S-NAV-1 converts it to <= 0.5 ms); queued queries progress incrementally and are returned by ticket. Add a path cache keyed by (start cluster, goal cell), invalidated by a per-face change counter. **03 s4.2**: add an "A* 0.5 ms" row. **S-NAV-1 pass** (03 s14.3, 01 App. A): amortised <= 0.5 ms/tick with 120 ground units re-pathing every 10 s; worst query done within 30 ticks; cache hit rate >= 80 % on harvester loops. |
| C1-06 | **03 s7.3/7.4 mesher**: sample by face-local texel index. Depth 5 has vertex = texel; depth 6 is bilinear within a 2x2 texel block; depth <= 4 uses strided reads; never round-trip through `face_uv_to_dir` -> `height_at`. The per-depth direction table becomes the default. **Scheduler**: if the queue is non-empty and no build ran in the last 2 frames, run one build regardless of the ms cap. Restate the per-chunk cost as "unmeasured". **S-WORLD-1 (03 s14.2)**: add variant B, GPU vertex displacement. One shared 33x33 mesh; height faces as RG8-packed u16 textures sampled in the vertex shader; the CPU builds only AABBs. Choose per tier. **S-WORLD-1/S-WEB-1 pass**: add "boost path, 160 m/s at 30 m AGL for 60 s on web-mobile and Android-mid: no parent-shown hole > 1 s within 400 m of the camera; <= 1 frame > 50 ms per 10 s". |
| C1-07 | **04 s5.2**: add `Prediction.render_state(alpha: float) -> ShipState`, interpolating predicted ticks `input_tick-1` and `input_tick` with `alpha = Engine.get_physics_interpolation_fraction()`, plus the smoothing offset. **03 s10.1**: `set_local_override` is called every `_process` frame with that pose. **06 s5.2**: chase follows the interpolated pose. Test: at 60 fps, a Dart at 110 m/s shows per-frame displacement variance < 10 % of the mean. |
| C1-08 | **01 s8.4** Host row: "8 *dedicated* vCPU runs 6 matches (shared-vCPU hosts: 4)". **04 s12.4**: game host 30 -> about 60 EUR/month (dedicated class); restate year one at about EUR 1,250. **04 s9.2**: at most 6 PLAYING per host; the spare is allocatable only while PLAYING < 6. **03 s14.1**: S-SIM-1 also runs as 6 concurrent instances on the target SKU. |
| C1-09 | **01 s5.7 and the ADR-03 frame table**: keep +X, but place start slot k at longitude 22.5 + 45k deg (2- and 4-player maps use subsets), so no base lies within 10 deg of a cube edge. **03 s2.5** role column: "slot 0 at (u,v) = (0.75, 0.5)". **07 s9.1**: the wedge spans lon 22.5-67.5; add check M11 "no start-slot flatten disc intersects a cube edge". **03 S-WORLD-1**: add scene Z8, a structure cluster straddling an equatorial edge (Outposts may still land there). **03 TA-19**: add a unit test for `Build.can_place` with a footprint across a face edge. |
| C1-10 | Apply resolutions a-n of the C1-10 table in each named doc. Add seed **CONTRACT-0** (Opus, 1.5 agent-days, after S-CI-1 and before any lane opens): commit `tools/schemas/{ships,structures,weapons,projectiles,map_recipe}.schema.json` and `sim/MODULE.md` reflecting the resolutions, with CI checking that every doc example JSON validates. |
| C1-11 | **06 A11Y-01** test: "team-vs-team CIEDE2000 >= 11.0 under each simulated CVD and >= 20 under normal vision (07 s2.3 measured 12.0/25.1); relation colours ally/enemy/self >= 20 under CVD". **ADR-11 / 03 s4.4 / s12.1 / 04 s15.2**: perf and tick-p95 assertions run only on one pinned self-hosted runner of the target SKU. GitHub-hosted jobs assert correctness, plus same-job base-vs-head A/B with a 25 % threshold. **S-CI-1 soak criterion**: "slope of per-minute p95 < 2 % per minute". |
| C1-12 | **04 s10.1/s12.1/s14**: v1 stack = Nakama + Postgres + FleetManager (agent role as systemd-managed processes) + Caddy + Prometheus/Grafana; logs to journald with daily upload to object storage; Loki/Promtail move to v1.x. **04 s10.7**: the moderation console is a FleetManager-served admin page (`/admin/moderation`, admin token + IP allowlist) calling new Nakama RPCs `moderation_list` and `moderation_view` (add to s10.5) plus `sanction_apply`. Add OPS seeds: monthly restore drill (`pg_dump` to a scratch VM, RTO 2 h) and `server-ops/RUNBOOK.md`. Resize S-BACKEND-1 to 5 agent-days with Opus review. |
| C1-13 | **08 s3**: add "Scope gate: shortlist work starts after S-SIM-1, S-WEB-2 and S-FLIGHT-1 pass and the vertical slice (01 s3.2 loop, 1v1 vs Normal bot) is feature-complete. SL-1 and SL-3 are v1; SL-2, SL-4, SL-5 and SL-6 are 'v1 stretch' defaulting to v1.x." Each SL design states its per-tick cost at caps, to be added to 03 s4.2. |
| C1-14 | **01 Q10** default: acquire a Mac (mini class) before the first iOS performance milestone, not at TestFlight. **ADR-12**: "macOS runner image with Xcode >= 26 (verify macos-15 ships it, else macos-26)". **S-IOS-1 pass** adds: Xcode >= 26 build uploaded to TestFlight, `PrivacyInfo.xcprivacy` present, 10-minute device frame-time log. |
| C1-15 | **04 s4.3**: replace the TIER_C_ONLY burst with a rolling refresh. Each tick, FULL records for ceil(C_count/300) C entities, round-robin, go inside the snapshot (same 1.3 KB/s average). KEYFRAME(ALL) only on join, reconnect or stale ack. |
| C1-16 | **03 s11.2**: replace the `audio.pck` row with "music.pck <= 4 MB after menu (07 s8.3); SFX in core.pck ~2.4 MB". **03 s11.3**: web audio 120 -> 15 MB; update R6 and the web total. |
| C1-17 | **01 s8.1**: accept ART-A1. Add a row "Visible entity mesh nodes: 800 Standard / 200 on Reduced and Low tier; beyond the cap, Far MultiMesh pools". **03 s13**: entity views 200/400/800 by tier plus the far pool. **03 s10.1**: add the far-pool path. |
| C1-18 | **04 s3.4**: POS_SMALL range "+-15.9 m E/N, +-31.75 m U". DR = `pos_b + vel_b*t - 0.5*g*normalize(pos_b)*t^2` for gravity-bearing entities (bombs, unpowered ships). **04 s4.6**: add 150 ms and 250 ms RTT columns with the estimated POS_LARGE share. |
| C1-19 | **03 s3.2/s3.6**: the hash becomes `cell_start: PackedInt32Array` + `cell_items: PackedInt32Array`, rebuilt by counting sort over a `touched_cells` list, with no Dictionary. Add to 03 s12.2: "never mutate packed arrays stored inside Array/Dictionary (copy-on-write)". |
| C1-20 | **03 s11.3**: `INITIAL_MEMORY` 256 MB with growth to 1 GB. S-WEB-1 records boot success on a 3 GB Android device. |
| C1-21 | **06 s9.1**: portal builds use a fast start: Mission 1 first beat interactive within 10 s on 20 Mbit/s, deferring unused pre-warm and all music. S-WEB-1 measures wasm compile time on web-mobile. |
| C1-22 | **04 s9.2**: "when PLAYING + ALLOCATED = 6, no further allocations on this host; the replacement process starts on match exit". |
| C1-23 | **03 s10.2**: add "ClientSession tick (decode + NetSimView + prediction): PC 1.0 ms, mobile/web 3.0 ms per 30 Hz tick", measured in S-WEB-1/S-NET-1. |
| C1-24 | **03 s12.4 D6**: make the radius-literal rule a warning with an allowlist file `tools/d6_allow.txt`. It errors only on `6000`/`8192` literals combined with position/length variables in `src/sim/**` and `src/presentation/planet/**`. |
| C1-25 | **06 s13 S-UX-1**: add a 25-minute online match on Android-mid at Low tier (iPhone 11 when available). Pass: no downshift below Low, median >= 28 fps, temperature/throttle notes logged. |
| C1-26 | **04 s15.3 S-NET-1**: at least 2 of the 8 clients are real browsers (Chrome desktop, Android Chrome). Measure reconcile p95 and main-thread stalls > 100 ms under TARGET and BAD. **04 s10.4**: add `s_transport` to ranked tickets only if browser reconcile p95 > 2x ENet. |
