# R0 amendments 03: NET-06 CQ-4..CQ-7, snapshot encode budget, TA-48, TA-46, UX-10, NET-03, TA-13 follow-ups (A-36..A-47)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, new subsection B.10 (append-only). No ADR is amended, so no `docs/adr/ADR-NN-amendment-*.md` and no line in 01's amendment log (10 s4.2): the wire layout is 04's, the tick budget row is 03 s4.2 / R0 B.7 and does not move, ADR-09 is read as written. |
| **Status** | Decided by the Architect 2026-10-13; A-36's `PROTOCOL_VERSION` and A-40's plan are OWNER items with the defaults stated and applied. |
| **Date** | 2026-10-13 |
| **Raised by** | NET-06 (archive PR #53, public #1) "Open items" CQ-4..CQ-7 in `godot/src/net/MODULE.md` and its perf note; TA-48 (archive PR #52) and TA-46 (archive PR #48) backlog notes; UX-10 (archive PR #41) `camera/MODULE.md` Open items; NET-03 (public #3) `net/MODULE.md` Open items (silent-pilot buttons, NQ10, `PilotInput` comment); TA-13 (public #4) backlog note (`Terrain.load_map`, `sim/MODULE.md` at 300 lines). |
| **Decided by** | Architect (Fable), 10 s4.1 "Change" row (a wire-layout change and a baseline-semantics ratification); the owner rules on the OWNER items. |
| **Size** (10 s4.1) | One wire-layout change before any shipped wire (A-36: two reserved flag bits gain a meaning; no byte moves). Four ratifications of code already merged (A-37, A-39, A-41, A-42). Two doc corrections (A-38, A-43). One perf plan with two new tasks and no budget change (A-40). No reorders, no deletes, no new def field, no `deps.json` edge. |

Reading order for a lane engineer: the B.10 table in `docs/reviews/R0-resolution-register.md` is the binding text; this
file is the why. 03 s3.1, s4.1, s4.2; 04 s3.4, s3.5, s4.6, s19; `net/MODULE.md`, `core/MODULE.md`, `camera/MODULE.md`
were patched in the same PR so that no doc contradicts B.10. Code follows in NET-48 and NET-49 (backlog patch below);
the Architect edits no `godot/src/**/*.gd` and no test.

## A-36 (NET-06 CQ-4) SNAPSHOT packet index in flags bits 6-7

**Context.** 04 s3.4 marks a multi-packet tick with `CONTINUED` / `LAST` only. A client that receives packets 1 and 3
of a 3-packet tick sees `CONTINUED` then `LAST` and cannot tell that packet 2 is missing, so it must never
acknowledge a split tick, and the server can never use one as a delta baseline. NET-06 therefore ships
`max_packets = 1` with overflow records deferred to the next tick and `BaselineStore.last_split` forcing a one-packet
tick after every split. On the canonical scene (04 s4.5) a tick is ~900 B, so splitting is the exception, but a FULL
storm (keyframe-adjacent ticks, a cell boundary crossed by a convoy, the 255-record sections of `test_snapshot_budget`)
defers records for several ticks in a row, which is latency on exactly the entities that just changed most.

**Decision.** Flags **bits 6-7 = packet index** `k` (0-3) of this packet within its tick; `MAX_PACKETS_PER_TICK` stays
4. Index 0 is the packet that carries the pilot block when `HAS_PILOT` is set; `LAST` is set on the packet with the
highest index, `CONTINUED` on every other; a packet with `LAST` and index `k` declares the tick's packet count `k + 1`.
A client treats a tick as **complete** only when indices `0 .. k_last` have all arrived; only a complete tick may be
acknowledged (`ack_tick` in `INPUT` / `SNAPSHOT_ACK`) and only an acknowledged tick is a baseline, so N9's "a frame is
a delta baseline only when its tick went out as one packet" becomes "only when the client acknowledged it", for any
packet count. The server marks every emitted frame `usable`; `BaselineStore.last_split` and the one-packet-after-split
rule are deleted (a deletion of private state, not of a public symbol). Decoder rules: a packet whose index is not 0
while carrying `HAS_PILOT`, or whose index exceeds the `LAST` index already seen for that tick, is MALFORMED; a missing
middle index is loss, not malformation (N5). `max_packets` default becomes 4.

**`PROTOCOL_VERSION` (OWNER).** Stays **1**: R0 B.3 ("stays 1 until first code") as refined by A-23 ("no shipped
wire") already let `POS_EN_HALF` change at version 1, and 04 s2.2's bump exists to refuse a shipped client that would
misparse, of which there are none. NET-06 proposed 2. Recommendation: stay at 1 until the first wire a player can
connect with (NET-45 S-NET-1 is the first candidate), then bump once for every pre-launch change together.
Default if the owner says nothing: 1.

**Alternatives.** A `u8 packet_count` in the header: one more byte on every snapshot (~30 B/s per client, 04 s4.6
headers row) for information two spare bits already hold. A per-tick record count the client sums: costs the same bits
and fails when a lost packet's count is unknown. Keep `max_packets = 1` for v1: deferral latency on FULL storms and a
permanently dead pair of bits.

**Consequences.** No byte moves; the 04 s3.5 53-byte example is unchanged (index 0, `LAST`, flags `0x2B`). The
`test_snapshot_malformed.gd` rule "bits 6-7 set is malformed" inverts (contract test changes first in NET-48).
Client-side: NET-17 (`ClientSession`) acknowledges complete ticks only; until NET-17 exists the only ack path is the
test rigs. Bandwidth: unchanged (packets per tick in 04 s4.6 stays 1.3).

## A-37 (NET-06 CQ-5) Section C: FULL vs C-BLIP discriminator

**Context.** 04 s3.4 writes the FULL marker as `0x80 | 0x7F mask = all` (0xFF) and a C-BLIP as `gap, e8, n8,
alt6_flags2` with no type byte, so section C had no stated way to tell the two apart when `e8` happens to be 255.

**Decision.** Ratified: in every section the byte after the gap is **0xFF for FULL**; a C-BLIP's `e8` is clamped to
**254** (`DeadReckon.BLIP_E8_MAX`), so a blip never starts with 0xFF. A/B records are already unambiguous because a
DELTA mask has bit 7 clear. The clamp costs one blip step (1/256 of the 2,560 m cell span, 10 m) on the +e edge of a
cell, below the 40 m altitude step of the same record and far below the C tier's purpose (a 2 Hz radar blip).

**Alternatives.** A type bit in `alt6_flags2`: the byte has no spare bit (6 altitude + 2 state). A 5-byte blip:
+300 B/s on the canonical scene for nothing visible.

## A-38 (NET-06 CQ-6) 04 s3.4 POS_SMALL numbers after A-23

**Decision.** 04 s3.4, s3.5 and s4.6 are corrected to the A-23 quantum: POS_SMALL is 3 x i8 at 4 quanta =
**15.6 cm E/N** (4 x 3.906), 25 cm U (unchanged), range **+-19.8 m E/N** (127 x 15.6 cm), +-31.75 m U. The worked
example's comments read -0.31 m / +0.47 m for the enemy Dart and 15.6 cm for the Harvester (bytes unchanged). The
s4.6 Dart-turn note moves from "15.9 m past ~0.53 s" to "19.8 m past ~0.59 s" (`0.5 * 110 * 1.047 * t^2`); the
POS_LARGE shares used in the table were conservative estimates and are not lowered. Bytes, sizes and the bandwidth
proof are otherwise unchanged. `net/MODULE.md` already carried the new numbers.

## A-39 (NET-06 CQ-7) Encoder-side baseline policies

**Context.** 04 s3.4 fixes the arithmetic both ends share (`dr(t)`, dequantised baseline values, residual against the
client's mirror) but not three choices NET-06 had to make; all three leave the wire bytes unchanged and are visible only
as "what the mirror holds", so they are baseline semantics and belong in the contract (N9).

**Decision.** Ratified as written in `net/MODULE.md`:

1. **Dead band.** A residual whose every axis is under one POS_SMALL step (4 quanta; 15.6 cm E/N, 25 cm U) is not
   sent; both mirrors keep `dr(t)`. The error is bounded by one step and never accumulates, because the next residual
   is measured against the same mirror (04 s3.4 "quantisation never accumulates"); the 04 s3.2 argument (2 cm against an
   11 m interpolation blur) holds at 25 cm.
2. **Fine velocity.** Mirror entries hold velocity at **1/1024 m/s per axis** (`DeadReckon.FINE_PER_MPS`), set from the
   dequantised i8 value when a VEL group or FULL record arrives and advanced by `g * dt` per tick for gravity-bearing
   entries without re-quantising; the wire VEL group stays 3 x i8 at 2 m/s (04 s3.3). This is what makes a falling bomb
   cost zero POS records after its FULL (NET-06 acceptance), since re-quantising the velocity every tick would drift it.
3. **Gravity VEL resend.** For a gravity-bearing entry, the VEL group is written only when the true quantised velocity is
   at least one 2 m/s step from the dead-reckoned velocity on some axis (`DeadReckon.vel_close` false); a non-gravity
   entry sends VEL whenever its quantised velocity changed.

**Alternatives.** Send sub-step residuals as POS_SMALL anyway: +3 B per entity per tick for a correction below the
blur. Re-quantise the mirror velocity on every re-base: the bomb case regresses to "a few records per fall" (04 s3.6's
old text), which the measured codec no longer needs.

## A-40 (NET-06 perf note) Snapshot encode against the 03 s4.2 row 12 budget

**Context.** NET-06 measured, on the owner's desktop at p50 with 400 entities: `prepare_tick` 1.24-1.26 ms, `encode`
1.1-1.2 ms per client, `decode` 0.53 ms (`bench_snapshot.gd`, `net/MODULE.md` Performance budget). Multiplied by
8 clients that is ~10.8 ms against the 4.0 ms "events + interest + encode + replay" row (03 s4.2, R0 B.7), and the row
also has to hold interest, event routing and the replay writer.

The bench, however, encodes **all 400 entities for one client every tick** (A 40 / B 200 / C 160 at 30 Hz). The
04 s4.1 schedule gives a client per tick A 40 + B ~100 (15 Hz of 200) + C ~47 (2 Hz of 700) + 3 rolling-refresh FULLs
~= 190 records, and the measured cost is ~3 us per record, so the honest desktop extrapolation is 1.26 + 8 x ~0.57 =
**~5.8 ms**, over the row by ~1.8 ms before interest, events and replay are counted. The production vCPU is slower
than the desktop (03 s4.2 header), so the gap is real, not a bench artefact.

**Decision.** The budget row **does not move** (03 s4.4, R0 C1-11: absolute numbers change only on the pinned runner,
TA-42, and the row re-split is S-SIM-1's / PM-01's job with every row measured, 09 s6 S-SIM-1 branch). Two engineering
moves, both inside the row's design, land before NET-08 measures the row:

1. **Client-independent byte cache** (the "shared per-tier encode caching" option, limited to what is actually
   client-independent). FULL bodies (19-20 B) and C-BLIP bodies (3 B) depend only on the shared cache, so `prepare_tick`
   writes them once per entity into packed byte arrays and `encode` appends slices. A/B DELTA bodies depend on each
   client's baseline (04 s3.4 baseline rule) and stay per client. **Encode per tier instead of per client is rejected**:
   a delta against eight different baselines is eight different byte strings, and a shared baseline would mean a
   reliable snapshot path, which 04 s3.4 explicitly avoids.
2. **Canonical-schedule bench.** `bench_snapshot.gd` gains the 04 s4.1 schedule for 8 clients with distinct ack delays
   (3, 6, 10 ticks) and prints `prepare_us`, `encode_sum_us` and per-client p95; the number that goes to
   `perf/history.jsonl` is prepare + sum of encodes. NET-08's acceptance ("tiering + encode for 8 clients fits the
   4.0 ms p95 row on the pinned perf runner") is the gate and is unchanged.

**OWNER.** If the pinned-runner number is over 4.0 ms after both moves, the choice is (a) cut-ladder rung 5 (tier B
15 -> 10 Hz, 03 s4.3, already data), (b) re-split from rows that S-SIM-1 measures under budget (TA-12 already measured
projectiles at 2.0-2.3 of 2.5 ms), or (c) a tier-A cap of 32. Recommendation: (a) then (b), decided at PM-01 with the
S-SIM-1 REPORT, which is the existing process. Default if the owner says nothing: no budget change now; PM-01 decides.

**Consequences.** 03 s4.2 row 12 notes gain the measured numbers and the per-record shape of the cost. New tasks
NET-49 (cache + bench) and NET-48 (A-36) precede NET-08. No milestone moves (both are M2, 1.5 d total, net lane).

## A-41 (TA-48) Zero fuel disables the brake; idle burn and docked ships

**Decision.** Both confirmed. (1) The brake is retro-thrust: 02 s2.3 charges it 0.6 fuel/s and "a ship at 0 fuel has
zero thrust and glides under gravity", so an empty tank disables boost, thrust and brake alike (`kinematics.gd`
step 3 as merged). (2) `step_ship` is not called for DOCKED ships: B.5's landing rule sets `vel = 0` and snaps `pos` to
the socket, 03 s6.4 holds the parked pose and 04's O-2 note calls it the "docked hold"; 03 s4.1 now says so as rule 9
(step 5 skips `flags & DOCKED`; service in step 10 is the only thing that changes a docked ship's fuel). Idle burn is
therefore a flight cost only, which is what 02 s2.3 means by "attitude jets".

## A-42 (TA-46) `EntityId.is_projectile` upper bound

**Decision.** The predicate stays **open-ended** (`slot(id) >= PROJECTILE_SLOT_MIN`) as 03 s3.1 writes it. It
classifies a slot's range; validity is the store's (`ProjectileStore` rejects an index `>= SLOT_COUNT`, and `alive`
checks the generation). No allocator can mint a slot at or above `PROJECTILE_SLOT_END` (6,144), so the extra compare
would only cost on the collision and combat hot paths (03 s12.2) and give no safety: a decoder (04) must validate ids
against the store, never against the predicate (N10 style). `core/MODULE.md` records this; 03 s3.1 is unchanged.

## A-43 (UX-10) Camera constants as `const` until `camera.json`

**Decision.** Interim confirmed. ADR-09 binds **sim-affecting** constants; camera tuning is presentation and 06 s5.1
places it in `godot/content/ui/camera.json`, which UX-02 (S-UX-2) records as its acceptance already says. Rule for the
interim: the math classes keep the 06 spec defaults as `const` and take tuned values as arguments; the first controller
task that lands after UX-02 (UX-11 or UX-13, whichever merges first) reads `camera.json` and the `const` values become
the file's documented defaults. No new task; UX-02's `docs` gains this record. `content/ui/*.json` files have no schema
requirement today (`hud.json`, `ui_scale.json` precede it; 03 s9.4 covers `content/defs/`), so no schema task either.

## A-44 (NET-03) Silent-pilot buttons

**Context.** 04 s5.1 and 05 C13 said "reuse the previous input with stick axes decayed 50 % per tick, thrust held" and
nothing about the buttons byte. NET-03's `InputBuffer` keeps `BOOST | BRAKE` (`KEEP_BUTTONS`) and clears FLIP, DOCK,
RELEASE, FIRE1 and FIRE2 on every reused tick.

**Decision.** Ratified. BOOST and BRAKE are held states like thrust and decay with the tank, not with the link; FLIP,
DOCK, RELEASE and FIRE are momentary actions whose replay has consequences no silent pilot intended (a flip every
tick, ammo spent, the possession ended, the assist engaged). 04 s5.1 / s5.5 and 05 C13 carry the rule; `Prediction`
(NET-18) applies the same mask to its own local reuse so the predicted and authoritative ships agree during a stall.

**Alternatives.** Replay the whole byte: the RELEASE case alone rules it out. Clear every button: a boosting ship that
loses its link for 300 ms would lurch; thrust is held for the same reason.

## A-45 (NQ10) Silent-pilot window: 10 ticks

**Decision.** 10 ticks (R0 C2-08). 05 C13 in its stage-3 text already says ticks 1-10 then `LINK_BRIDGE`; the stage-2
"60 ticks" that NQ10 recorded was the transport-timeout scale (60 s web), not the reuse window. NET-03 ships
`InputBuffer.DECAY_TICKS = 10`; 05's `ControlMachine` (AI-02) mirrors one named constant and `handoff_test` (NET-19)
pins both. 04 s17 NQ10 is marked closed; no doc loses, so nothing else is patched.

## A-46 (TA-13, NET-03) Doc errata

**Decision.** (1) 03 s6.2 and s8.4 now name the loader `Terrain.load_map(map_dir)`, as TA-13 built it and
`sim/MODULE.md` already lists it (`load` shadows a GDScript global). (2) `PilotInput`'s wire form is
`PilotWire.to_wire` / `from_wire` in `net/` (04 s2.4; NET-03); the `sim/pilot_input.gd` doc comment that promised
`to_bytes` / `from_bytes` is wrong and is a sim-lane follow-up folded into the next sim task that touches
`pilot_input.gd` or `sim/MODULE.md` (TA-14 by order); the Architect edits no `.gd` file and a 0.1-day task for a
comment is not worth a wave slot. `sim/MODULE.md` Open items records it.

## A-47 `sim/MODULE.md` at the 300-line cap again (TA-13)

**Decision.** A-21 stands: the register, signatures and invariants are never compressed to make room. This PR
collapses the "Open items" prose (closed follow-ups into one bullet each), which is the same move A-21 made. The
named release valve for the next sim task that needs lines (TA-14 by order): the "How to add X" recipes are not a
contract under 10 s4 (Public API, Invariants, Events, Test entry points are), so they move to 03 s15.4 with a one-line
pointer left in the file. 05-lane subsystems keep opening `godot/src/sim/<subsystem>/MODULE.md` per A-21. Splitting the
sim lane's own classes into subdirectories would be a code move (not the Architect's) for a housekeeping problem.

## Register and impact

| Item | Entry |
|---|---|
| **Affected MODULE.md files** | `godot/src/net/MODULE.md` (Wire layout: SNAPSHOT flags bits 6-7 packet index, complete-tick ack rule, section C discriminator, baseline policies; N9 wording; Open items closed incl. NET-03's; Performance budget: the per-record shape and the A-40 plan; NET-11 link-semantics prose re-wrapped to fit the cap, text unchanged). `godot/src/core/MODULE.md` (Open items: A-42). `godot/src/camera/MODULE.md` (Open items: A-43). `godot/src/sim/MODULE.md` (Open items collapsed; A-41, A-42, A-46, A-47 recorded; 296 lines). No Public API block changes in this PR; NET-48 changes `BaselineStore` (drops `last_split`) and `SnapshotCodec.max_packets` default with its contract tests. |
| **Affected tasks (backlog patch for the owner)** | New: **NET-48** net, Opus, 0.5 d, M2, depends NET-06: SNAPSHOT flags bits 6-7 packet index; client completes a tick only with indices 0..last; every emitted frame usable; `last_split` deleted; `max_packets` default 4; malformed rules of A-36; `test_snapshot_malformed.gd` / `test_snapshot_budget.gd` / `test_snapshot_codec.gd` updated first; `PROTOCOL_VERSION` stays 1 (acceptance: a 3-packet tick with the middle packet dropped is never acked and the next complete tick becomes the baseline; the 53 B example unchanged; `codec_delta_test` 3,000 ticks with random splits identical baselines). **NET-49** net, Opus, 1 d, M2, depends NET-06: client-independent FULL / C-BLIP byte cache in `prepare_tick`; canonical-schedule 8-client `bench_snapshot.gd` (A 40 / B 15 Hz / C 2 Hz + 3 refresh, ack delays 3/6/10) writing prepare + encode sum to `perf/history.jsonl` (acceptance: BENCH_SNAPSHOT canonical mode printed and recorded; encode per client at the canonical schedule not above the pre-change number; delta/budget tests unchanged). Changed: **NET-08** depends_on += NET-49 (acceptance unchanged: the 4.0 ms row on the pinned runner); **NET-07** depends_on += NET-48 (rolling-refresh FULLs in section C use the A-37 discriminator; splitting semantics); **NET-17** depends_on += NET-48 and acceptance += "acks complete ticks only (A-36)"; **NET-06** status `review` -> `done`, `pr` 53 (archive) / 1 (public), note "CQ-4..CQ-7 closed by R0 B.10 A-36..A-40"; **TA-48** note -> "confirmed, R0 B.10 A-41"; **TA-46** note -> "decided, R0 B.10 A-42"; **UX-02** docs += "R0-amendments-03 A-43"; **TA-14** acceptance += "`pilot_input.gd` comment names `PilotWire` (A-46); if `sim/MODULE.md` needs lines, recipes move to 03 s15.4 (A-47)"; **NET-18** acceptance += "local reuse applies the A-44 button mask"; **NET-03** and **TA-13** notes -> "closed by R0 B.10 A-44..A-47". No re-tier, no milestone move. |
| **Affected docs** | R0 Part B.10 (new, append-only); 03 s3.1 (A-42 sentence), s4.1 (rule 9), s4.2 (row 12 notes), s6.2 and s8.4 (`load_map`), revision log; 04 s3.4 (flags, record table, dead reckoning, baseline rule), s3.5 (comments), s4.6 (one sentence), s5.1 and s5.5 (A-44 buttons, A-45), s17 (NQ10 closed), s19 (NET-48, NET-49 rows), revision log; 05 s2.3 C13 (A-44, A-45), revision log. 01, 02, 06 unchanged (06 s5.1 already names `camera.json`; 02 s2.3 already states the fuel rule). 09 s2.3 is regenerated from `backlog.json` and is not hand-edited (10 s3.7). |
| **Contract tests to update first** | None in this PR (no schema, enum or signature changes; `tools/tests` untouched). NET-48: `godot/test/unit/net/test_snapshot_malformed.gd` (bits 6-7 no longer malformed; index rules), `godot/test/unit/net/test_snapshot_codec.gd` (53 B example, index 0 + LAST), `godot/test/net/test_snapshot_budget.gd` (split tick acked and used as a baseline), `godot/test/net/test_snapshot_delta.gd` (random splits). NET-49: `godot/test/perf/bench_snapshot.gd`, `godot/test/net/test_snapshot_budget.gd` (bytes identical before and after the cache). |
| **Gate** | `python tools/validate_content.py`, `python -m unittest discover -s tools/tests`, `python tools/check_deps.py`, `python tools/extract_doc_examples.py --check`, `python tools/gen_module_api.py --check` green in this PR (prose-only MODULE.md edits). |

## Backlog patch (for the owner; `backlog.json` is not edited by this PR)

```json
[
  {"op": "add", "task": {"id": "NET-48", "title": "net: SNAPSHOT flags bits 6-7 packet index; complete-tick ack; every emitted frame usable; last_split removed; max_packets default 4 (R0 B.10 A-36)", "lane": "net", "tier": "Opus", "size_days": 0.5, "depends_on": ["NET-06"], "milestone": "M2", "acceptance": "A 3-packet tick with the middle packet dropped is never acked and the next complete tick becomes the baseline; 04 s3.5 53 B example unchanged; codec_delta_test 3,000 ticks with random splits keeps identical baselines; HAS_PILOT on index > 0 and index > LAST index are MALFORMED; PROTOCOL_VERSION stays 1", "docs": ["R0-amendments-03 A-36", "04 s3.4"], "status": "todo"}},
  {"op": "add", "task": {"id": "NET-49", "title": "net: client-independent FULL/C-BLIP byte cache in prepare_tick; canonical-schedule 8-client bench_snapshot with perf/history.jsonl row (R0 B.10 A-40)", "lane": "net", "tier": "Opus", "size_days": 1, "depends_on": ["NET-06"], "milestone": "M2", "acceptance": "BENCH_SNAPSHOT canonical mode (A 40 / B 15 Hz / C 2 Hz + 3 refresh, 8 clients, ack delays 3/6/10) prints prepare_us and encode_sum_us and appends to perf/history.jsonl; per-client encode at the canonical schedule not above the pre-change number; snapshot bytes identical before and after the cache", "docs": ["R0-amendments-03 A-40", "04 s3.4", "04 s4.1", "03 s4.2"], "status": "todo"}},
  {"op": "edit", "id": "NET-08", "depends_on_add": ["NET-49"]},
  {"op": "edit", "id": "NET-07", "depends_on_add": ["NET-48"]},
  {"op": "edit", "id": "NET-17", "depends_on_add": ["NET-48"], "acceptance_append": "; acks complete ticks only (R0 B.10 A-36)"},
  {"op": "edit", "id": "NET-06", "status": "done", "merged": "2026-10-13", "pr": 1, "pr_archive": 53, "note": "CQ-4..CQ-7 closed by R0 B.10 A-36..A-40 (NET-48, NET-49)"},
  {"op": "edit", "id": "TA-48", "note": "confirmed: zero fuel disables the brake; docked ships are not stepped (R0 B.10 A-41)"},
  {"op": "edit", "id": "TA-46", "note": "decided: is_projectile stays open-ended; the store validates (R0 B.10 A-42)"},
  {"op": "edit", "id": "UX-02", "docs_add": ["R0-amendments-03 A-43"]},
  {"op": "edit", "id": "TA-14", "acceptance_append": "; sim/pilot_input.gd comment names PilotWire.to_wire/from_wire (R0 B.10 A-46); if sim/MODULE.md needs lines, the How-to-add-X recipes move to 03 s15.4 with a pointer (A-47)"},
  {"op": "edit", "id": "NET-18", "acceptance_append": "; local input reuse during a stall applies the A-44 button mask (BOOST/BRAKE held, FLIP/DOCK/RELEASE/FIRE cleared)"},
  {"op": "edit", "id": "NET-03", "note": "silent-pilot buttons and NQ10 closed by R0 B.10 A-44, A-45; PilotInput comment -> TA-14 (A-46)"},
  {"op": "edit", "id": "TA-13", "note": "Terrain.load_map in 03 s6.2/s8.4 and sim/MODULE.md cap decided by R0 B.10 A-46, A-47"}
]
```

## Sign-off

| Role | Name | Date | Verdict |
|---|---|---|---|
| Architect | Fable 5.1 | 2026-10-13 | A-36..A-47 decided; A-36 `PROTOCOL_VERSION` (default 1) and A-40 over-budget branch (default: PM-01 decides with S-SIM-1) are OWNER items |
| Owner | | | |

## A-48 (post-merge erratum) `EntityId` generation is 11 bits; bit 31 stays clear

**Context.** 03 s3.1 packs `slot (bits 0-19) | generation (bits 20-31)` with generation wrapping 4095 -> 1. GDScript
`int` is 64-bit, but the stores keep ids in `PackedInt32Array` (`ProjectileStore.target` / `shooter`,
`EntityStore.link`, `OrderQueue`, `Command.order` ids, `SimView.ids_near` / `visible_ids`). From generation 2048 on
bit 31 is set, the stored value reads back sign-extended (negative) and no longer equals the id `EntityId.make`
returns. TA-18 reported it and masked two compares in `LocalSimView` with `& 0xFFFFFFFF`. With the 0-tick projectile
quarantine (A-20) a busy projectile slot reaches generation 2048 within minutes. Reproduced in TA-46: 100,000
alloc/free cycles on one projectile slot gave 49,152 failed store-and-read checks.

**Decision (proposed, TA-46).** Generation is **11 bits** (bits 20-30), `GEN_MASK` 0x7FF, `GEN_MAX` **2047**, wrap
2047 -> 1 (never 0); **bit 31 is always 0**. Every id is a non-negative int31, so a `PackedInt32Array` round trip is
exact and the 04 wire form (`u32` ids; `ENTITY_META` `generation u16`) equals the int with no normalisation. No
constant is renamed, no signature or wire byte changes; `core/MODULE.md` gains invariant C10 and `LocalSimView` drops
its masking helper.

**Cost.** A slot's id recurs after 2,047 frees instead of 4,095. Entity ranges quarantine 64 ticks, so an entity id
recurs after at least 131,008 ticks (73 min). The worst projectile case (one slot freed and reused every tick) recurs
after 2,047 ticks (68 s), against a ~35-tick projectile life and a 100 ms interpolation window.

**Alternatives.** (b) `& 0xFFFFFFFF` at every packed-array read: every current and future read site in `sim`,
`sim_ai` and `net` must remember it, and a missed one is a silent equality bug. (c) make the sign-extended int32 the
canonical id: the stores agree, but `decode_u32` yields the positive form, so every `net` decoder would have to
re-sign. (d) `PackedInt64Array` for id fields: +4 B per id field per slot and a change to the 03 s3.2 / s3.3 layouts.

**Docs to patch on confirmation (Architect).** 03 s3.1: "generation (bits 20-31)" -> "generation (bits 20-30; bit 31
always 0)" and "wraps 4095 -> 1" -> "wraps 2047 -> 1"; a B.10 row A-48 in the register. 01 ADR-06 and 04 I15
("generation << 20") stay true as written.

| Role | Name | Date | Verdict |
|---|---|---|---|
| Architect | | | pending (TA-46 erratum) |
| Owner | | | pending |
