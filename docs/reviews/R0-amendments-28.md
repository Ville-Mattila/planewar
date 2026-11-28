# R0 amendments 28: a held DOCK after a hook, the client-side DOCK claim, the sticky service pause, who completes RETURN, foundry's contested pair, what `affordable` counts (PM-07; GD-40 PR #203, AI-45 PR #204 and AI-24 PR #193 Opus reviews)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, subsection B.34 (append-only): A-164..A-169 added 2026-11-28. Parts B.1-B.33 are unchanged. No ADR is amended; no enumeration, signature, `deps.json` edge or named type, autoload, addon or thread change by this ruling. A-165 pulls the wire path R0 B.23 A-116 already names forward (NET-63: an enum append and a `PROTOCOL_VERSION` bump, in that task). GD-55 bumps `SimSerialize.FORMAT` by one for the A-164 latch. |
| **Status** | Decided by the Architect 2026-11-28. A-164 (a control rule the player feels), A-165 (a wire task pulled forward) and A-168 (a 05 gate value) are OWNER items and carry their default until the owner rules. |
| **Raised by** | PM-07: GD-40 (PR #203) Opus review rounds 1-2, questions Q1 and Q2; AI-45 (PR #204) Opus review, C1 and C2; AI-24 (PR #193) Opus review comment 7225502421, contract questions 1 and 2. |
| **Decided by** | Architect (Fable), 10 s4.1 and s4.3. |
| **Size** (10 s4.1) | Six register rows, doc patches in 02 s13, 04 s5.2 and 05 s3.2 / s6.2 / s7.3, two new tasks, four amended tasks. The Architect edits no `godot/src/**`, no `godot/test/**`, no schema, no def, no `MODULE.md`, no `backlog.json`. |

Reading order: the B.34 rows in `docs/reviews/R0-resolution-register.md` are the binding text; this file is the why and the backlog patch.

| # | Question | Decision in one line | Follow-up |
|---|---|---|---|
| A-164 | Q1: may `auto_dock` start while DOCK stays held after a hook? | No. A press that hooks is spent until DOCK is released; a saved per-player latch in `Salvage` | GD-55 |
| A-165 | Q2: client recomputes the claim, or the server echoes it? | Recompute, through one shared pure rule; the tow state it needs is not on the wire today, so the A-116 path is built first | NET-63 (new), NET-18, GD-55 |
| A-166 | C1: sticky pause memory, or `SimView.service_paused`? | Sticky reading ratified; no `SimView` append | AI-15 (inherits it) |
| A-167 | C2: who completes a ship's RETURN head? | (b) `Docking`, at SERVICED and at LAUNCHED; no `CommandSinkBase` change | BUG-7 (acceptance replaced) |
| A-168 | Q3: foundry's contested Expansion pair | A deferred tail at `t>=300` (`book_end_s`), now; it does not wait for AI-51; SC-41 judges a pending step just before 5:00 | CONTENT-6 (new) |
| A-169 | Q4: what `affordable` counts | Ore and Ice on hand minus what the slot's own unpaid sites and unstarted queue items owe | AI-52 |

## A-164 A press that hooks is spent until DOCK is released

**Decision (OWNER, default applied).** After a DOCK press whose claim hooks a wreck, `Assist.auto_dock` does not act for that player until DOCK has been released. A new press is a new decision under W12: it claims a wreck if one is in reach, otherwise it keeps its auto-dock meaning (02 s13, A-108).

- **Where.** `Salvage` owns the latch, one byte per player slot: `dock_spent(p) -> bool` (an append). It is set in step 10 when `_dock_pass` links p's claimed wreck. It is cleared in `claim_docks` (step 4, first line) on the first tick p's possessed ship does not hold DOCK or p has no live possession, and by `clear_player` on every possession change. `AssistStep` skips p while `dock_claimed(p) or dock_spent(p)`.
- **Saved.** A hold can span a save, so the latch is saved in S4 (GD-55 bumps FORMAT; it does so anyway if it saves `LandingState`). The claim itself stays unsaved (W12).
- **Set by the hook, not by the claim.** A claim whose hook fails in step 10 (the wreck expired, or another Hauler's W6 pass took it) leaves no latch: the press hooked nothing, so from the next tick DOCK has its auto-dock meaning, as A-108 says. This also keeps the latch equal to a fact the client can observe (A-165): the wreck is tethered to its ship.
- **A-44 and LINK_BRIDGE.** Both clear DOCK in the entity slot, which ends the hold and the latch; the next held tick is a new edge (the W12 note already says so).

**Why.** A-108 chose DOCK reuse so that one button hooks or lands, never both from one press. Without the latch a Hauler that hooks next to its own pad starts a landing one tick later while the pilot's thumb is still down. `LandingState.assist_off` already works this way ("until DOCK is released").

**Alternative (owner).** No latch: auto-dock may start on the tick after the hook. It saves the byte and makes A-165 trivial (one tick of mismatch), at the cost of unwanted landings beside a pad.

## A-165 The client recomputes the claim; the tow state goes on the wire first

**Finding.** Both reviews assume the client can read "wreck positions and F_TETHERED" from the snapshot. It cannot. 04 s3.7 (R0 B.23 A-116, A-117): TETHERED is carried by no wire field, the tow end of `link` is not replicated, and no encoder sets wire flags bit 6. So a client cannot tell a free wreck from a towed one, nor whether its own ship has a free tow slot. A Hauler's own towed wreck rides 26 m behind it (`tether_len_m` 25, `tether_drop_m` 8), inside `salvage_hook_m` 33. A client that recomputed the claim today would "claim" its own tow on every DOCK press and predict no assist for the whole landing of a loaded Hauler, which is the common case.

**Decision (OWNER for the pulled-forward task, default applied).**

1. **Recompute client-side; no server echo.** An echo arrives a round trip after the edge tick, so the client has to predict the claim anyway.
2. **One rule, not two.** The pick (nearest free wreck with centre distance `<= reach_m`, lowest slot on a tie) becomes one pure static on `Assist`, which `net` may already reference (B.4). Proposed shape: `static func dock_pick(ship_pos: Vector3, ids: PackedInt64Array, pos: PackedVector3Array, reach_m: float) -> int` (the caller passes free wrecks in ascending slot order; 0 = none). `Salvage.claim_docks` and `Prediction` both call it. An append; GD-55 may adjust the parameter list in review. No `deps.json` change.
3. **The data.** NET-63 builds the path A-116 names: `SimEvent.Kind` `TETHERED` / `UNTETHERED` (wreck, ship), and the encoder sets wire flags bit 6 on a ship that tows and on a wreck that is towed (04 s3.3 "towing (per def class)"; the wreck half is the clause this row adds). `NetSimView` then answers `link(wreck)` and the TETHERED flag. ART-17's `vfx_tether` needs the same pairs.
4. **The latch on the client.** The client sets its A-164 latch from its own predicted claim and corrects it from the events: `TETHERED(wreck, own ship)` stamped with the edge tick sets it; a snapshot at or after the edge tick without that pair clears it. A wrong guess costs one reconciliation.
5. **Until NET-63 is done,** `Prediction` does not model the claim: it predicts `auto_dock` as if no wreck were in reach. That is right for a loaded Hauler and wrong only while DOCK stays held after a hook inside `auto_dock_radius_m` of a free friendly pad.

**Alternative (owner).** A server echo of the latch (one bit in the own-pilot block): also a `PROTOCOL_VERSION` bump, still needs the edge-tick prediction, and leaves ART-17 without its pairs.

## A-166 The sticky service pause is ratified

**Decision.** 05 s6.2 DOCKED now reads: once a service timer of the current stay has paused for Ice or Ore, the ship leaves at `fuel01 >= landing.auto_launch_fuel01`; the memory lasts until the ship flies. This is `OV_SVC_PAUSED` as AI-45 built it (saved in `ov_flags`, kept through possess and release). No `SimView.service_paused`.

**Why.** 02 s2.3's intent is that an empty pool never holds a ship on the pad. A bot spends its pool to zero between deliveries, so a "paused right now" reading would flicker between the two exits from one think to the next; the sticky one is stable. A ship that leaves short of ammo or hull comes back under the common RTB rule (05 s6).

**Alternative.** Append `SimView.service_paused(id) -> bool` (sim, about 0.5 d: `local_sim_view.gd` is at the A-73 line, a `NetSimView` stub, a TEST-02 clause). Reopen it only if an M3 playtest shows ships leaving under-serviced while the pool is positive.

## A-167 `Docking` completes RETURN

**Decision: (b).** In step 10 `Docking` completes a ship's standing RETURN head through `ControlOrders.complete_head` (ORDER_DONE, value = RETURN; 05 C4):

- on the tick it emits SERVICED for that ship, after the SERVICED event;
- on the tick the ship LAUNCHES from a service pad (D13) with a RETURN head still standing, after the LAUNCHED event. This covers the A-119 paused-fuel exit and a pilot who launches early.

Only a head whose kind is RETURN is touched. A D10 release (the pad is gone) completes nothing: the ship still needs a pad. A POSSESSED ship's saved queue is popped the same way and its control state stays POSSESSED (`_settle` already returns early).

**Why (b).** "DOCKED and fully serviced" (05 s3.2) is a sim fact that `Docking` computes and no brain decides. A possessed ship has no brain running when SERVICED fires. A Bomber cannot see the order queued behind its RETURN, so only the sim can hand it the ATTACK. Nothing is added to `CommandSinkBase`.

**Rejected: (a)** an appended `CommandSinkBase.complete_head(id)` called by the brain on leaving DOCKED. It misses the possessed case and the Bomber's queued order, and it gives `sim_ai` an unvalidated write for a fact the sim already has.

**BUG-7 as filed does not fit:** it completes "when the ship leaves DOCKED" through a path "PM-07 rules". Its acceptance is replaced below. Its four `sim_ai` tests stay; the Bomber clause becomes "an order head exists".

## A-168 foundry's contested pair is a deferred tail at `t>=300`

**Measured (PR #193, the book's `_doc` and the review).** The 4:30 move goes out at 4:29; the site is 2,365 m away; the only Dart is refuelling after the home-trap escort; nobody is present by 5:00. Under A-163 a pair whose move has been sent must also place its Outpost before 5:00 or SC-41 fails, and the hand-over drops it without leaving a "book's time" for the reactive Expansion rule (05 s7.5).

**Decision (OWNER, default applied).** `foundry_standard`'s contested pair is gated `t>=300` and sits at the end of the book, after `set_replenish harvester 6` (A-163: a deferred pair is the tail). 300 is `book_end_s`, the earliest gate A-163 allows for a deferred pair; no new number. Foundry still expands first: 5:00, bulwark 5:30, vanguard 7:00 or Ore 900. The 05 s7.3 listing is patched in this PR; CONTENT-6 ships the data now.

**The boundary (A-163 was silent at equality).** A gate equal to `book_end_s` is a deferred gate: the interpreter ends the book at `t_s >= book_end_s` before it looks at the step (`OpeningBook.think`), so it can never run it. SC-41 takes its snapshot on the first think at or after 5:00, where `t>=300` already reads true and `waits_on_clock` says no. SC-41 therefore judges a pending step at the last instant of the book: with `t_s` capped strictly below `book_end_s`. The verdicts for `t>=330` and `t>=420|ore>=900` do not change. CONTENT-6 makes that one-line change in the scenario test.

**Why not wait for AI-51.** AI-51 fixes the escort orbit, not the 30 s window or the Dart's fuel. A 4:30 pair that fits on `cradle` and misses on a larger map is dropped at the hand-over and leaves the doctrine with no book time; a deferred gate is always read.

**Alternative (owner).** Keep `t>=270` in 05, ship no pair now, and re-add it after AI-51 if SC-41 passes.

## A-169 `affordable` counts what is already owed

**Decision.** `affordable` is true when Ore on hand minus Ore owed covers the step's doctrine-resolved Ore cost, and the same for Ice. Owed = the resolved cost of the Commander slot's own construction sites that are placed and not yet paid (QUEUED; `sim/build` B7 pays when assembly starts) plus its own factory queue items that have not started (`sim/production` P2). Each is counted once and leaves the sum on the tick the sim takes the payment. `ore>=X` and `ice>=X` terms stay on-hand amounts. The reactive managers (05 s7.5, s7.6) use the same function.

**Why.** A-162: "a step that waits for funds blocks the steps behind it". With on-hand Ore two costed steps close DONE against the same Ore (bulwark's Flak: placed 3:12, paid 4:20), so SC-41 reports a book as complete that its income did not pay for.

**Alternative.** Ore on hand, as built: simpler, and it lets a book run ahead of its funds. If the shipped books no longer pass SC-41 under the stricter reading, AI-52 names a content refit task; that is the honest result.

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

Checked on `main` at db5ae54: NET-62 and CONTENT-5 are the highest NET / CONTENT ids; NET-63, CONTENT-6, A-164..A-169, B.34 and `R0-amendments-28.md` are unused. BUG-7, GD-55, AI-51, AI-52, NET-18, AI-15 and ART-17 are `todo`. NET-18 and AI-15 already have an `acceptance_append`; the text below is appended to it. GD-55, AI-51 and AI-52 gain the field.

```json
{
  "new": [
    {"id": "NET-63", "title": "sim+net: replicate the tow state: TETHERED / UNTETHERED events and wire flags bit 6 (R0 B.23 A-116 named path, pulled forward by R0 B.34 A-165)", "lane": "sim+net", "tier": "Sonnet", "size_days": 1.0, "depends_on": ["GD-40", "NET-17"], "milestone": "M4", "acceptance": "SimEvent.Kind gains TETHERED and UNTETHERED at the end (append; a = wreck, b = ship; sim/MODULE.md); Salvage emits TETHERED when a wreck is linked (W6 hook, W12 DOCK hook) and UNTETHERED when a tow ends without delivery or death (release, the ship dies); 04 s3.6 payload row wreck u16 + ship u16, roster scope, EventRouter row; the snapshot encoder sets wire flags bit 6 on a ship that tows at least one wreck and on a wreck that is towed (04 s3.3); PROTOCOL_VERSION + 1; NetSimView.link(wreck) returns the towing ship and flags() reports TETHERED on both ends, 0 / clear with field_unknown true only for a pair tethered before both entered the roster; NetUnknown lists updated (A-117); tests: an event round trip, a client that sees hook, tow and delivery reads link and flags as LocalSimView does on the same ticks, a late joiner reads bit 6 with link unknown; the task edits 04 s3.3 / s3.6 / s3.7 (shared file authorised by A-165); sim/salvage/MODULE.md and net MODULE.md files updated; perf note (snapshot bytes unchanged, one event per hook)", "docs": ["docs/reviews/R0-amendments-28.md", "04 s3.3", "04 s3.6", "04 s3.7", "godot/src/sim/salvage/MODULE.md"]},
    {"id": "CONTENT-6", "title": "content: foundry_standard gains its contested Expansion pair as a deferred tail at t>=300 (R0 B.34 A-168)", "lane": "content+sim_ai", "tier": "Sonnet", "size_days": 0.25, "depends_on": ["AI-24", "AI-50"], "milestone": "M3", "acceptance": "build_orders.json foundry_standard ends with order move dart|scout to contested_field when t>=300 and build outpost near contested_field when presence, after set_replenish harvester 6; the _doc drops the 'cut' sentence and cites A-168; test_shipped_books.gd pins 3 deferred pairs (vanguard, bulwark, foundry) and asserts each deferred gate is >= book_end_s; test_sc41_all_books.gd judges a pending step at the last instant of the book: the hand-over snapshot's t_s is capped strictly below book_end_s before expansion_waits_on_clock (the interpreter ends the book at t_s >= book_end_s, so a gate equal to book_end_s never ran), and the verdicts of the other five books do not change; no godot/src change; SC-41 passes on all six books and both slots with foundry_standard pending at 5:00 only on that move, waiting on the clock; validate_content green; no other book changes", "docs": ["docs/reviews/R0-amendments-28.md", "05 s7.3"]}
  ],
  "acceptance_replace": {
    "BUG-7": "R0 B.34 A-167: in step 10 Docking completes a ship's standing RETURN head through ControlOrders.complete_head (ORDER_DONE, value = RETURN; 05 s2.3 C4) (a) on the tick it emits SERVICED for that ship, after the SERVICED event, and (b) on the tick the ship LAUNCHES from a service pad (D13) with a RETURN head still standing, after the LAUNCHED event (the R0 B.24 A-119 paused-fuel exit, a pilot's early launch); only a head of kind RETURN is touched; a D10 release (pad gone) completes nothing; a POSSESSED ship's saved queue is popped the same way and its control state stays POSSESSED; no CommandSinkBase, SimView or enum change, no FORMAT change, S4 round trip across the completion byte-exact. Sim tests (docking suite): SERVICED then ORDER_DONE(RETURN) once on the same tick with a PATROL behind it becoming the head; a head that is not RETURN is untouched; a possessed docked ship reaching SERVICED loses its saved RETURN and stays POSSESSED; an early launch emits LAUNCHED then ORDER_DONE(RETURN); a pad destroyed under a docked ship leaves the RETURN head. Tests in test/sim/ai/test_docked_mode.gd: (1) a Dart docked with a system RETURN (FLAG_PREPEND) ahead of a PATROL order launches once after SERVICED, emits ORDER_DONE(RETURN) once and resumes the PATROL: exactly 1 LAUNCHED and 0 further DOCKED in 120 s; (2) a Dart whose only order is RETURN goes AUTO and is tagged PATROL above launch_climb_agl_m; (3) a Bomber docked with a RETURN head and an ATTACK queued behind it (FLAG_QUEUE) launches on the ATTACK after SERVICED; (4) DockedMode's Bomber clause head.kind != RETURN becomes 'an order head exists'; (5) a Dart on the paused-fuel exit (Ore 0, fuel01 >= auto_launch_fuel01) emits ORDER_DONE(RETURN) once at LAUNCHED and makes 0 further DOCKED for that order in 60 s; sim/docking/MODULE.md gains the invariant (D15), sim/control/MODULE.md Open items names Docking as the RETURN caller, sim_ai/MODULE.md updated; perf note"
  },
  "acceptance_append": {
    "GD-55": "; R0 B.34 A-164: Salvage owns the latch: dock_spent(p) -> bool (append), one byte per player slot, set in step 10 when _dock_pass links p's claimed wreck, cleared in claim_docks on the first tick p's possessed ship does not hold DOCK or p has no live possession, and by clear_player; saved in S4 (FORMAT + 1; the claim stays unsaved); AssistStep skips p while dock_claimed(p) or dock_spent(p); a claim whose hook fails in step 10 sets no latch; tests: (e) setup (a) with DOCK held for 90 more ticks: no assist tick; release, then a press with no free wreck in reach: auto_dock acts; (f) a claimed wreck taken by another Hauler's W6 pass in step 10: auto_dock acts from the next tick; (g) save / restore mid-hold is byte-exact and the latch holds after it; R0 B.34 A-165: the pick rule (nearest free wreck with centre distance <= reach_m, lowest slot on a tie) is one pure static Assist.dock_pick (append; proposed (ship_pos: Vector3, ids: PackedInt64Array, pos: PackedVector3Array, reach_m: float) -> int, 0 = none) that claim_docks calls; the GD-40 suite passes unchanged",
    "NET-18": "; R0 B.34 A-165: predicted step 4 recomputes the W12 DOCK claim for the local player with Assist.dock_pick over the free wrecks NetSimView reports (TETHERED clear, NET-63), the DOCK edge from its own input history and the free tow slot from the def's tow_slots, the team's Doctrine and the wrecks linked to its ship; it skips Assist.auto_dock on a claimed tick and, per A-164, while that press stays held; the latch is corrected from the server: TETHERED(wreck, own ship) stamped with the edge tick sets it, a snapshot at or after the edge tick without that pair clears it; no server echo; a claim or latch mismatch is resolved by normal reconciliation; tests: a loaded Hauler (tow slots full) holding DOCK inside auto_dock_radius_m predicts the same auto-dock as the server (its own towed wreck is never claimed); an empty Hauler pressing DOCK with a free wreck in reach beside a free pad predicts no assist tick while held, as the server; a hook lost to another Hauler on the edge tick costs at most one reconciliation",
    "AI-51": "; R0 B.34 A-168: foundry_standard's contested pair is CONTENT-6's (a deferred tail at t>=300) and is not part of this task's content follow-up, which is bulwark_standard's home-trap move back to 05's form only",
    "AI-52": "; R0 B.34 A-169: owed = the doctrine-resolved Ore and Ice of sites and factory queue items whose owner is the Commander's player slot and that the sim has not yet charged (a site before assembly starts, sim/build B7; a queue item before it starts, sim/production P2), each counted once and dropped on the tick it is paid; ore>=X and ice>=X terms stay on-hand amounts; the reactive managers call the same function; a SimView accessor the sum needs and lacks is an append in this task's PR (10 s4.1), flagged 'Contract impact: append'",
    "AI-15": "; R0 B.34 A-166 / A-167: the Hauler's DockedMode uses the sticky pause memory as ratified; the Hauler brain never completes a RETURN head (Docking does); its complete_head / fail_head calls for HAUL / TOW (A-108) need a brain path to ControlOrders that does not exist: the task appends it to CommandSinkBase (10 s4.1 Append, 'Contract impact: append') or raises a contract question"
  },
  "depends_on_append": {
    "NET-18": ["GD-55", "NET-63"]
  },
  "note": {
    "PM-07": "Ruling R0-amendments-28 (B.34 A-164..A-169): a hooking DOCK press is spent until release (Salvage latch); the client recomputes the claim after NET-63 puts the tow state on the wire; sticky service pause ratified; Docking completes RETURN at SERVICED / LAUNCHED; foundry's contested pair deferred to t>=300; affordable subtracts what the slot owes.",
    "ART-17": "R0 B.34 A-165: the A-116 tow path (TETHERED / UNTETHERED, NetSimView.link(wreck)) is built by NET-63; ART-17 depends on it instead of filing it.",
    "GD-40": "R0 B.34 A-165: the acceptance's 'the client sees the TETHERED flag from the snapshot' does not hold on the current wire (04 s3.7: TETHERED is not carried); NET-63 makes it true."
  }
}
```

New work: 1.25 d (NET-63 1.0 d in M4, CONTENT-6 0.25 d in M3). GD-55 stays 1.0 d and BUG-7 0.5 d. Order: GD-55 and BUG-7 before the M3 playtests; NET-63 before NET-18.

## Not ruled here

- **Brain-known completions** (ATTACK done, MOVE arrived, HAUL / TOW delivered; A-61, A-108): still unwired, and `sim_ai` has no path to `ControlOrders`. An appended `CommandSinkBase` method is an Append (10 s4.1) and stays with AI-15; A-167 covers RETURN only.
- **A spent hold is still a pad wish** (`PilotTrack.dock_held`, docking D6). It ends with the hold; GD-55 reports it if a test shows a queue effect.
- **A paused-fuel launch below `rtb.hp01`** returns to the same empty pool. That is A-119 as decided; BUG-7's test (5) records what it does.

## Decisions for the owner

1. **A-164 a hooking DOCK press is spent until release.** Alternative: auto-dock may start on the next tick. Recommendation: as ruled. Default if silent: as ruled; GD-55 runs with the appended clause.
2. **A-165 build the A-116 tow path now (NET-63, 1.0 d, M4, `PROTOCOL_VERSION` + 1) and recompute the claim client-side.** Alternatives: a server echo bit; or no NET-63, and `Prediction` ignores the claim (wrong only during a hold after a hook beside a pad). Recommendation: NET-63; ART-17 needs it anyway. Default: NET-63 is filed and NET-18 waits for it.
3. **A-166 sticky service pause.** Alternative: `SimView.service_paused` (0.5 d). Recommendation: sticky. Default: sticky.
4. **A-167 `Docking` completes RETURN at SERVICED and at LAUNCHED.** Alternative: the brain through `CommandSinkBase`. Recommendation: as ruled. Default: as ruled; BUG-7 runs on the replaced acceptance.
5. **A-168 foundry's contested pair at `t>=300`, shipped now.** Alternative: keep 4:30 and retry after AI-51. Recommendation: `t>=300`. Default: `t>=300`; CONTENT-6 runs.
6. **A-169 `affordable` subtracts owed Ore and Ice.** Alternative: on hand. Recommendation: as ruled. Default: as ruled; AI-52 runs.
7. **The backlog patch:** NET-63 and CONTENT-6 new (1.25 d); BUG-7 replaced; GD-55, NET-18, AI-51, AI-52, AI-15 appended; NET-18 depends on GD-55 and NET-63. Recommendation: as written. Default: as written.
