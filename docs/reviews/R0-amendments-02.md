# R0 amendments 02: TA-04, TA-11, TA-12, GD-05, TA-06, TA-10, NET-01, NET-02, TA-30 follow-ups (A-8..A-35)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, new subsection B.9 (append-only). No ADR is amended, so no `docs/adr/ADR-NN-amendment-*.md` and no line in 01's amendment log (10 s4.2). A-21 keeps ADR-14's "each module has a MODULE.md" intact; A-20 is already an owner ruling; A-27 grows ADR-14's named-exception list and waits for the owner. |
| **Status** | Decided by the Architect 2026-10-13; A-11's phase order and A-27 are OWNER (defaults stated); A-20 records the owner's ruling of 2026-10-13. |
| **Date** | 2026-10-13 |
| **Raised by** | `docs/waves/2026-10-10-M0.4-M0.5.md` Architect queue: TA-04 (PR #16), TA-11 (PR #19, #28), TA-12 (PR #27), GD-05 (PR #25), TA-06 (PR #26), TA-10 (PR #20); net lane: NET-01 (PR #30), NET-02 (PR #31, CQ-1..CQ-3) |
| **Decided by** | Architect (Fable), 10 s4.1 "Change" row; the owner rules on the OWNER items and approves the required-field / signature / wire-constant changes (A-12, A-13, A-23) |
| **Size** (10 s4.1) | Appends: five optional or required def fields, one trailing optional parameter, five `ContentDB` members, one invariant (N8), one register file. One invariant weakened for projectiles only (S2, owner-decided). One wire constant changed before any shipped wire (A-23). One proposed `deps.json` named-type append (A-27, OWNER). No reorders, no deletes. |

Reading order for a lane engineer: the B.9 table in `docs/reviews/R0-resolution-register.md` is the binding text; this
file is the why. 02 s2.2, s2.3, s5.1, s14; 03 s2.6, s2.8, s3.1, s5.1-5.3, s9.2, s13, s15.3, s15.4; 04 s2.3, s3.2, s3.3,
s7.1, s8; 06 s8, s9.1, s9.3; 10 s4, s4.3; `CLAUDE.md`; `core/MODULE.md`, `content/MODULE.md`, `sim/MODULE.md`,
were patched in the same PR so that no doc contradicts B.9. `net/MODULE.md` is not touched here (NET-02 #31 and NET-11 #34
merged meanwhile); a net follow-up task NET-47 applies A-23..A-26 and A-28 to `codec.gd`, `test_protocol.gd` and `net/MODULE.md`
(migration notes below).

## A-8 (TA-04) `EDGE_NEIGHBOUR` as a flat `PackedInt32Array`, stride 3

**Context.** 03 s2.6 wrote `const EDGE_NEIGHBOUR: Array[PackedInt32Array]`. GDScript 4.7 rejects a typed array of
packed arrays as a constant expression (TA-04, PR #16); `sphere.gd` shipped the 24 rows flattened with
`EDGE_NEIGHBOUR_STRIDE = 3`, and `core/MODULE.md` already documents that form.

**Decision.** The flat form is canonical; 03 s2.6 is corrected. Row `face * 4 + edge` occupies indices `3 r .. 3 r + 2`;
edge ids equal the `dir` ids. Table contents and C5 (regeneration from the face frames) are unchanged.

**Alternatives.** A `static func edge_neighbour(face, edge) -> PackedInt32Array`: allocates per call on the pathing and
footprint paths (03 s12.2 rule 2). A `Dictionary`: `Variant` boxing on the same paths.

**Consequences.** None for consumers beyond reading three ints; `Build.footprint_cells` and `GroundMotion` already use
`neighbour_cell`, not the table.

## A-9 (TA-04) C3 neighbour round trip

**Decision.** `core/MODULE.md` C3 is the canonical wording ("stepping `dir ^ 1` on the same face, or the entered edge
`EDGE_NEIGHBOUR[(face * 4 + dir) * 3 + 1]` across an edge, returns `c`; `neighbours8` symmetric"); 03 s2.6 now states it
next to the table. The cross-edge return path is not `dir ^ 1` because the along-edge coordinate may change role
(u on one face is v on the other), which is exactly what the table's second column encodes.

## A-10 (TA-04) `is_occluded_by_datum` endpoint semantics

**Context.** 03 s2.8 said only "segment-sphere test against radius R". TA-04 implemented: true when the point of the
segment nearest the centre has `0 < t < 1` and lies strictly inside R. Relief reaches -500 m (R0 B.2), so units on maria
and crater floors sit below the datum; a closed-segment or clamped-altitude test would make them self-occluding.

**Decision.** TA-04's semantics are canonical and are now written in 03 s2.8 and `core/MODULE.md`: open segment,
endpoints excluded, no altitude clamp, symmetric, `a == b` false. Two vectors with endpoints below the datum are added
to 03 s2.8; TA-37 (Vision) adds them to `test_sphere.gd` (its lane reads the function; `core` is frozen). Decided here
rather than deferred to TA-37 because the renderer's horizon cull (03 s7.5, TA-25) uses the same function.

**Alternatives.** Clamp both endpoints to `max(|p|, R)`: hides a crater-floor Harvester from a Scout 500 m above it;
wrong for gameplay and for pillar P4. Terrain-aware occlusion: v1.x (03 cross-doc 08).

## A-11 (TA-12) Flip as a sequential half roll then half loop

**Context.** 03 s5.3 forced roll and pitch rates to `PI / flip_duration_s` simultaneously. Two equal body rates about
orthogonal axes compose to a single rotation about `(right + fwd) / sqrt(2)` of `PI * sqrt(2)` radians (254 degrees),
which ends neither upright nor with the heading reversed; TA-12 implemented the only form that meets its acceptance
("flip reverses heading in `flip_duration_s`"): a half roll, then a half loop, each tick turning exactly its share.

**Decision.** The binding rule is the end state (heading reversed, upright, rates zero, in exactly `flip_duration_s`)
and the sequential form; 03 s5.3's pseudo-code and "Flip semantics" paragraph are rewritten. The lock-break window of
02 s4.4 and the 25 percent speed loss remain S-FLIGHT-1's to verify.

**OWNER.** Phase order: roll-then-loop (TA-12 as merged; the altitude signature of a split-S, ship dips then climbs back)
or loop-then-roll (Immelmann-like, ship climbs then settles). This is feel, not correctness, so the recommendation is
to keep the default and let S-FLIGHT-1's testers decide; the swap is one line in `_flip_tick`. Default if the owner says
nothing: roll-then-loop.

**Alternatives.** Simultaneous rates at `PI / (sqrt(2) * flip_duration_s)` about the combined axis: still not a heading
reversal. Slerp of the basis to the reversed pose: hides the rates from `SimView.basis` consumers and the HUD.

## A-12 (TA-12) `step_projectile(..., out: ProjectileState)`

**Context.** TA-12 measured 2.0-2.3 ms per 2,000 projectiles against the 2.5 ms row of 03 s4.2, with the per-call
`ProjectileState.new()` about 65 percent of the cost. B.8 A-8 already said "one reused scratch per `ProjectileMotion`",
but the frozen signature could not take one.

**Decision.** Append a trailing optional parameter: `step_projectile(p, v, def, rules, dt, out: ProjectileState = null)`.
Fills and returns `out` when given; allocates when null. Every existing call site (04 s3.3 client spawn, 05 s6.3.1
`Ballistics.predict_impact`, 06 s6.3 bomb-sight `Callable`) compiles unchanged, so this is an append in effect although
10 s4.1 files a signature change under "Change" (hence this document). Code follow-up TA-43.

**Alternatives.** A second function `step_projectile_into`: two names for one step, and 05/06 docs would drift. A
`ProjectileState` pool in `Kinematics`: a `static var`, which S8 forbids.

## A-13 (TA-12) `flight_common.brake_fade_mps`

**Context.** 03 s5.3 wrote `clamp(v_fwd / 10.0, 0, 1)`; `kinematics.gd` carries it as `_BRAKE_FADE_MPS = 10` with a
note asking 02/03 for a field. ADR-09 and S6 want every sim constant in a def.

**Decision.** `flight_common` gains the required field `brake_fade_mps` (1..30, canonical 10). Required rather than
optional-with-default because a default is a constant in code, which is what ADR-09 forbids, and because the only
`ships.json` in flight (GD-02, PR #29) has not merged. Schema, canonical fixture, 02 s2.2 and 03 s5.1/s5.3 updated;
`FlightCommonDefFixture` and `kinematics.gd` read it in TA-44 (sim) and GD-02 adds the value (migration note).

## A-14 (TA-12) Interim `*DefFixture` types

**Decision.** Accepted as interim, with rules: private to `sim` (never in a Public API block, never named by another
lane), R0 B.1 names only, no new fixture type. TA-45 (sim, after TA-09) swaps the four parameter types for content's
`*Def` classes and deletes `sim/fixture/`; the swap is a type rename and the tests keep loading the canonical fixture
through `flight_test_kit.gd`. TA-09 (content) cannot do the swap itself: `sim/**` is not its lane (10 s4.3).

## A-15 (TA-06) Def classes missing from 03 s15.3

**Context.** R0 B.1 lists `WingDef`, `CallsignDef`, `BarkDef[]`, `SupplyCanisterDef` and `MissionDef`; 03 s15.3's
`ContentDB` had no members for them, so TA-06 flagged the contract incomplete.

**Decision.** Members and classes appended as in B.9 A-15, plus invariant N8 (absent not-yet-shipped files load as
`null` / empty; a present file must validate). TA-09 declares the classes and the "load if present" loader; FEAT-01
(SL-2/3/5 schemas and files) and GD-30 (missions) append the field lists. `chat_filter.json`, `sfx.json`,
`vfx_prewarm.json` are not defs (hash-excluded, 07/04-owned) and get no class.

**Alternatives.** Leave them to the feature tasks entirely: then `ContentDB`'s surface changes four times and each is a
"Change" needing this process; one append now is cheaper.

## A-16 (GD-05) Coop pause "listen host only" stored as a bool

**Context.** B.6 says coop pause is "listen host only"; A-4 typed `pause_save` as a bool; GD-05 stored `true` and
flagged it. 04 s7.1 said pause and save "exist only when every link is local", which contradicts B.6; 06 s8 and 02 s14
agree with B.6. Resolved by citing R0: B.6 wins.

**Decision.** Optional `pause_scope` (`in_process` default / `listen_host`) appended; coop = `true` + `listen_host`.
Save/Load stays offline-only (ADR-10). Validator rules in B.9. 04 s7.1 corrected: the host's `pause()` broadcasts
`ADMIN_NOTICE PAUSE` / `RESUME` (0x91, already in 04's catalogue) and ticks stop for every link.

**Alternatives.** Retype `pause_save` as an enum: a rename of a frozen field (forbidden). A `pause_host_only` bool:
cannot grow when a third scope appears.

## A-17 (GD-05) Skirmish Lite caps for web/mobile

**Context.** 02 s14 and B.6 give skirmish and campaign "standard on native; lite on web/mobile until S-WEB-2 passes at
reduced"; the `caps` enum holds one value. 03 s13 says the caps profile is "a mode and platform property chosen by
`app`"; `Config.default_offline_caps_profile()` exists in `core` but cannot read content (no `core -> content` edge).

**Decision.** Optional `caps_web_mobile` appended; `app` applies it for `in_process` sessions when `Config.is_web()`
or `Config.is_mobile()`. The S-WEB-2 pass flips the value to `reduced` as a data change (the 09 s6 pattern), so the
platform gate lives in JSON (ADR-09), not in code. Validator: allowed only with `in_process` hosting.

## A-18 (GD-05) Promise locale key names

**Decision.** `promise.<id>.audience` / `promise.<id>.human_target` (GD-05's names, matching the file and field names).
CONTRACT-0's fixture used `bot.<id>.audience` / `bot.<id>.target`; it is corrected here (fixture only, never shipped).
Schema patterns and a validator cross-check pin them; 06 s11 owns the strings.

## A-19 (GD-05) Shipyard launch-only pad

**Context.** 02 s5.1 says "launch only" and 02 s2.3 "launch-only, never a service pad"; B.1 had no field, so GD-05 left
the Shipyard with no pad fields and flagged it. The sim needs to know where a produced ship appears and that the socket
never services or accepts landings.

**Decision.** Optional `launch_pad: bool` on structures and towers; `shipyard` sets `true` with `pads` omitted (0).
Semantics in B.9: spawn DOCKED on the socket, leave through the B.5 `LAUNCHED` rule, never a landing or service target,
never returned by `nearest_friendly_pad`. The validator forbids `launch_pad` together with `pads > 0`. The socket's
position is a 07 attachment point in `presentation`, not a sim field (the sim uses the footprint centre and facing).

**Alternatives.** `pads: 1` with `pad_radius_m` 0: a service pad the docking code would have to special-case.
A new structure kind: there is one such structure.

## A-20 (TA-11) Projectile quarantine (owner-decided)

**Decision.** Records the owner's ruling of 2026-10-13: projectiles quarantine 0 ticks (PR #28 implements; the same
03 s3.1 and `sim/MODULE.md` text is applied here so the two PRs merge cleanly). S2 is amended for projectiles only;
04 keys projectile entities by the full `EntityId`, so a same-tick slot reuse with a new generation is a new entity to
every peer. Core follow-up TA-46 (`EntityId.PROJECTILE_SLOT_END`); the `possessed` live list stays with TA-18.

## A-21 `sim/MODULE.md` at 299 of 300 lines

**Context.** The file hit the cap before Spatial, Collision, Combat, Economy, Vision, Orders, Control and Steer have any
API. Two options were on the table: split per subsystem, or move the enumerations to a referenced file.

**Decision.** Split per subsystem; the enumeration block stays where it is. `sim/steer/`, `sim/orders/`, `sim/control/`,
`sim/scoring/` (05's lane, distinct owners) open their own `MODULE.md` from the template with their first code and are
listed in `sim/MODULE.md` by name, so 05's controller, order and control APIs never land in the parent file. Today's
room comes from trimming prose only (299 -> 295 lines; no ordinal, signature or invariant text changed). Tooling:
TA-27's `gen_module_api.py --check` and `check_deps.py` D10 cover nested `MODULE.md` files (TA-27 scope, no new task).

**Alternatives.** Move the enumeration register to a sibling `ENUMS.md`: tried in this PR and withdrawn, because
`godot/test/unit/net/test_protocol.gd` (NET-01) parses the "## Enumerations" bullets of `sim/MODULE.md` to pin
`Protocol`'s wire mirrors; moving them is a contract change to another lane's test, which the Architect does not edit.
That dependency is now written down (10 s4, 03 s15.4): the bullet format is part of the contract. Raise the cap: an
ADR-14 change for a housekeeping problem.

**Consequences.** `sim/MODULE.md` must stay under the cap by moving subsystem APIs out, not by compressing the register.
PR #28's one `MODULE.md` line is kept byte-identical.

## A-22 (TA-10) `quality_tiers.json` deferred to TA-31

**Decision.** Deferral confirmed, but not to TA-31 alone: TA-31 is `presentation+app` and may not author schemas
(10 s4.3), and 03 s9.4 fails CI on a def file without a schema. New Haiku task TA-47 (content+tools) authors
`quality_tiers.json` and `tools/schemas/quality_tiers.schema.json` from the 03 s13 table; TA-31 depends on it and
S-WORLD-1 (TA-25) writes the mesher winner per tier into the file (09 s6 row unchanged).

## A-23 (NET-02 CQ-1, item 12) Position range `POS_EN_HALF` 1,280 m

**Context.** 04 s3.2 reasoned on the datum sphere: every point of an interest cell lies within 900 m of its centre,
so +-1,024 m with a 3.125 cm quantum. But `e = dot(p - c, east)` scales with `(R + h) / R`: a cube-corner cell reaches
1,200 m at the 2,000 m hard ceiling, so positions there clamped above ~827 m with errors up to ~180 m (NET-02 PR #31;
pinned by `test_pos_envelope_pins_cq1` and `Codec.pos_in_range`). The flight envelope is the ceiling, not the ground.

**Decision.** `POS_EN_HALF` = 1,280 m: quantum 3.906 cm, horizontal error <= 2.0 cm, 80 m of margin at the ceiling;
`u` unchanged (its sagitta note now uses 1,200 m, 120 m, still inside -768..3,328). `pos_in_range` must be true for
every cell corner from -500 m to `ceiling_hard_m`, and the NET-02 envelope test asserts that instead of pinning the
clamp. Field sizes, the size table and the 04 s4.6 bandwidth proof are unchanged (still u16); `PROTOCOL_VERSION` stays
1 (R0 B.3: until first shipped wire). NET-02's acceptance bound moves 1.6 -> 2.0 cm (backlog patch).

**Alternatives.** Measure e/n on the datum (scale by `R / |p|`): a divide per encode and decode, a radius-dependent
error (4.2 cm at the ceiling) and a dead-reckoning rule that no longer lives in one frame. Neighbouring-cell frame
selection: changes what the cell means for interest. Both cost more than 0.8 cm of ground precision.

## A-24 (NET-02 CQ-2, item 13) Which flag tier B drops

**Decision.** Bit 5 BRAKING. The coarse orientation's 7 spare bits carry flags bits 0-4 (control state, docked,
firing, boosting) in place, flags bit 6 (shield / cargo / towing) in spare 5 and flags bit 7 (dying) in spare 6; a
tier-B entity reads braking as false. Rationale: at 100+ m the retro flare is the only flag with no gameplay reading
(possession marker, docked, firing, boosting, class state and the wreck animation all are); NET-02's suggestion stands.
NET-06 implements and pins the mapping.

## A-25 (NET-02 CQ-3, item 14) Coarse quaternion bound

**Decision.** The decoder is normative; the encoder is free as long as its output decodes within 6 degrees. NET-02's
one-code refinement (5.07 degrees measured over 200 k samples, adversarial region included) is the reference encoder;
the 6 degree bound of 04 s3.3 stands. Raising the bound to the plain-rounding 7.4 degrees was rejected: visible banking
on B entities is what the coarse form exists for, and the refinement costs ~0.5 us per entity inside the shared cache.

## A-26 (NET-01, item 15) `CHAT_RELAY` 221 vs 222

**Decision.** 222: 04's own field list plus the id byte sums to 222 (8 + 1 + 1 + 4 + 202 + 4 + 1 + 1); `Protocol.CATALOGUE`
already says 222. `test_protocol.gd` pins the deviation (`DOC_MAX_ERRATA`) and fails the moment 04 s2.3 says 222, so the
04 cell, the erratum entry and the `net/MODULE.md` note change together in NET-47 under this decision (a doc patch
named in an amendment, 10 s4.3); the Architect does not edit tests.

## A-27 (NET-01, item 16) Wire mirrors of sim enums and `deps.json`

**Context.** `Protocol` mirrors `CommandResult.Code`, `SimEvent.Kind` and `Build.Reject` as wire enums pinned against
`sim/MODULE.md`; that needs no type dependency. NET-10's `EventRouter` and `ReplayWriter`, however, consume
`SimWorld.drain_events() -> Array[SimEvent]`, and NET-04's `COMMAND_RESULT` codec takes a `CommandResult`; neither type
is in `net`'s named list (R0 B.4, 01 s9.2, `tools/deps.json`), so D1 would fail those tasks.

**Decision (OWNER).** Append `SimEvent` and `CommandResult` to `net`'s named `sim` types; do not append `Build`
(`Build.Reject` travels as the `int` `CommandResult.reject`). This grows ADR-14's named-exception list, which is a
`deps.json` edge change (10 s4.1 "Change") and an 01 s9.2 edit, so it waits for the owner. Recommendation: approve.
Default if the owner says nothing: the Architect applies the one-line `deps.json` edit, the 01 s9.2 net row and an
amendment-log entry in the PR that launches NET-10 (`presentation` and `ui` already hold `SimEvent`, so the layering
direction does not change).

## A-28 (NET-01, item 17) `SessionPhase` home

**Decision.** `Protocol.SessionPhase` in `net/protocol.gd` is the one definition, owned by 04 (B.3 already says "(04)");
`ServerSession` drives it and may reference it because `server` depends on `net`. `sim/MODULE.md`'s parenthetical
"in `server/`" and 04 s8's "owned by `ServerSession`" are corrected to "defined in `net/protocol.gd`, driven by
`ServerSession`". No ordinal changes.

## A-29..A-35 (S-FLIGHT-1, TA-30 REPORT, items 18-24)

Source: `docs/spikes/TA-30/REPORT.md` s3, s5, s6 (PR #37). The human gate is still pending, so every feel decision below
is a default the tester sessions may overturn through TA-30's 02 tuning patch.

**A-29 Flip and velocity (item 18, OWNER).** The report measured the merged TA-12 flip: nose reversed, velocity on the
old heading (105.9 m/s, dot 0.94 after 3 s). 03 s5.3 promised "reverses heading, ~25 % loss"; the lock-break of 02 s4.4
and the "turn to face a pursuer" use both assume the ship leaves the flip flying nose-first. Default: redirect, by
rotating `v` with the body on every flip tick and scaling by `flip_speed_retain` 0.75 on the last tick (one body-frame
preservation, no new state). Alternative: physical (no redirect), with 03 s5.3 reworded and the lock-break kept as a
pure attitude rule. Recommendation: redirect; it is Triplane's roll identity (01 s3.1.1 item 6) and what the doc said.

**A-30 Scrape damage (item 19).** One damage event per contact episode; `scrape_clear_s` 0.5 ends an episode. TA-14.

**A-31 Pad entry in contact (item 20).** Landing is evaluated every tick inside the pad volume, so a sliding ship is
graded by its current speeds; nothing special-cases "already touching". TA-14 / GD-15.

**A-32 Fuel burn (item 21).** 02 s2.3's constants become `flight_common` fields and `step_ship` burns them; owner TA-48
(new sim task: flip redirect, fuel burn, reads the A-29..A-35 fields; Opus, 1 d, depends TA-12, TA-44).

**A-33 Auto-dock radius (item 22).** Horizontal in the pad frame, like `pad_radius_m`; the 3D reading in the spike and
AI-10's `Assist.auto_dock()` is corrected.

**A-34 Auto-dock widening (item 23).** Adopted: `auto_dock_latch_mult` 5 in `flight_common`; the 75 degree L4 tilt is a
landing-controller gain for 05's block (AI-10), not a flight constant. 03 s14.6 already names this fail path as a data
change, so no amendment was needed; it is recorded here because it adds a field.

**A-35 Proposed fields (item 24).** `brake_fade_mps` (done, A-13), `landing_damage_tilt_deg` 45 (accepted),
`auto_dock_latch_mult` (accepted), `auto_dock_transition_tilt_deg` (05's block). The 06 requests in the report (hover
camera blend, auto-level above 45 degrees, MOUSE_AIM clamp) are 06's and go to UX tasks; not decided here.

## Register and impact

| Item | Entry |
|---|---|
| **Affected MODULE.md files** | `godot/src/sim/MODULE.md` (Public API: `step_projectile` `out`; `ProjectileStore._init` default 0; Enumerations: `SessionPhase` note; S2; Open items; prose trimmed to 295 lines). `godot/src/core/MODULE.md` (Conventions: flat table, occlusion semantics; Open items: TA-46 planned append). `godot/src/content/MODULE.md` (Public API: `wing`, `callsigns`, `barks`, `supply_canister`, `missions`, `mission()`; N8; Open items). |
| **Affected tasks (backlog patch for the owner)** | New: **TA-43** sim, Opus, 0.5 d: `step_projectile(out)` + `ProjectileMotion` scratch, perf delta in the PR (depends TA-12). **TA-44** sim, Haiku, 0.25 d: read `flight_common.brake_fade_mps`, delete `_BRAKE_FADE_MPS`, fixture field (depends GD-02). **TA-45** sim, Sonnet, 0.5 d: swap `*DefFixture` for `*Def`, delete `sim/fixture/` (depends TA-09, TA-12). **TA-46** core, Haiku, 0.25 d: `EntityId.PROJECTILE_SLOT_END`, `ProjectileStore.SLOT_COUNT` derived (depends TA-11). **TA-47** content+tools, Haiku, 0.5 d: `quality_tiers.json` + schema from 03 s13 (depends CONTRACT-0). **TA-48** sim, Opus, 1 d: flip velocity redirect (A-29), fuel burn (A-32), reads the A-29..A-35 `flight_common` fields (depends TA-12, TA-44). Changed: TA-14 acceptance adds the scrape-episode rule (A-30) and per-tick pad-volume evaluation (A-31); AI-10 adds `transition_max_tilt_deg` and the horizontal radius (A-33, A-34); TA-31 adds dependency TA-47; TA-27 acceptance adds "`gen_module_api` and D10 cover nested `godot/src/sim/<subsystem>/MODULE.md` files"; TA-37 acceptance adds the two below-datum occlusion vectors; TA-09 acceptance adds N8 and the A-15 members; GD-02 (merged #29) carries `brake_fade_mps` (applied in this PR); TA-30 may file the A-11 phase order in its tuning patch. Net lane: new **NET-47** (net, Opus, 0.5 d, depends NET-02): `POS_EN_HALF` 1,280 with the envelope test and the 2.0 cm bound (A-23), tier-B flag mapping constants (A-24), 04 s2.3 CHAT_RELAY cell + `DOC_MAX_ERRATA` removal (A-26), `net/MODULE.md` open items closed (A-23..A-26, A-28); NET-02's recorded acceptance bound reads 2.0 cm; NET-06 pins the A-24 flag mapping; NET-10 and NET-04 depend on the A-27 `deps.json` edit (Architect, after owner approval). No re-tier. |
| **Affected docs** | R0 Part B.9 (new, append-only); 02 s2.2, s2.3, s5.1, s14, revision log; 03 s2.6, s2.8, s3.1, s5.1, s5.2, s5.3, s9.2, s13, s15.3, s15.4, TA-10/TA-11 rows, revision log; 04 s2.3, s3.2, s3.3, s7.1, s8, NET-02 row, revision log; 06 s8, s9.1, s9.3, revision log; 10 s4, s4.3, revision log; `CLAUDE.md` enumeration rule. 01 unchanged (no ADR touched; 01 s9.4 defers to `sim/MODULE.md` and R0 B; the A-27 s9.2 edit waits for the owner). |
| **Contract tests updated first** | `tools/tests/test_validate_content.py` (`Amendments02`, 5 tests) and 11 new negative fixtures in `tools/tests/fixtures/content/negative.json`, this PR. `godot/test/unit/sim/test_kinematics.gd` (TA-43 `out` identity, TA-44 brake field), `godot/test/unit/core/test_sphere.gd` (TA-37 vectors), `godot/test/unit/core/test_entity_id.gd` (TA-46), `godot/test/unit/net/test_codec_roundtrip.gd` and `test_protocol.gd` (NET-47: `POS_EN_HALF` 1,280, envelope coverage to `ceiling_hard_m`, 2.0 cm bound, erratum removed) when those tasks open. |
| **Gate** | `python tools/validate_content.py`, `python -m unittest discover -s tools/tests`, `python tools/check_deps.py`, `python tools/extract_doc_examples.py --check`, `python tools/gen_module_api.py --check` (TA-27) green in this PR; the `out` parameter enters `sim/MODULE.md` with TA-43, since the check compares existing signatures regardless of planned markers. |

## Sign-off

| Role | Name | Date | Verdict |
|---|---|---|---|
| Architect | Fable 5.1 | 2026-10-13 | A-8..A-35 decided; A-11 phase order and A-29 flip velocity defaults applied pending the owner; A-12, A-13, A-23 (signature / required field / wire constant) proposed for owner approval; A-27 (`deps.json` named types) waits for the owner |
| Owner | | | |
