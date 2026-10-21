# R0 amendments 13: `ENTITY_META` precedes `KEYFRAME`; the post-FULL C-BLIP is removed (NET-54), not budgeted; a known blip is never dead-reckoned, on the wire as well as on screen (NET-07 PR #97 Opus review, NET-56 PR #104 open question)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, subsection B.19 (append-only): A-101, A-102, A-103 added 2026-10-21. A-39 (B.10) gains a trailing pointer by append. No ADR is amended: ADR-07 (01, authoritative server, delta snapshots) is applied, not changed; no `docs/adr/ADR-NN-amendment-*.md`, no line in 01's amendment log (10 s4.2). `PROTOCOL_VERSION` stays 1 (A-36 precedent). |
| **Status** | Decided by the Architect 2026-10-21; the OWNER item below carries its default until the owner rules. |
| **Date** | 2026-10-21 |
| **Raised by** | NET-07 (PR #97) Opus review, comment 6308679994, "Contract questions for the Architect": (1) 04:124 and 04:723 send `KEYFRAME + ENTITY_META batch` and 04:250 says "the roster is built by `KEYFRAME`", while the KEYFRAME record (04:169) carries no def / owner / team; (2) 04 s4.6 (04:523) does not budget the C-BLIP that followed every refresh FULL (+0.23 KB/s at 700 C). NET-56 (PR #104) note: should a known-blip DYING entry's DELTA base also drop gravity (wire semantics)? |
| **Decided by** | Architect (Fable), 10 s4.1: a doc contradiction is resolved by citing 01 / R0 (rule 4 of the Architect brief); a protocol-semantics change (A-103) is the Architect's to propose and the owner's to approve; its code is a backlog task, never applied here. |
| **Size** (10 s4.1) | Eleven sentences in 04 (s2.2 diagram, s2.3 row, s3.1, s3.4 policy (4), s4.3, s4.6, s5.6, s5.7 diagram, revision log), three register rows, one pointer, one new task (NET-57), acceptance appends for NET-15 / NET-20 / NET-17. No signature, enum, event, byte layout, `deps.json`, autoload, addon or thread change; no budget number moves (A-62): the s4.6 totals are unchanged. |

Reading order: the B.19 rows in `docs/reviews/R0-resolution-register.md` are the binding text; this file is the why. The Architect edits no `godot/src/**`, no `godot/test/**`, no `MODULE.md`; `net/keyframe/MODULE.md` already states A-101's order and needs no change.

## A-101 `ENTITY_META` for every keyframe entry is sent before the `KEYFRAME`

**Evidence.**

1. 04 s2.3 (04:169): `KEYFRAME` = `keyframe_seq, tick, scope, roster_count, roster[] x FULL record (19 B)`. A FULL record (04 s3.5) is gap, 0xFF, vec3q, quat, vel, hp, flags (+ ai_tag): position and state, keyed by **roster index**, no slot / generation / def / owner / team. Only `ENTITY_META` (04:171: `slot, generation, def_id, owner, team, name_or_tag`) carries what a roster entry is (04 s3.1: "each binding a roster index to `(slot u16, generation u16, def_id, owner, team)`"). So "the roster is built by `KEYFRAME`" (04:250) cannot hold literally; a KEYFRAME can only reset the baseline of entries that exist.
2. Both messages travel on channel 3, reliable and ordered (04 s2.1). Sending META first is therefore the only order that never makes the client hold a ~23 KB KEYFRAME waiting for its roster (the reviewer's point 2). The decoder's `MISSING_ROSTER` result stays as the totality guard against a malformed server; `net/keyframe/MODULE.md` (K-rules, "ENTITY_META for every record's index is sent before the KEYFRAME on channel 3 (ordered); the doc's sequence diagram lists it after") already implements and tests this order, so the code is right and the doc is wrong (R0 "Authority": where a doc and the register disagree the doc is wrong until fixed; here the register was silent, so this row fills the gap).
3. Snapshot records on channel 2 can still overtake META on channel 3, so the hold-and-retry rule of 04 s3.1 (1 s timeout, `REQUEST_KEYFRAME(ROSTER_GAP)`) is untouched. NET-05's "held snapshot applied after meta" acceptance stands.

**Decision.** 04 s2.2 join diagram, s2.3 KEYFRAME row, s3.1, s4.3 trigger table and s5.7 reconnect diagram now read: `ENTITY_META` for every record's index first, then `KEYFRAME`, then `TEAM_DETAIL(FULL)` (ALL only), for every trigger; `ROSTER_REPAIR` sends the repaired entries' META first and no `TEAM_DETAIL(FULL)`. The roster is built by `ENTITY_META` and pruned by `ROSTER_REMOVE`. No byte changes. `ServerSession` (NET-15) and reconnect (NET-20) implement the order; acceptance appends below. **Not accepted:** a KEYFRAME record that carries identity (option (a) of the review: a wire change for a problem that ordering solves).

## A-102 The post-FULL C-BLIP is removed by NET-54, so 04 s4.6 cites it instead of growing a row

**Evidence.** NET-07 (PR #97) measured records 1.740 KB/s and stream delta 1.966 KB/s at 700 C on CI; the 0.23 KB/s difference was the C-BLIP the NET-06 tier-C rule sent after every refresh FULL because `BaselineFrame.set_full` resets the mirror's blip to unknown and the client cannot derive the blip (float altitude, server-only `under_fire`) from a FULL. The reviewer offered two fixes; the server-only one (option (b)) became NET-54. NET-54 (PR #100, merged 2026-10-21) compares `blip_of(s)` with `BaselineFrame.shown_blip` (the blip the client's dead-reckoned entry implies at the encode tick) and skips when equal: stream delta **1.562 KB/s** at 700 C, decoder and wire unchanged, mirrors identical, `test_keyframe_link.gd` guards 1.8 KB/s; NET-06 / NET-25 byte baselines were re-recorded in that PR with the change explained.

**Decision.** 04 s4.3 states the skip rule and both measurements; 04 s4.6 states under the table that the "C rolling refresh" row is FULL records only and that the +0.23 KB/s C-BLIP was removed by NET-54, so no row is added and the payload totals (25,116 / 25,649 / 26,440 B/s) stand. The NET-07 acceptance figure "refresh bytes <= 1.8 KB/s" means FULL-record bytes (04:494, 04:523), as the reviewer read it; the stream delta now also satisfies it. **Not accepted:** a "+0.23 KB/s" row describing a cost that no longer exists.

## A-103 A known blip is never dead-reckoned: the DELTA base is the stored bucket, no velocity, no gravity

**Evidence.**

1. State of the code after NET-54 / NET-56: `BaselineFrame.shown_blip` (skip decision) and `shown_levels` (presentation; `ReplayReader.position_of`, `NetSimView` by NET-17's acceptance) return the **stored** bucket levels for a known blip and `dr_levels` otherwise. The encoder / decoder DELTA base still calls `dr_levels` on the entry's pos / vel for every entry, and `set_blip` zeroes the mirror's velocity but keeps `FLAG_DYING`, so a known-blip DYING entry's base falls under gravity from a fabricated zero velocity (PR #100 "Notes for reviewers"; PR #104 note). Both mirrors agree, so nothing is wrong on the wire today; the question is which semantics to fix as the contract.
2. A C-BLIP is `gap, e8, n8, alt6_flags2` (04 s3.4): a 20 m bucket and a 40 m band, no velocity. There is no measurement behind `vel = 0`; integrating `g` from it is a model of nothing. 04 s3.4's gravity branch was written for baselines that hold a dequantised velocity ("`pos_b`, `vel_b` ... dequantised baseline values") and A-39 (2) advances that velocity by `g * dt`; a known blip has no `vel_b`.
3. Cost case (`rules.gravity` 6.0, `rules.json`): a DYING entity that rests in its bucket (NET-56's 300-tick test is this case) and is later promoted to A/B, or receives any DELTA, is encoded against a base that has fallen `0.5 x 6.0 x t^2` m: 0.75 m within one C interval (0.5 s), 12 m at 2 s, past POS_SMALL's +-31.75 m U range (A-38) at ~3.2 s (POS_LARGE, +3 B), 300 m at 10 s. The bucket base keeps the residual within one bucket (<= 10.5 m E/N) and one 40 m band (U). Where gravity would have helped (a truly falling entity between two C ticks) the two bases differ by 0.75 m, one third of POS_SMALL's U range, so no record is pushed to POS_LARGE by the change.
4. A/B entries are untouched (they hold a real velocity); unknown-blip entries (after a FULL) are untouched (the FULL carries velocity and flags, and NET-54's skip compares against their dead-reckoned position for exactly that reason). Only the three readers of a known blip are unified.

**Decision.** **Yes.** R0 B.19 A-103 and 04 s3.4 baseline policy (4): a mirror entry whose last record was a C-BLIP has the stored bucket levels as its DELTA base, no velocity advance and no gravity term, DYING or not, until a FULL or DELTA replaces them; A/B and unknown-blip entries dead-reckon as before. It is a protocol-semantics change applied to both ends at once: `PROTOCOL_VERSION` stays 1 (A-36 precedent, no shipped wire). Code is **NET-57** (net, Opus, 0.5 d, after NET-56): both codecs take the DELTA base from `BaselineFrame.shown_levels` (or an equivalent single helper) for a known blip, the mirror's per-tick velocity advance skips known-blip entries, determinism and mutation sweeps re-run, NET-06 / NET-25 byte baselines re-recorded only if a fixture contains a known-blip DELTA. Until NET-57 lands, 04 s3.4 carries the rule as `[planned: NET-57]` and both ends keep the NET-06 gravity branch; the author clears the marker in the NET-57 PR (shared-file authorisation under A-103, 10 s4.3, the NET-02 / A-23 precedent for a net task patching one 04 sentence). **Not accepted:** a velocity or flag in the C-BLIP (a wire change for a 0.75 m gain); dropping the gravity term while keeping the velocity advance (the same fiction with a different sign); leaving the divergence (three readers, two rules, and a resting DYING entity that costs POS_LARGE for no reason). **OWNER:** NET-57 in M3 (default) or deferred to the NET-17 wave.

## Doc patches in this PR (Architect-owned text)

- 04 s2.2 join diagram (04:124) and s5.7 reconnect diagram (04:723): `ENTITY_META batch ; KEYFRAME(ALL) ; TEAM_DETAIL(FULL)`.
- 04 s2.3 KEYFRAME row (04:169): Rate cell states the META-first order and that the record carries no identity.
- 04 s3.1 (04:250): roster built by `ENTITY_META`, META before KEYFRAME for every trigger, `ROSTER_REPAIR` likewise, KEYFRAME `MISSING_ROSTER` held like a record (A-101).
- 04 s3.4 baseline policies: policy (4) known blip `[planned: NET-57]` (A-103).
- 04 s4.3: trigger table rows (META before, `ROSTER_REPAIR` no `TEAM_DETAIL(FULL)`); the rolling-refresh paragraph states NET-54's skip rule and the 1.740 / 1.562 / 1.966 KB/s figures (A-101, A-102).
- 04 s4.6: one paragraph under the table citing NET-07 / NET-54; no row added (A-102).
- 04 s5.6: known blips are shown at their stored bucket with no gravity (`shown_levels`, NET-56) (A-103 presentation half, already code).
- 04 revision log: one row.
- R0 register: new B.19 heading and rows A-101..A-103; trailing pointer on A-39.

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

```json
{
  "new": [
    {"id": "NET-57", "title": "net: a known blip is never dead-reckoned on the wire: DELTA base = stored bucket levels, no velocity advance, no gravity even when DYING, on both ends (R0 B.19 A-103)", "lane": "net", "tier": "Opus", "size_days": 0.5, "depends_on": ["NET-56"], "milestone": "M3", "acceptance": "SnapshotCodec encoder and SnapshotDecoder take the DELTA base of a known-blip entry from BaselineFrame.shown_levels (or one shared helper both call), never dr_levels; the mirror's per-tick velocity advance (A-39 policy 2) skips known-blip entries; A/B and unknown-blip entries unchanged (test_c_blip_skip.gd and test_dying_blip_rests_300_ticks_at_blip_pos stay green); a DYING entity that gets a C-BLIP, rests 300 ticks and is then promoted to A encodes POS_SMALL or POS_LARGE from the bucket residual only and mirror == client (same_state) on every tick; a falling DYING entity whose bucket changes still gets a new C-BLIP; determinism (test_determinism_identical_bytes, byte cache) and the 20,000-mutation sweep green; NET-06 / NET-25 byte baselines re-recorded only if a fixture contains a known-blip DELTA, with the change explained in the PR; PROTOCOL_VERSION stays 1 (A-36 precedent); net/MODULE.md SNAPSHOT paragraph states the rule as one sentence; the 04 s3.4 policy (4) `[planned: NET-57]` marker is removed in the same PR (shared file authorised by A-103); check_deps, gen_module_api --check, check_perf_gates green; perf note: no allocation, one branch per entry", "docs": ["R0-amendments-13", "04 s3.4", "04 s5.6"], "status": "todo", "note": "From the NET-56 #104 open question, ruled yes in R0 B.19 A-103. OWNER default: M3; alternative: defer to the NET-17 wave."}
  ],
  "acceptance_append": {
    "NET-15": "; R0 B.19 A-101: on join and on every KeyframePolicy trigger the ServerSession sends ENTITY_META for every record's index on channel 3 before the KEYFRAME, then TEAM_DETAIL(FULL) for scope ALL only; a LocalTransport test asserts the channel-3 order META -> KEYFRAME -> TEAM_DETAIL(FULL) and that the client decodes the KEYFRAME without a MISSING_ROSTER hold",
    "NET-20": "; R0 B.19 A-101: the reconnect sequence sends ENTITY_META batch, then KEYFRAME(ALL), then TEAM_DETAIL(FULL), TEAM_STATE, MATCH_STATE (04 s5.7 as amended); reconnect_test asserts the order",
    "NET-17": "; R0 B.19 A-103 / 04 s5.6: NetSimView presents a known-blip entry at BaselineFrame.shown_levels (stored bucket, no gravity even when DYING) and never extrapolates it; a contract test shares the fixture of test_dying_blip_rests_300_ticks_at_blip_pos"
  },
  "acceptance_replace": {},
  "depends_on_append": {},
  "note": {
    "NET-55": "Done as R0-amendments-13 (A-101..A-103). 04 amended: META before KEYFRAME (s2.2, s2.3, s3.1, s4.3, s5.7); s4.6 cites NET-54 (no C-BLIP row); known-blip rule in s3.4 (4) [planned: NET-57] and s5.6. NET-56's open question ruled yes -> NET-57.",
    "NET-07": "Architect notes closed by R0 B.19 A-101 (META before KEYFRAME) and A-102 (C-BLIP removed by NET-54, cited in 04 s4.3 / s4.6).",
    "NET-56": "Open Architect question ruled yes (R0 B.19 A-103): the DELTA base of a known blip drops gravity and velocity on both ends; code is NET-57."
  }
}
```

## Consequences

1. NET-07, NET-54, NET-56: nothing to change; their code already matches A-101 / A-102 and the presentation half of A-103.
2. NET-15 / NET-20 (todo): the META-first order is now acceptance text, not a MODULE.md aside.
3. NET-17 (todo): `NetSimView` uses `shown_levels` (already in NET-56's note; now acceptance).
4. NET-57 (new): the wire half of A-103.

## Not ruled here

The NET-07 review nits (MOBILE_SWITCH exact stale count; `rec_kb_s` computed not counted; the `rolling_refresh.gd` header bound sentence) are review findings inside the net lane, not contract; whether a future codec carries velocity in a C-BLIP (rejected for v1 in A-103; revisit only with a measured need).

## Decisions for the owner

1. A-101: `ENTITY_META` before `KEYFRAME` for every trigger, roster built by META. Recommendation: approve (the code already does this; only the doc changes). Default if silent: applied.
2. A-102: 04 s4.6 cites NET-54 and adds no C-BLIP row. Recommendation: approve. Default: applied.
3. A-103: a known blip is never dead-reckoned on the wire (DELTA base = stored bucket, no velocity, no gravity), `PROTOCOL_VERSION` stays 1. Recommendation: approve. Default: applied as `[planned: NET-57]`.
4. NET-57 (net, Opus, 0.5 d, after NET-56) scheduled in M3 vs deferred to the NET-17 wave. Recommendation: M3, before NET-17 so `NetSimView` is built against the final base rule. Default: M3.
5. Acceptance appends for NET-15, NET-20, NET-17. Recommendation: approve. Default: applied.
