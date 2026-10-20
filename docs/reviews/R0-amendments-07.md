# R0 amendments 07: the AI-11 contract questions (PR #69): separation look-ahead (05 s5.4), the ESCORT fields on the ORDER wire (04 s2.5), the `separation` / `formation` blocks of `autopilots.json` (A-84..A-86)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, new subsection B.14 (append-only). No ADR is amended, so no `docs/adr/ADR-NN-amendment-*.md` and no line in 01's amendment log (10 s4.2): A-84 is a 05 s5.4 formula amendment backed by a measurement, A-85 is a 04 s2.5 erratum (05 s3.1 and 08 SL-2 already promise what 04 forgot to pack), A-86 is a def field-set decision under ADR-09 as written. |
| **Status** | Decided by the Architect 2026-10-20; the three OWNER items below carry their defaults until the owner rules. |
| **Date** | 2026-10-20 |
| **Raised by** | AI-11 (PR #69, head 9e4d270): "Deviation from 05 s5.4 (please review)" and the three "Contract questions"; `sim_ai/MODULE.md` "Open (needs sim)" / "Open (needs content, AI-19)" bullets. |
| **Decided by** | Architect (Fable), 10 s4.1 "Change" row (a required def field set: 10:259; `tools/schemas/*.schema.json` required fields and `godot/content/defs/*.json` field *sets* are the Architect's: 10:250, 10:276); the owner approves the OWNER items. |
| **Size** (10 s4.1) | One formula amendment with a measurement (A-84); one payload-layout append conditioned on an existing enum value, no ordinal, signature or size-formula change for any other kind (A-85); two def blocks with required keys (A-86). No enum change, no reorder, no delete, no `deps.json` edge, no new autoload, addon or thread. |

Reading order for the AI-11 author: the B.14 table in `docs/reviews/R0-resolution-register.md` is the binding text; this file is the why. The Architect edits no `godot/src/**/*.gd` and no test; the code consequences are listed per task at the end.

## A-84 (deviation) 05 s5.4 gains the AI-11 look-ahead; the acceptance is not narrowed

**Evidence.** 05 s5.4 (05:479) gives one term: inside a 60 m ring, `gain * (p - p_j).normalized() * (60 - dist) / 60 * 20 m/s`. 05 s11.2 SC-39 (05:1026) and 09 AI-11 (09:167) demand "no collisions" and "zero friendly collisions in a 50-seed swarm test". PR #69 measured on `SwarmWorld` (12 mixed ships, fair starts, `test_swarm_separation.gd`): the ring alone collides in 30 of 50 seeds; the ring plus the look-ahead in 0 of 50 (smallest surface gap 3.8 m), 1 of 300 in the wide sweep, 23 of 300 under the stress variant (every ship to the same points). The reason is kinematic, not a tuning miss: two Darts head-on at cruise close at 2 x `v_cruise`, so a 60 m ring is crossed in about 0.3 s, while the AI-05 `FlightController` needs about 1 s before a 30 degree heading command shows as lateral motion (step responses measured on Dart / Lancer / Bomber in the PR); and for an overtaker the ring pushes along the line of closing, which cannot separate ships flying the same track. The 60 m ring is still correct for what it was written for (two ships drifting together while slot-keeping, 05 s5.6); it was never a collision-avoidance law for closing pairs. 01 s3.1.3 makes ramming lethal for both ships, and 05 s5.4 already says separation "outranks formation keeping", so the acceptance is the right one and the formula is what gives.

**Decision.** 05 s5.4 is amended (patched in this PR) to the two-term law as built, with every number a key of the autopilot def's `separation` block:

1. **Neighbour query.** `SimView.ids_near(p, separation.query_radius_m, Spatial.MASK_SHIP)` once per think; friendly ships only (enemies are never avoided here; tall structures are the terrain probe's, 05 s5.3, the second sentence of s5.4 stands). `query_radius_m` must not exceed the hash's ring-2 coverage (R0 B.11 A-52: ~188-208 m) or `ids_near` leaves the cheap path.
2. **Proximity ring (unchanged).** For `dist < radius_m`: `near += (p - p_j).normalized() * (radius_m - dist) / radius_m`; coincident ships split along a tangent chosen by id order.
3. **Look-ahead (new).** For a pair that is closing (`v_rel = v - v_j`, `t* = -d . v_rel / |v_rel|^2 > 0`, `t = min(t*, lookahead_s)`), predicted miss `m = |d + v_rel t|`. If `m < lookahead_miss_m`: `deficit = lookahead_miss_m - m`, `urgency = deficit / lookahead_miss_m`, `rate = min(deficit / (lookahead_eff * max(t - lookahead_lag_s, lookahead_min_s)), lookahead_max_mps)`; the push is `rate` along the **horizontal** side direction (the horizontal part of the miss vector when it carries more than half of it, else `up x v_rel`, which is opposite for the two ships of a pair, so they split; an exactly aligned pair splits by id order). A ship **catching up on a neighbour ahead** (`d . v < 0` and `v_rel . v > 0`) also sheds `lookahead_brake * urgency * min(closing speed, lookahead_max_mps)` along its own velocity. **Only the most urgent neighbour's look-ahead counts** (the largest push; sums cancel in a clump).
4. **Output.** `v_cmd += gain * (near * push_mps + look)`.

**Anchors (OWNER, default applied).** The values are those of the fixture the 50-seed run passed with (`godot/test/sim/ai/ai11_params.json`): `radius_m` 60, `gain` 1.0, `push_mps` 20, `lookahead_s` 4, `lookahead_miss_m` **80**, `lookahead_lag_s` 1.0, `lookahead_eff` 0.7, `lookahead_min_s` 0.3, `lookahead_max_mps` 60, `lookahead_brake` 1.0, `query_radius_m` 200. The PR body and `sim_ai/MODULE.md` say "under 60 m" for the miss threshold while the fixture says 80: the fixture is what was measured, so 80 is the anchor and the PR text follows it; if the author prefers 60, the 50 / 300-seed numbers are re-run at 60 and reported, and the anchor is whichever passed. `lookahead_eff` (0.7 m of lateral offset per m/s of push per second after the lag) and `lookahead_lag_s` are flight-model measurements, so AI-06's harness re-measures them whenever the `FlightGains` set changes (A-68 / AI-38); the rest are tuning anchors for GD-34.

**Perf.** `EscortPilot.think` ~39 us with 17 ships inside 300 m (dev machine) against the 05 s10 think row of 25 us (which prices 6 probes, 1 query, 1 choice point; here 0 probes). No row moves (R0 B.11 A-62: dev-box numbers are advisory; TA-22 / TA-42 measure on the pinned runner). The levers, in order, when the runner shows the think row over: (1) `query_radius_m` down toward 150 (data; cost is ~2.5 us per neighbour in range), (2) brains that also probe and choose targets run `Separation.push` every second think (code, AI-13 / AI-14 perf notes), (3) the AI governor's existing rungs (05 s10). The 03 s4.2 reserved row "SL-2 wing orders in step 3 inside 05's governor" (03:575) is unchanged.

**Alternatives.** Narrow the scenario (fewer ships, wider starts, same-speed classes): rejected; 05 s6.7 raids and the Commander's squads (05 s7.6) put 4-8 mixed ships on one track every match, which is exactly the overtaking case the ring cannot handle. Lower `lookahead_lag_s` by re-tuning `FlightGains`: AI-06 found no set under 1 s without the damping_only instabilities of AI-38. Both lose to a law whose every number is data.

## A-85 (question 1) the ORDER payload gains a 6-byte ESCORT trailer; sim (TA-60) and NET-04 carry it

**Evidence.** 05 s3.1 (05:287): "ESCORT's `escort_slot`, `focus` and `escort_mode` fit inside that layout; 04 s2.5 owns the exact packing." 08 SL-2 (08:259): "the ORDER wire layout is 04's (C2-06 ...) with these fields carried per 05 s3.1." R0 C2-06 (R0:76): "`OrderSpec` gains `escort_slot`, `focus`, `escort_mode` when SL-2 is built". 04 s2.5 (04:227-238) packs none of them, so an ESCORT ordered by `Command` always arrives as `FORM`, slot -1, focus 0: the SL-2 wing (08 rules 1-3, FEAT-08 / FEAT-09 / FEAT-11, M5) has no wire path. The sim's reader (`CommandPayload.read_order`, exact-size check `9 + 4n + 24np`) and builder (`Command.order`) mirror 04's omission. `OrderRules.validate` O9 already range-checks the three fields "only with ESCORT and in range" (`sim/orders/MODULE.md` O9; `order_rules.json` `escort_slot_max` 7), so validation exists and only the bytes are missing. Nothing in `net` is built yet (NET-04 `todo`), so no shipped codec changes.

**Decision.** This is a 04 s2.5 erratum under C2-06, not a new contract: the two docs that own the semantics promised the fields; the packing doc dropped them. **Decided now, not deferred**, because NET-04 is the next `net` task and would otherwise be built twice. The ORDER layout gains an **ESCORT trailer**, appended after `points[]` and present **iff `order_kind == 3` (ESCORT)**:

```
u8   escort_mode     EscortMode (R0 B.3): 0 FORM, 1 FOCUS, 2 BREAK
u8   escort_slot     0xFF = -1 (class default slots, 05 s5.6); else 0..order_rules.escort_slot_max (wing.json slot)
u32  focus           EntityId or 0 (FOCUS target)
```

Wire size = `8 + 4 * count + 8 * point_count + (6 if ESCORT else 0)` <= 256 B. ESCORT carries `point_count` 0 (O9: points only with PATROL), so its largest payload is `8 + 128 + 6 = 142` B and the A-60 rule (15 points at 32 ids) is untouched. A non-ESCORT payload with trailing bytes, or an ESCORT payload without the 6 bytes, is `REJECTED_MALFORMED` (V-ORD, 04 s11.3). The sim form (`sim/world/command_payload.gd`, f64 points) carries the same 6 bytes at the same place: size `9 + 4n + 24np + (6 if ESCORT)`. No other kind's bytes move; `OrderSpec.fits_wire` / `wire_size` gain an appended optional parameter for the kind (default = no trailer), never a changed one.

**Who carries it.** `sim`: **TA-60** (new, Sonnet, 0.5 d): `Command.order` writes the trailer for ESCORT, `CommandPayload.read_order` reads it, `wire_size` / `fits_wire` count it, `test_command_payload` / `test_command_validator` round-trip an ESCORT with slot 1, FOCUS and a focus id to `SimView.order_head`, and refuse a MOVE with 6 trailing bytes. `net`: **NET-04** acceptance append (encode / decode of the trailer; a 32-id ESCORT is 142 B; a MOVE with trailing bytes returns null). `server`: NET-16 reuses `OrderRules.validate` (no change). `sim_ai`: AI-11 merges with its `OrderQueue.push` injection (the SL-2 fields exist on the queue, AI-01, so the behaviour under test is real); **FEAT-09** acceptance append: its SC-39 wing variant issues the ESCORT through `Command.order` and the injection helper is deleted. `ui`: FEAT-08 builds `Command.order` with the fields set (no change to its acceptance).

**Alternatives.** Carry the trailer on every kind (fixed +6 B): simpler codec, but it moves the bytes of eight kinds whose layout 04 published and costs 6 B on every MOVE; rejected. Defer to FEAT-08 (M5): leaves NET-04 (M3) to be reopened; rejected. Encode `escort_slot` as `i8`: equivalent; `u8` with the 0xFF sentinel matches the `AiState.NO_SLOT = 255` convention the PR already uses.

## A-86 (questions 2, 3) `autopilots.json` `separation` and `formation` blocks: keys, required-ness, one home per number

**Evidence.** 05 s4.4 (05:393) shows `"separation": { "radius_m": 60, "gain": 1.0 }` and the schema (`tools/schemas/autopilots.schema.json`) allows exactly those two keys, `additionalProperties: false`, the block optional. 05 s5.6 (05:536) states the formation numbers in prose (slots, `k_form` 0.5, cap cruise + 10 %, break utility 0.5, half the escorts, rejoin 1,500 m) with no def home; 05 s3.3 (05:308) puts the escort engage radius (1,000 m) in `order_rules.json` (`escort_engage_radius_m`, present) and the SL-2 numbers in `wing.json` (present, FEAT-01). The PR's `FormationParams.SEP_KEYS` / `FORM_KEYS` and the fixture `ai11_params.json` are the proposed sets. ADR-09 (01:528) and the A-51 / A-65 reading: one home per sim-affecting number.

**Decision.**

| Block | Keys (names binding) | Required where | Anchors |
|---|---|---|---|
| `separation` | `radius_m`, `gain`, `push_mps`, `lookahead_s`, `lookahead_miss_m`, `lookahead_lag_s`, `lookahead_eff`, `lookahead_min_s`, `lookahead_max_mps`, `lookahead_brake`, `query_radius_m` (= `FormationParams.SEP_KEYS`, 11) | **Required on every ship autopilot** (`ap_dart`, `ap_lancer`, `ap_bomber`, `ap_scout`, `ap_hauler`, `ap_harvester`): 05 s5.4 applies to every ship brain. Absent on towers and `ap_crawler`. All 11 keys required when the object is present (A-67 pattern). | A-84 values for every ship class in v1.0 (one set; class differences come from `ShipDef` speeds). Ranges: `radius_m` (0, 1000], `gain` (0, 10], `push_mps` (0, 100], `lookahead_s` (0, 10], `lookahead_miss_m` (0, 500], `lookahead_lag_s` [0, 3], `lookahead_eff` (0, 2], `lookahead_min_s` (0, 2], `lookahead_max_mps` (0, 200], `lookahead_brake` [0, 2], `query_radius_m` (0, 208]. |
| `formation` | `class_slots_m` (array of 4 `[right, forward, up]` metre triples, 05 s5.6 slots 0-3), `k_form`, `speed_cap_mult`, `rejoin_radius_m`, `break_utility`, `max_break_frac`, `slot_scan_m`, `min_heading_speed_mps` (8 keys) | **Required on `ap_dart` and `ap_lancer`** (the ESCORT classes, 05 s3.2); optional elsewhere; all 8 required when present. | `class_slots_m` `[[-40, -30, 20], [40, -30, 20], [0, -60, 40], [-80, -60, 20]]`, `k_form` 0.5, `speed_cap_mult` 1.1, `rejoin_radius_m` 1500, `break_utility` 0.5, `max_break_frac` 0.5, `slot_scan_m` 1500, `min_heading_speed_mps` 5 (05 s5.6; the last two are AI-11's). Ranges: `k_form` (0, 5], `speed_cap_mult` [1, 2], `rejoin_radius_m` (0, 5000], `break_utility` [0, 1], `max_break_frac` (0, 1], `slot_scan_m` (0, 5000], `min_heading_speed_mps` [0, 50]; `class_slots_m` 1-8 rows (below `AiState.NO_SLOT`). |

**`engage_radius_m` is not a `formation` key.** 05 s3.3 already homes the FORM engage radius in `order_rules.json` `escort_engage_radius_m` (1,000 m) and V-ORD / the server read it there; a second copy in `autopilots.json` is the two-sources error A-51 / A-65 closed. `FormationParams` takes it from `OrderRulesDef` (`ContentSet.order_rules`; how it is passed is the lane's) and `FORM_KEYS` drops it; the fixture follows. The SL-2 numbers (`slots_brf_m`, `slot_tolerance_m`, `focus_timeout_s`, `focus_leash_m`, `break_radius_m`, `break_s`) stay in `wing.json` only, as the PR has them.

**AI-19** writes both blocks into every `ap_*` named above, extends `autopilots.schema.json` (keys, ranges, the per-class `required`), and deletes the "Needs content (AI-19)" bullets; `test/sim/ai/ai11_params.json` stays the fixture until then (the AI-05 / AI-08 pattern). **OWNER:** the two required block sets; default applied. The content hash changes.

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

```json
{
  "new": [
    {"id": "TA-60", "title": "sim: ESCORT trailer on the ORDER payload (u8 escort_mode, u8 escort_slot 0xFF = -1, u32 focus; present iff kind ESCORT) in Command.order, CommandPayload.read_order, OrderSpec.wire_size / fits_wire (R0 B.14 A-85)", "lane": "sim", "tier": "Sonnet", "size_days": 0.5, "depends_on": ["AI-01", "TA-18"], "milestone": "M3", "acceptance": "An ESCORT Command with escort_slot 1, EscortMode.FOCUS and a focus id round-trips through SimWorld.apply_command to SimView.order_head with the three fields intact; an ESCORT payload without the 6 bytes and a MOVE payload with 6 trailing bytes are REJECTED_MALFORMED; a 32-id ESCORT is 142 B on the wire formula; every other kind's bytes unchanged (existing tests untouched); sim/orders/MODULE.md and sim/MODULE.md Command line updated", "docs": ["R0-amendments-07 A-85", "04 s2.5", "05 s3.1"], "status": "todo"}
  ],
  "acceptance_append": {
    "NET-04": "; the ORDER codec writes / reads the 6-byte ESCORT trailer (present iff order_kind 3): an ESCORT with slot 1, FOCUS and a focus id round-trips, a 32-id ESCORT is 142 B, a MOVE with 6 trailing bytes returns null (R0 B.14 A-85)",
    "AI-19": "; every ship ap_* carries the 11-key separation block and ap_dart / ap_lancer the 8-key formation block of R0 B.14 A-86 with the AI-11 anchors (godot/test/sim/ai/ai11_params.json, lookahead_miss_m 80), schema ranges and per-class required as A-86 states; engage_radius_m stays in order_rules.json only",
    "FEAT-09": "; the SC-39 wing variant issues its ESCORT (escort_slot >= 0, FOCUS / BREAK) through Command.order (TA-60), and the OrderQueue.push injection helper of AI-11 is deleted (R0 B.14 A-85)"
  },
  "depends_on_append": {"FEAT-09": ["TA-60"]},
  "note": {
    "AI-11": "05 s5.4 look-ahead ratified as A-84 (lookahead_miss_m anchor 80 per the fixture; MODULE.md text aligned); formation.engage_radius_m dropped in favour of order_rules.escort_engage_radius_m (A-86); SL-2 wire path is TA-60 / NET-04 (A-85); think ~39 us vs 25 us row recorded, no row moves (A-62)"
  }
}
```

## Consequences for PR #69 (review findings, not new contract)

1. `sim_ai/MODULE.md`: the "proposed amendment to 05 s5.4" wording becomes "05 s5.4 as amended by R0 B.14 A-84"; the miss threshold reads 80 m (or the re-measured value); the two "Open" bullets cite A-85 / A-86 and name TA-60 / AI-19; the duplicated AI-11 Status sentence and the duplicated `NO_SLOT` lines in the AiState block are collapsed to one each.
2. `FormationParams.FORM_KEYS` loses `engage_radius_m`; the value comes from `OrderRulesDef`; `ai11_params.json` follows.
3. Everything else in the PR (`Separation`, `Formation`, `EscortPilot`, AiState FORMAT 4, the SC-39 / swarm tests) is inside the `sim_ai` contract and needs no Architect ruling; the Opus review's text stands.

## Not ruled here

Whether `Separation.push` should also see enemy ships (it should not: 05 s5.4 last sentence stands), the `w.get("_orders")` test access (review hygiene, lane's), and the 05 s10 think-row price of a brain that probes, chooses and separates (AI-13's perf note is the input; PM-01 reads it).
