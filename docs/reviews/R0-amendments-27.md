# R0 amendments 27: structure `up`, the landing band on a slope, basin vision, harvest distance `d`, the `ap_crawler` `siege` block, the opening book's default `when` (PM-06; BUG-3 PR #190 and AI-24 PR #193 Opus reviews; AI-49)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, subsection B.33 (append-only): A-157..A-163 added 2026-11-27. The B.1 `autopilots.json` sentence gains one clause (A-161). Parts B.2-B.32 are unchanged. No ADR is amended; no enumeration, signature, `deps.json` edge, wire layout, autoload, addon or thread change; `PROTOCOL_VERSION` and `SimSerialize.FORMAT` unchanged. |
| **Status** | Decided by the Architect 2026-11-27. A-161 (a required def block) and A-158 (a sim rule) are OWNER items and carry their default until the owner rules. |
| **Raised by** | PM-06: BUG-3 (PR #190) Opus review comment 7198733100, questions 1-3; AI-24 (PR #193) Opus review, contract questions 1-3; AI-49 ("after the Architect rules on the siege block"; R0 B.29 A-145 Limits). |
| **Decided by** | Architect (Fable), 10 s4.1 (a required def field and a changed sim rule are Changes: the Architect proposes, the owner approves) and 10 s4.3. |
| **Size** (10 s4.1) | Seven register rows, one B.1 clause, doc patches in 02 s8.2 / s8.4, 03 s3.7 / s6.4 / s7.6, 05 s6.7 / s7.3 / s11.2, five new tasks, one re-scoped task. The Architect edits no `godot/src/**`, no `godot/test/**`, no schema, no def, no `MODULE.md`, no `backlog.json`. |

Reading order: the B.33 rows in `docs/reviews/R0-resolution-register.md` are the binding text; this file is the why, the work lists and the backlog patch.

| # | Question | Decision in one line | Follow-up |
|---|---|---|---|
| A-157 | Radial `up` (built) vs normal `up` (Relay Stations) | Radial for every structure | GD-52 |
| A-158 | Off-centre landing on a sloped pad misses the band | The band follows the terrain where it rises above the deck | BUG-6 |
| A-159 | Structures in a basin no longer see ground units there | Intended: the ADR-05 horizon rule, now the same in a basin as on a plain | GD-53 (test pin) |
| A-160 | 02 s8.2 `d`: centre to centre or to the field edge? | Neither: the driven leg, dock stop to mining spot | GD-54 |
| A-161 | The `ap_crawler` `siege` block | Required, 12 keys, no defaults in code | AI-49 (re-scoped) |
| A-162 | Default `when`: `affordable` (05) or always true (code)? | 05 is canonical; a funds wait is never a stall | AI-50 |
| A-163 | SC-41's `t>=` prefix exemption; the 05 s7.3 book defects | Pending at 5:00 only for an Expansion pair waiting on the clock; 05 books patched | AI-50, AI-24, AI-25 |

## A-157 One rule for `up`: radial

**Decision.** Every structure has `up` = its footprint centre direction (`pos.normalized()`), whoever spawns it: `Build.stamp` / `place` (as built, `sim/build` B10) and `MapRelays` (GD-51 changes from `Terrain.normal_at`). `fwd` is the facing projected on the tangent plane there. Ground units and wrecks are not structures and keep their own rule.

**Why radial.**

- **Solar.** 02 s8.4: "`elev_deg` equals latitude, so a Solar Array must sit at least 52 m north of the equator for full output". That is only true with a radial `up`. `solar_band_deg` is 0.5, so `solar_factor` is close to a step at the terminator; a normal `up` on the 15 degree slope `build_max_slope_deg` allows would move that step by up to 15 degrees of arc, 1,570 m on this moon, in a direction the player cannot read from the map.
- **Pads.** A radial deck is level in the gravity frame. Tail-down landing (R0 O-2) and the tilt term of the landing band are measured against `up`; a tilted deck would ask a hovering ship to lean off its thrust axis.
- **Art.** 07 s4.2's foundation skirt is `0.27 x half_footprint` deep. tan(15 degrees) = 0.268: the skirt is sized for a level structure on the steepest buildable slope.
- **Sim.** `TurretSlew` already yaws about `pos.normalized()` (`sim/world` W9).

**Alternative.** Normal `up` for all structures: fails the four points above. No shipped bake has a Relay Station entry yet (GD-51 note), so nothing saved changes.

## A-158 The landing band on a sloped pad

**Facts.** The pad plane passes through `pos` with normal `up` (03 s6.1). The sim terrain under a pad is not flattened (ADR-04; the renderer's flatten is cosmetic, 03 s7.6). On ground of slope `a` the uphill terrain stands `off x tan(a)` above the deck, so a ship resting there has `alt > r + 0.5` once `off x tan(a) > 0.5`: 1.9 m off centre at 15 degrees, 5.7 m at 5 degrees (review, PR #190). It sits on the pad and never docks.

**Decision (OWNER, default applied).** The landing volume's upper bound follows the terrain where the terrain is above the deck:

`offset <= pad_radius_m` and `-(r + 0.5) <= alt <= r + 0.5 + g`, with `alt` = altitude above the pad plane and `g = max(0, (Terrain.surface_point(ship direction) - pos[pad]) . up[pad])`.

- On level ground `g` = 0: the rule is A-31 / A-109 unchanged, bit for bit. No constant is added; 0.5 stays.
- `g` is bounded by the placement rule: at most `pad_radius_m x tan(build_max_slope_deg)` = 2.7 m (Outpost, Pad, Hangar) or 3.2 m (Core, Relay Station).
- The lower bound, the deck half-space (A-109), the capturer exception (A-146) and the docked position `pos[pad] + up x r` are unchanged.
- Cost: one `height_at` for a ship that is inside a pad column and above the plain band; nothing per entity otherwise.

**Rejected.**

- *Sim-side flatten.* Terrain is baked and immutable (ADR-04); a per-structure height override would enter pathing, collision, save state and the net.
- *A pad-only slope limit.* The band needs `tan(a) <= 0.5 / pad_radius_m`, about 2.9 degrees. 03 s8 M2 lets even a slot area have a mean slope of 6 degrees, and Outposts go on unflattened ground, so many Outpost sites would be refused, for players and for `BuildPlanner`.
- *A deck at the highest footprint sample.* Moves every pad structure's `pos` or adds a deck offset (the pad plane has none, GD-15), and doubles the skirt 07 s4.2 needs.
- *A fixed wider band.* A ship would be judged as landed up to 3 m above a level deck, before it has finished braking; that changes landing grades on every pad.

## A-159 Basin vision: intended

**Finding.** Nothing new hides ground units in a basin. For a pair whose lower endpoint is at or below the datum, `Sphere.is_occluded_by_datum` (A-10) reduces exactly to "the higher endpoint is below the horizontal plane through the lower one": the foot of the perpendicular from the moon centre, when it lies inside the segment, is lower than both endpoints, so it is inside the datum whenever one endpoint is. A ground-level sensor at radius `r` therefore sees a target standing `h` above the same floor out to `sqrt(2 r h)`:

| Sensor at ground level | Harvester (`bounding_radius` 4.5) | Siege Crawler (7) |
|---|---|---|
| on the datum (r = 6,000) | 232 m | 290 m |
| on `cradle` slot 0's floor (r = 5,665) | 226 m | 282 m |

Before BUG-3, structures on `cradle` stood on the datum, 335 m above their own floor, and saw the whole basin. That was the defect; BUG-3 removed it.

**Decision.** Intended; no code change. 01 ADR-05 (01:476) stands: horizon occlusion against the datum, no terrain line of sight in v1. A base's answer to ground units beyond the horizon is the Sensor Mast, whose 1,200 m `deck_reveal_radius` ignores occlusion (01 s6.2) and covers the Siege Crawler's 1,000-1,150 m firing band, or any ship high enough: a Dart 600 m out is seen from 32 m above the floor.

**Known and unchanged.** Terrain above the datum gets a longer horizon (two ground-level points at +50 m see each other to about 1.5 km). That is the same ADR-05 simplification; slots of one map are symmetric, so it is fair within a match.

**Alternative (owner).** A structure sensor height (`sensor_height_m`, a new def field read by Vision) so that base sensors see ground units at range whatever the floor level. It changes Vision's pair test and every tower engagement; a v1.x candidate with terrain line of sight.

## A-160 Harvest distance `d`

**Decision.** 02 s8.2 already says "a field `d` metres (one way) from its Refinery dock". `d` is the one-way driven leg: from the Harvester's dock stop at the Refinery to its mining spot (the near-side spot, `spot_frac x radius_m` from the field centre toward the Refinery; BUG-4, PR #195). It is not the centre-to-centre distance and not the distance to the field edge.

- GD-12 and BUG-4 already measure it this way: brain-driven cycle 110.3 s at d = 450 (+1.7 %) and 137.7 s at d = 600 (+1.2 %).
- `cradle`: 600 m centre to centre (02 s9.2) is a driven leg of about 472 m (PR #193 review), T_trip 112.5 s. The table's 450 m row is that case, rounded: +3.7 %, inside GD-21's +-5 %. No table value changes.
- `tools/econ_model.py` prices the first trip at d = 600 from a standing start (86 s); the sim delivers at 68 s on `cradle` (BUG-4). GD-54 aligns the model.

## A-161 The `ap_crawler` `siege` block

**Decision (OWNER, default applied as A-93 and A-144 were).** `siege` is **required** on `ap_crawler`, all 12 keys required, `additionalProperties: false`; optional and unread on every other `ap_*`. The values are data; the content lane tunes them without a ruling.

| Key | Type, range | Value | Source | Replaces in code |
|---|---|---|---|---|
| `spot_min_m` | number, > 0, <= 5000 | 1000 | 05 s6.7 | `SIEGE_DEFAULTS[0]` |
| `spot_max_m` | number, > 0, <= 5000 | 1150 | 05 s6.7 | `SIEGE_DEFAULTS[1]` |
| `spot_slope_deg` | number, > 0, <= 45 | 10 | 05 s6.7 | `SIEGE_DEFAULTS[2]` |
| `relocate_bomb_m` | number, > 0, <= 1000 | 60 | 05 s6.7 | `SIEGE_DEFAULTS[3]` |
| `relocate_step_m` | number, > 0, <= 1000 | 150 | AI-18 | `SIEGE_DEFAULTS[4]` |
| `aim_tol_deg` | number, > 0, <= 10 | 1 | AI-18 | `SIEGE_DEFAULTS[5]` |
| `spot_samples` | integer, 1..64 | 24 | AI-18 | `SIEGE_DEFAULTS[6]` |
| `loft_tol_m` | number, > 0, <= 100 | 15 | AI-18 | `SIEGE_DEFAULTS[7]` |
| `solve_tol_m` | number, > 0, <= 100 | 2 | AI-18b | `SIEGE_DEFAULTS[8]` |
| `loft_iters` | integer, 1..16 | 6 | AI-18b | `CrawlerParams.LOFT_ITERS` (`siege_aim.gd:33`) |
| `solve_step_ticks` | integer, 1..4 | 2 | AI-18b | the `2.0 * k.dt` step in `SiegeAim._miss` and the `2.0 * p.dt` in `max_steps` |
| `relocate_tries` | integer, 1..16 | 6 | AI-18 | `for k: int in 6` in `CrawlerBrain._relocate` |

Cross-field rules (`validate_content`, one negative case each): `spot_min_m < spot_max_m`; `solve_tol_m <= loft_tol_m`; `[spot_min_m, spot_max_m]` inside the Crawler weapon's `[range_min_m, range_m]`. These are the three checks `CrawlerParams.from_content` already makes.

**Why required.** ADR-09: every sim-affecting constant lives in JSON. An optional block with defaults in `crawler_params.gd` keeps nine balance numbers in code. Precedent: A-86, A-93, A-144, A-145.

**Not siege keys (derived; do not copy them into the block).** `dt` (`rules.tick_hz`), `max_steps` (`siege_shell.lifetime_s / (solve_step_ticks x dt)`), `speed` (`siege_shell.speed_mps`), `range_m` / `range_min_m` (`siege_gun`), `radius` (`bounding_radius`), `barrel_rate` / `barrel_lo` / `barrel_hi` (`ground_units.json` `barrel_*`, A-151; read from the typed `GroundUnitDef` fields now that CONTENT-5 has landed), `turn_rate` (`ground_common.ground_turn_rate_dps`), the route-health strike counts (05 s5.7, shared with the Harvester).

**Public symbols (10 s4.1; A-156 precedent).** `CrawlerParams.SIEGE_KEYS` gains the three new names at the end. `SIEGE_DEFAULTS` and `LOFT_ITERS` stay in the file and in `sim_ai/brains/MODULE.md` with their values, marked deprecated in Open items, and are read by nothing. `CrawlerParams` gains `var loft_iters: int`, `var solve_step_ticks: int`, `var relocate_tries: int` (appends). A def without the block, or with a key missing or <= 0, makes `from_content` return null.

**Limits.** This rules `siege` only. A further `ap_crawler` key is again optional with a default or a contract question (A-145).

## A-162 The default `when` is `affordable`; a funds wait is never a stall

**The contradiction.** 05 s7.3: `"affordable"` (default). `OpeningBook`: an empty `when` is always true, so a step waiting for funds is "due", its stall clock runs, and after `stall_s` it is skipped (`SKIPPED_STALL`). PR #193 worked round this with `t>=215` gates derived from `stall_s`.

**Decision.** 05 is canonical.

1. An absent or empty `when` compiles as `affordable`.
2. A `build` or `produce` step with an explicit `when` is due only while it is also affordable. `order`, `raid` and `set_replenish` steps cost nothing and are unaffected.
3. So the stall clock (`commander` OB3) never counts a funds wait. It still counts every other wait of a due step: prerequisites, caps, queue space, locks.

Point 2 is where 05 is silent; it is the reading under which point 1 means something for the mandatory `when: presence` of an Outpost step. A step that waits for funds blocks the steps behind it (OB1) until the 5:00 hand-over; it is not skipped out of order.

**Alternative (owner).** The literal text: only an absent `when` gets `affordable`; authors write `presence&affordable`. Same interpreter cost, one more thing for every book author to remember.

## A-163 SC-41's exemption, the deferred tail, and the 05 s7.3 books

**SC-41.** "Completes without stall" (05 s11.2): at the hand-over every step is DONE or skipped by `skip_if_have`, except that an **Expansion pair** (an `order move` followed by a `build outpost` to the same site) may be PENDING when the cursor step **waits on the clock**. A step waits on the clock when its `when` is false at the hand-over and either (a) becomes true by advancing `t` alone, or (b) stays false at this `t` even with every other term true. The `begins_with("t>=")` test is removed.

| `when` at 5:00 | Verdict |
|---|---|
| `t>=330` | waits on the clock (a) |
| `t>=420\|ore>=900`, Ore 400 | waits on the clock (a) |
| `t>=270&ore>=900`, Ore 400 | **fails**: the clock is met, the step waits for Ore |
| absent (`affordable`), funds short | **fails**: the book does not fit the income |

**Deferred tail.** 05 s7.5 Expansion reads "the book's time". So a step whose time gate lies at or after `book_end_s` is legal only as the Expansion pair at the end of a book: the interpreter never runs it, and the reactive planner (AI-25) uses its gate. Any other step gated at or after `book_end_s` is dead data.

**05 s7.3 patch (applied in this PR).**

- (3a) `bulwark_standard`: the `relay_pylon` x 2 step is replaced by the home-trap Outpost pair, and the Extractor waits for `have:outpost>=1`, as in the other two books. The home Cold Trap is 1,500-1,700 m from the Core on all three maps (02 s9.2); a Core radius of 600 m plus two 250 m Pylons reaches 1,100 m.
- (3b) With 3a the home-trap Outpost is bulwark's first Outpost and the 6:00 checkpoint is reachable; the contested pair at `t>=330` is a legal deferred tail.
- (3c) Dead steps removed: vanguard `raid ... t>=300&have:dart>=3` (it also blocked the `ore>=900` alternative of the pair behind it) and foundry `reactor ... t>=600`. After the hand-over raids are the military manager's (s7.6, AI-27) and Reactors the Power rule's (s7.5).
- The listing is the doctrine intent; the shipped `build_orders.json` (AI-24) is the data, fitted to the sim's measured income.

No gate value is added or changed by this ruling. AI-24 may re-add a raid or a Reactor step with a gate before 5:00 if SC-41 shows the income pays for it.

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

Checked on `main` at db87dc4: GD-51, BUG-5, AI-49 are the highest GD / BUG / AI ids; GD-52, GD-53, GD-54, BUG-6, AI-50, A-157..A-163, B.33 and `R0-amendments-27.md` are unused. AI-24 and GD-22 are `todo` and each already has an `acceptance_append`; the text below is appended to it. AI-25 is `todo`.

```json
{
  "new": [
    {"id": "GD-52", "title": "sim: map-spawned Relay Stations get a radial up, as every built structure (R0 B.33 A-157)", "lane": "sim", "tier": "Sonnet", "size_days": 0.25, "depends_on": ["GD-51", "BUG-3"], "milestone": "M3", "acceptance": "MapRelays.spawn sets up = the entry's dir (radial), fwd = the facing projected on the tangent plane at dir (default Sphere.tangent_frame(dir).x) and pos = Terrain.surface_point(dir), as Build.stamp does (sim/build B10); a test on a sloped fixture asserts up == pos.normalized() within 1e-6 for every structure spawned by spawn_start_kit, Build.place and MapRelays; on a fixture map whose relay site slopes 10 degrees a Hauler lands tail-down and captures; Economy.solar_factor of a solar structure placed on a 15 degree slope equals the value at its latitude on level ground; sim/relay/MODULE.md and sim/build/MODULE.md B10 cite A-157; S4 round trip byte-exact, no FORMAT change (no shipped bake has a relay entry); no def or schema change", "docs": ["docs/reviews/R0-amendments-27.md", "03 s7.6", "02 s8.4"]},
    {"id": "BUG-6", "title": "sim: a ship resting off-centre on a sloped pad never docks: the landing band follows the terrain where it rises above the deck (R0 B.33 A-158)", "lane": "sim", "tier": "Opus", "size_days": 0.5, "depends_on": ["BUG-3"], "milestone": "M3", "acceptance": "Collision._ship_structure: for a not-DOCKED ship the landing volume of a pad-friendly structure is offset <= pad_radius_m and -(r + 0.5) <= alt <= r + 0.5 + g, alt = altitude above the pad plane, g = max(0, (Terrain.surface_point(ship direction) - pos[pad]) . up[pad]); g = 0 on level ground, so every existing collision, docking and landing test passes unchanged; the deck half-space (A-109), the capturer exception (A-146), the lower bound and the docked position are unchanged; terrain is sampled only for a ship inside a pad column above the plain band (at most one height_at per such ship per tick); new tests on a sloped fixture with pad_radius_m 10: a ship settling 8 m uphill of the pad centre on 5 degree and on 15 degree ground gets C_PAD, is graded and DOCKED at pos[pad] + up x r; the same ship 8 m downhill docks; a ship hovering r + 1 above a level deck gets no C_PAD; the landing autopilot (05 L4-L6) docks on the 15 degree pad; S4 byte-equal, no FORMAT change; sim/MODULE.md Collision line and sim/docking/MODULE.md cite A-158; perf note with a perf_tick A/B", "docs": ["docs/reviews/R0-amendments-27.md", "03 s6.1", "03 s6.4"]},
    {"id": "GD-53", "title": "sim: test pin for basin vision (ADR-05 horizon rule on cradle slot 0; R0 B.33 A-159)", "lane": "sim", "tier": "Sonnet", "size_days": 0.25, "depends_on": ["BUG-3"], "milestone": "M3", "acceptance": "Tests only, no godot/src change. On cradle slot 0 (floor about -335 m) with the start kit: (1) an enemy Siege Crawler standing on the floor is visible to the Core's team at 200 m and not visible at 600 m (horizon sqrt(2 x |p_core| x 7) = about 282 m); (2) an enemy Dart 600 m from the Core and 40 m above the floor is visible; (3) with a finished Sensor Mast the Crawler at 1,150 m from the Mast is visible (deck_reveal_radius 1,200); (4) the same three cases on the flat datum give the same answers; test/unit/core/test_sphere.gd gains two vectors for is_occluded_by_datum: two points at R - 335 and 300 m apart: true; the second point raised 10 m: false; sim/vision/MODULE.md cites A-159 in one line", "docs": ["docs/reviews/R0-amendments-27.md", "03 s3.7", "03 s2.8"]},
    {"id": "GD-54", "title": "tools: econ_model.py prices Harvester trips with d as the driven leg and starts the kit Harvester mining (R0 B.33 A-160, BUG-4)", "lane": "tools", "tier": "Sonnet", "size_days": 0.5, "depends_on": ["BUG-4"], "milestone": "M3", "acceptance": "tools/econ_model.py takes each trip's d as the driven leg (centre-to-centre distance - spot_frac x radius_m - the dock stop offset, read from the defs and the map recipe, none typed in the script) and starts the kit Harvester mining at the field's near edge (R0 B.6); on cradle it reproduces the sim: first start-kit delivery 68 s +- 5 s and a steady cycle within 5 % of test_bug4_harvest_cycle.gd; a 02 s8.7 checkpoint that moves by more than 5 s is updated in a 02 revision; the 02 s8.2 table is unchanged; tools tests green", "docs": ["docs/reviews/R0-amendments-27.md", "02 s8.2", "02 s8.7"]},
    {"id": "AI-50", "title": "sim_ai: OpeningBook default when = affordable, a funds wait is never a stall; SC-41 exempts only an Expansion pair that waits on the clock (R0 B.33 A-162, A-163)", "lane": "sim_ai", "tier": "Sonnet", "size_days": 0.5, "depends_on": ["AI-23"], "milestone": "M3", "acceptance": "BookCondition.compile of an absent or empty when is the affordable condition (05 s7.3); a build or produce step with an explicit when is due only while it is also affordable; order, raid and set_replenish steps are unaffected; tests: a step that waits for funds longer than stall_s is not SKIPPED_STALL and runs when the funds arrive, and it blocks the steps behind it; a due, affordable step blocked by a missing prerequisite is still SKIPPED_STALL after stall_s; SC-41 _assert_no_stall: a PENDING outcome at the hand-over passes only when the cursor step is the order move or the build outpost of an Expansion pair and waits on the clock (its when is false at the hand-over and either becomes true by advancing t alone or stays false at this t with every other term true), through an appended pure BookCondition helper; the begins_with t>= test is gone; unit cases: t>=330 passes, t>=420|ore>=900 with Ore short passes, t>=270&ore>=900 with Ore short fails, an absent when with funds short fails; SC-40, SC-43, SC-47 still pass; no BookRun layout or AiDriver FORMAT change; commander/MODULE.md OB1 and OB3 reworded and citing A-162; perf note (test_commander_perf.gd)", "docs": ["docs/reviews/R0-amendments-27.md", "05 s7.3", "godot/src/sim_ai/commander/MODULE.md"]}
  ],
  "acceptance_replace": {
    "AI-49": "R0 B.33 A-161: tools/schemas/autopilots.schema.json gains $defs.siege (object, additionalProperties false, all 12 keys required) and a siege property on the autopilot, required on the ap_crawler branch beside follow: spot_min_m, spot_max_m (number, > 0, <= 5000); spot_slope_deg (number, > 0, <= 45); relocate_bomb_m, relocate_step_m (number, > 0, <= 1000); aim_tol_deg (number, > 0, <= 10); spot_samples (integer 1..64); loft_tol_m, solve_tol_m (number, > 0, <= 100); loft_iters (integer 1..16); solve_step_ticks (integer 1..4); relocate_tries (integer 1..16); autopilots.json ap_crawler and the canonical fixture carry the block with the values 1000, 1150, 10, 60, 150, 1, 24, 15, 2, 6, 2, 6 and a _doc citing 05 s6.7 (the first four), AI-18 and AI-18b; validate_content cross-field rules: spot_min_m < spot_max_m, solve_tol_m <= loft_tol_m, [spot_min_m, spot_max_m] inside the Crawler weapon's [range_min_m, range_m]; negative cases in test_validate_content.py: ap_crawler without siege, a siege block missing one key, and one per cross-field rule; CrawlerParams.from_content reads all 12 keys from the def with no default and returns null when the block or a key is missing or <= 0; SiegeAim.loft loops prm.loft_iters and steps solve_step_ticks x dt, max_steps = ceil(lifetime_s / (solve_step_ticks x dt)), CrawlerBrain._relocate tries prm.relocate_tries; CrawlerParams gains var loft_iters, solve_step_ticks, relocate_tries (appends), SIEGE_KEYS gains the three names at the end, SIEGE_DEFAULTS and LOFT_ITERS stay with their values, deprecated in MODULE.md Open items and read by nothing (10 s4.1); the barrel limits are read from the typed GroundUnitDef fields (CONTENT-5), not raw; brains/MODULE.md CR5 rewritten; behaviour unchanged: the AI-18 / AI-18b suites pass with the same impact numbers; PR flagged 'Contract impact: change (R0 B.33 A-161)'"
  },
  "sets": {
    "AI-49": {"lane": "content+sim_ai", "tier": "Sonnet", "size_days": 0.5, "depends_on": ["AI-18", "AI-18b", "CONTENT-5"], "docs": ["docs/reviews/R0-amendments-27.md", "05 s6.7", "godot/src/sim_ai/brains/MODULE.md"]}
  },
  "acceptance_append": {
    "AI-24": "; R0 B.33 A-162 / A-163: no gate is derived from stall_s and commander BK1 is not added; under AI-50's SC-41 every book either completes or is pending at 5:00 only on an Expansion pair that waits on the clock; a step gated at or after 5:00 appears only as that pair at the end of a book; bulwark_standard reaches its Extractor through the home-trap Outpost pair (05 s7.3 as patched); gates are fitted to the sim's income after BUG-4 (first delivery 68 s on cradle)",
    "AI-25": "; R0 B.33 A-163: at the hand-over the Expansion rule (05 s7.5 'at the book's time') reads the gate of the book's deferred Expansion pair, if it has one, through OpeningBook.when_of; no other unexecuted book step is carried over",
    "GD-22": "; R0 B.33 A-157 / A-158: the Noon Pole relay_station entry sits on ground whose slope over its pad_radius_m is <= build_max_slope_deg (the bound A-158's band assumes); the PR states the measured slope"
  },
  "depends_on_append": {
    "AI-24": ["AI-50"]
  },
  "note": {
    "PM-06": "Ruling R0-amendments-27 (B.33 A-157..A-163): radial up; terrain-following landing band; basin vision intended; d = driven leg; siege block required (12 keys); default when = affordable; SC-41 exemption and the 05 s7.3 book patch.",
    "AI-49": "Re-scoped by R0 B.33 A-161: it edits sim_ai code as well as the schema and def, so Sonnet 0.5 d with an Opus review (brains)."
  }
}
```

New work: 2.0 d plus 0.25 d on AI-49. All M3. BUG-6 and AI-50 should land before the M3 playtests; AI-24 waits for AI-50.

## Not ruled here

- **`IceExtract.refinery_for` measures `pipe_radius_m` in 3-D while the build radius is great-circle** (PR #190 nit). On a 15 degree slope the two differ by under 4 %; the sim lane may align it without a ruling.
- **Harvesters of one Refinery share one mining spot** (BUG-4 note): visual stacking only; a presentation or sim_ai follow-up if wanted.
- **`bot_profiles.json` `opening_book` constants** (`stall_s`, `book_end_s`; AI-23 note): still in the `ai23_params.json` fixture. They come back as a contract question with AI-28's profile schema.
- **A relay-site slope rule in `moonbake validate`.** GD-22 states the slope for `cradle`; a validator rule is the tools lane's when the second map with a Relay Station is baked.

## Decisions for the owner

1. **A-157 radial `up` for every structure.** Alternative: terrain normal for every structure. Recommendation: radial (02 s8.4 solar rule, level pads, the 07 skirt). Default if silent: radial; GD-52 runs.
2. **A-158 landing band follows the terrain above the deck.** Alternatives: a pad-only slope limit of about 3 degrees; a raised deck. Recommendation: as ruled (no new constant, level pads unchanged). Default: as ruled; BUG-6 runs.
3. **A-159 basin vision is intended.** Alternative: `sensor_height_m` on structures in v1. Recommendation: intended; revisit with terrain line of sight in v1.x. Default: intended; GD-53 pins it.
4. **A-160 `d` is the driven leg; the 450 m row stays.** Alternative: relabel the row 470 m and recompute the table. Recommendation: keep (inside +-5 %). Default: keep.
5. **A-161 `siege` required on `ap_crawler`, 12 keys.** Alternative: optional with the defaults left in code (an append under A-145). Recommendation: required (ADR-09; A-93 / A-144 precedent; no value changes). Default: required; AI-49 runs as re-scoped.
6. **A-162 a funds wait is never a stall, also behind an explicit `when`.** Alternative: only an absent `when` means `affordable`. Recommendation: as ruled. Default: as ruled.
7. **A-163 only an Expansion pair may be deferred past 5:00; the vanguard raid and foundry Reactor steps leave the 05 listing.** Alternative: keep them and move `book_end_s` later, which needs a measured income to pick the number. Recommendation: as ruled. Default: as ruled.
8. **The backlog patch:** GD-52, BUG-6, GD-53, GD-54, AI-50 new (2.0 d); AI-49 becomes content+sim_ai, Sonnet, 0.5 d; AI-24 depends on AI-50. Recommendation: as written. Default: as written.
