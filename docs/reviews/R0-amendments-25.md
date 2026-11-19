# R0 amendments 25: the ground barrel contract: `barrel_*` def keys, `SimView.barrel_elevation`, ground `pitch` as a slew rate, the barrel controls (GD-50 PR #182, three Architect questions from its Opus review plus the ground input mapping)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, subsection B.31 (append-only): A-151 .. A-155 added 2026-11-19. The B.1 `ground_units.json` sentence gains one clause (A-151); the B.5 tick order and `SimView` list gain one pointer each (A-152, A-153). 06 s3.2, 04 s2.4, 04 s3.7, 03 s4.1, 03 s15.4 and 07 s4.2 are patched in place. No ADR is amended; no enumeration, `deps.json` edge, wire layout, autoload, addon or thread change; `PROTOCOL_VERSION` unchanged; `SimSerialize.FORMAT` 17 -> 18 (PR #182, ratified by A-153). |
| **Status** | Decided by the Architect 2026-11-19; the OWNER item (A-154) carries its default until the owner rules. |
| **Raised by** | GD-50 (PR #182), Opus review comment 7016176193, verdict "approve", with the acceptance clause "Architect confirms whether an R0 row is needed" left open: three contract questions and one `needs input:` conflict with 06 s3.2. |
| **Decided by** | Architect (Fable), 10 s4.1 (optional def fields and a new public function are Appends; the meaning of a `PilotInput` axis is a Change) and 10 s4.3. |
| **Size** (10 s4.1) | Five register rows, one B.1 clause, two B.5 pointers, six in-place doc patches, five new tasks, four acceptance appends, one dependency append. The Architect edits no `godot/src/**`, no `godot/test/**`, no schema, no def, no `MODULE.md`. |

Reading order: the B.31 rows in `docs/reviews/R0-resolution-register.md` are the binding text; this file is the why, the author's work list and the backlog patch.

**Outcome for PR #182 in one line:** everything is ratified as built except the NAN return of `SimView.barrel_elevation` (A-152); that change and two citation edits are listed under "What PR #182 changes before merge". The input conflict (A-154) does not block it.

## A-151 Def keys: three optional `barrel_*` keys on `ground_units.json`

**Decision.** Ratified as an append.

| Key | Type, bounds | Meaning | Absent |
|---|---|---|---|
| `barrel_slew_dps` | number, 0 .. 180 | elevation rate at full `pitch`, degrees per second | 0 |
| `barrel_min_deg` | number, -30 .. 85 | lowest elevation, degrees above the local horizontal at the unit | 0 |
| `barrel_max_deg` | number, -30 .. 85 | highest elevation | 0 |

A def has a barrel when any of the three is non-zero. Rest is `clamp(0, barrel_min_deg, barrel_max_deg)`. With `barrel_slew_dps` 0 the barrel is fixed at rest. A def without a barrel fires along its heading, as before GD-50. Doctrines do not modify the keys.

**Siege Crawler: 10 / 0 / 45, resting level, as GD-50 tuning anchors** (GD-34 may retune, the `ground_turn_rate_dps` precedent of B.12 A-65). Evidence, PR #182 table: a lofted shot at 1,000-1,150 m needs 13.3-17.0 deg on flat and on cradle relief; the barrel gets there from rest in 40-52 ticks (1.3-1.7 s), inside the 4.0 s reload; the worst `predict_impact` gap is 3.65 m against `loft_tol_m` 15.

**What 45 deg is not.** It is not the range limit. The range stays `siege_gun` `range_m` 1,200 / `range_min_m` 300 (02 s4.1, B.8 A-2). From the defs (110 m/s, g 6.0, `siege_shell` `lifetime_s` 12): a level-ground flight lasts `2 x 110 x sin e / 6` seconds, which passes 12 s at about 19 deg (about 1,250 m). This is arithmetic, not a measurement, and nobody has tested what a possessing player sees when a shell reaches its end of life in the air. AI-18b measures the highest useful elevation and reports it (A-155); GD-34 then decides whether `barrel_max_deg` drops. Until then 45 stands because nothing measured argues for another number.

**Cross-field rules** (CONTENT-5, in `validate_content.py`, the A-19 precedent; one negative case each): `barrel_min_deg <= barrel_max_deg`; the keys only on an entry whose `weapon` is not null. The sim keeps swapping reversed limits; the validator makes sure it never has to.

**Typed fields.** `GroundUnitDef` is the content lane's. PR #182 reads `raw` (the TA-56 `structure_bomb_mult` precedent) and `ContentSet.warnings` lists the keys as unknown until CONTENT-5.

## A-152 `SimView.barrel_elevation(id) -> float`: ratified, without the NAN

**Decision.** The accessor is an append to the B.5 list and 03 s15.4:

```gdscript
func barrel_elevation(id: int) -> float   # radians above the local horizontal at the unit; 0.0 for no barrel / dead / not received
```

- Live ground unit whose def has a barrel: its elevation (the def's rest before the first slew).
- Every other id (no barrel, not a ground unit, dead, stale): 0.0.
- A view that has not received it: **0.0, not NAN.** The base `SimView` returns 0.0. `NetSimView` returns 0.0 with `field_unknown(id, &"barrel_elevation")` true until NET-61.

**Why not NAN.** The base class states its own invariant ("every accessor returns the neutral default"), and 04 s3.7 with B.23 A-116 already defines "no data" for every accessor: the default plus `field_unknown`. `overlay`, `cargo`, `cargo_kind` and `link` follow it. A second convention for one accessor is a third position; R0 has one. In practice a NAN that reaches a `Basis` in `presentation` or an angle in the HUD corrupts the transform on every client; a level barrel flagged unknown does not.

**Wire.** 04 s3.7 gains the row "not replicated until NET-61". Named path, not built: one `barrel u8` = `round((e - barrel_min) / (barrel_max - barrel_min) * 255)` (0.18 deg at the Crawler's 0-45 deg) for an entity whose def has a barrel, in tier A and FULL records, with a `PROTOCOL_VERSION` bump. NET-61 states the exact placement in its PR as "Contract impact: change (R0 B.31 A-152)"; it comes back to the Architect only if it needs a new message id or grows the tier B record. Replays are command-driven and unaffected (the review's note).

**Readers.** `sim_ai` (AI-18b), `ui/hud` (UX-49), `presentation` (ART-40). `SimView` is already on each reader's B.4 list; no `deps.json` edge.

## A-153 Ground `pitch` is a slew rate

**Decision.** As built. For a live ground unit whose def has a barrel, each tick:

```
e = clamp(e + clamp(pitch, -1, 1) x barrel_slew_dps x dt, barrel_min_deg, barrel_max_deg)
```

`+` raises the muzzle, 0 holds the barrel where it is, there is no rate lag and no return to rest on release or hand-over. A unit spawns at rest. A def without a barrel ignores `pitch`. The input slot is the only source: a possessing player and `CommandSink.drive` slew by the same law, and S11 keeps an autopilot off a possessed barrel.

**Grounds, all from existing text.**
- Towers already read `pitch` / `yaw` as slew rates (B.3 `PilotInput` comment, 02 s4.4, B.23 A-118).
- `PilotInput` has no absolute aim field and its axes are -1 .. 1 (04 s2.4). An angle reading would need a mapping from the axis to degrees per def and would be quantised by the input byte.
- Digital controls (keys, touch buttons) reach every angle only with a rate.
- A brain loses nothing: `pitch = clamp((e* - barrel_elevation) / (rate x dt), -1, 1)` reaches `e*` to 1e-12 (`test_dead_beat_slew_reaches_an_exact_elevation`).

**Ratified with it, as built.** `BarrelSlew.step` in tick step 5 after `GroundMotion.step`; the CB15 shot frame (`dir = h cos e + n sin e`, `n` the radial at the unit, `h` its heading, muzzle `pos + dir x radius`); the barrel state (`elevation` f64, `bound` EntityId per main-range slot) saved after the entity store, `SimSerialize.FORMAT` 17 -> 18. It is not an `EntityStore` field, so 03 s3.2 is unchanged. `PROTOCOL_VERSION` is unchanged: `pitch` already travels in `INPUT`.

**Patched in place.** 06 s3.2 (the row's last column and a new "Barrel" paragraph), 04 s2.4 (ground clause), 03 s4.1 (step 5 in the diagram), 03 s15.4 (the accessor).

## A-154 The barrel controls (OWNER, default applied)

**The conflict.** `InputRouter` has no ground mapper; GROUND mode samples the flight mappers. So on `main` today, before GD-50, a ground unit's drive is on the thrust control (RT, W, the slider) and stick Y / mouse Y feed `pitch`, which did nothing. 06 s3.2 gives left-stick Y to drive and the mouse to the camera orbit, and names no barrel control. GD-50 makes `pitch` do something, so the gap becomes visible.

**Decision.** 06 s3.2 stands as written and the barrel gets digital holds of its own, on controls 06 leaves free on the ground:

| Input class | Barrel up / down | Why it is free |
|---|---|---|
| Gamepad | RB / LB (hold) | the flight yaw bumpers; on the ground LS X steers |
| KBM | E / Q (hold) | the flight yaw alternates; on the ground A / D steer |
| Touch | BARREL UP / BARREL DOWN hold buttons (`ux_barrel_up`, `ux_barrel_down`) | the thrust slider is not shown on the ground (drive is on the stick) |

They send `pitch` = +1, -1 or 0. `invert_pitch` does not apply. In GROUND mode stick Y and mouse Y never reach `pitch`. A unit without a barrel sends 0 and shows no barrel control. UX-48 builds the ground mapper.

**Does it block PR #182? No.**
1. The fault is the missing ground mapper, in the `input` lane. GD-50's law is the same whichever control feeds it.
2. The shipped state is not wrong for players, because no player can reach it: nothing outside `input` calls `InputRouter.set_mode` (grep of `godot/src` at d1040fe), and `app/match_controller.gd`, which will, is UX-39 (todo).
3. UX-39 gains UX-48 as a dependency, so GROUND mode is never entered on the flight mappers.

**Not accepted.** Stick Y, mouse Y or right-stick Y as the barrel: 06 s3.2 gives them to drive and the camera orbit. An absolute "aim where the camera looks" barrel: it needs an angle input and contradicts A-153.

**Why OWNER.** Which buttons a player presses is a feel decision 06 never made. The default above changes no existing 06 binding.

## A-155 Follow-ups, and the muzzle offset

| Task | Lane, tier, size, milestone | What |
|---|---|---|
| NET-61 (new) | net, Opus, 1.0 d, M4 | replicate the elevation (A-152's named path); `barrel_elevation` leaves `NetUnknown.NEVER` |
| CONTENT-5 (new) | content+sim, Haiku, 0.2 d, M3 | typed `GroundUnitDef.barrel_*`; `BarrelSlew` reads them; the two cross-field rules |
| UX-48 (new) | input, Sonnet, 1.5 d, M3 | ground mapper for the three input classes (A-154) |
| UX-49 (new) | ui/hud, Sonnet, 0.5 d, M3 | elevation readout for a possessed barrel unit |
| ART-40 (new) | presentation, Sonnet, 0.5 d, M3 | the view pitches the `Barrel` node by `SimView.barrel_elevation` |
| AI-18b (append) | sim_ai | reads `SimView.barrel_elevation`, slews dead-beat, solves from the sim muzzle |
| ART-08 (append) | assets | the Siege Crawler's `Barrel` is a separate object (07 s4.2, patched) |
| UX-06 (append) | ui/hud | the two touch barrel buttons in GROUND mode |
| UX-39 (dependency) | app | + UX-48 |

**The muzzle offset is not a defect.** `SiegeAim.loft` puts the muzzle at `p + tangent x radius`; the sim puts it at `p + (h cos e + n sin e) x radius`, 1.7-2.1 m higher at 14-17 deg (the author's note 4). That is inside `loft_tol_m` 15 m and the PR's measured misses (0.55-3.51 m) already include it. AI-18b removes the bias at the source: `SiegeAim.loft` calls the static `BarrelSlew.muzzle_dir` / `muzzle_up` of `sim/ground/MODULE.md` instead of carrying a second copy of the formula. Those two functions are pure and public; `sim_ai` -> `sim` is an allowed edge; the `BarrelSlew` instance stays lane-internal.

## What PR #182 changes before merge (author)

Required (one push, no commit split, squash merge):

1. **No NAN (A-152).** `godot/src/sim/sim_view.gd`: the base `barrel_elevation` returns `0.0`; its doc comment says "0.0 on a view that has not received it (NetSimView until NET-61, with field_unknown true)". `godot/src/sim/MODULE.md`: the accessor's comment reads `0.0 none / dead / not received; R0 B.31 A-152` instead of `0 none / dead, NAN no data` (same line, the file stays at 300 lines).
2. **`NetUnknown.NEVER`.** `godot/src/net/client/net_unknown.gd`: add `"barrel_elevation"` to `NEVER` and name it in the list's comment ("no codec yet: ... barrel_elevation NET-61"). This ruling permits the GD-50 author that one edit in the `net` lane.
3. **Contract factory.** `godot/test/unit/sim/contract/factories/net_sim_view_factory.gd`: drop the `barrel_elevation` exemption if the clause now passes for `NetSimView` (it asserts 0.0 on four ids without a barrel, which is what the base returns). If it does not pass, keep the line and say why in the PR.
4. **Citations.** `ground_units.json` Crawler `_doc`: "tuning values pending an R0 B.1 row" becomes "tuning anchors, R0 B.31 A-151". The three schema `$comment`s cite R0 B.31 A-151. `sim/ground/MODULE.md` B1 and the `PilotInput` comment in `sim/MODULE.md` cite R0 B.31 A-153 where they now cite GD-50 only.
5. **PR body.** "Contract impact: append (R0 B.31 A-151, A-152) and change (`PilotInput.pitch` for ground units, R0 B.31 A-153)".

Optional (the review's nits): CB15 says that for a barrel unit the spread axis is the radial-frame `muzzle_up` even at `e = 0`.

Nothing else changes. The Opus approval stands for the rest; the re-review is items 1-3 only.

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

Ids checked free on `main` at d1040fe (highest in use: NET-60, CONTENT-4, UX-47, ART-39; GD-50, GD-51, AI-49, UX-47 are taken and not reused).

```json
{
  "new": [
    {"id": "NET-61", "title": "net: replicate the ground barrel elevation for barrel defs at tier A and FULL; NetSimView.barrel_elevation reads it (R0 B.31 A-152)", "lane": "net", "tier": "Opus", "size_days": 1.0, "depends_on": ["GD-50"], "milestone": "M4", "acceptance": "One u8 per replicated entity whose def has a barrel, round((e - barrel_min) / (barrel_max - barrel_min) * 255), in tier A and FULL records; the placement, mask bit and byte cost are stated in the PR as 'Contract impact: change (R0 B.31 A-152)' and 04 s3.3 / s3.4 / s3.7 are updated in the same PR; PROTOCOL_VERSION bumped; an entity without a barrel pays zero bytes (the bench hash and byte budget of a scene without a Siege Crawler are unchanged); NetSimView.barrel_elevation returns the decoded value within one quantum (the contract factory tolerance gains the accessor) and 0.0 with field_unknown true at tier B / C; 'barrel_elevation' leaves NetUnknown.NEVER; a slewed-Crawler case is added to the SimView contract clause and passes for LocalSimView and NetSimView; the PR says whether the possessing client predicts its own barrel or shows the replicated value; perf note (prepare_tick delta on the canonical bench); a design that needs a new message id or grows the tier B record goes back to the Architect", "docs": ["docs/reviews/R0-amendments-25.md", "04 s3.3", "04 s3.4", "04 s3.7"]},
    {"id": "CONTENT-5", "title": "content+sim: typed GroundUnitDef.barrel_slew_dps / barrel_min_deg / barrel_max_deg; BarrelSlew reads them; cross-field rules (R0 B.31 A-151)", "lane": "content+sim", "tier": "Haiku", "size_days": 0.2, "depends_on": ["GD-50"], "milestone": "M3", "acceptance": "GroundUnitDef gains var barrel_slew_dps: float = 0.0, barrel_min_deg: float = 0.0, barrel_max_deg: float = 0.0 (not req); def unit tests assert siege_crawler 10 / 0 / 45 and harvester 0 / 0 / 0; ContentSet.warnings no longer lists the three keys; BarrelSlew reads the typed fields and grep of src/sim/** finds no raw.get for them; validate_content rejects barrel_min_deg > barrel_max_deg and any barrel key on an entry whose weapon is null, one negative case each in test_validate_content.py; the barrel suites are unchanged and green (no behaviour change)", "docs": ["docs/reviews/R0-amendments-25.md", "R0 B.1"]},
    {"id": "UX-48", "title": "input: ground mapper for the three input classes (drive, steer, BRAKE, FIRE1, barrel holds) so GROUND mode stops sampling the flight mappers (06 s3.2, R0 B.31 A-154)", "lane": "input", "tier": "Sonnet", "size_days": 1.5, "depends_on": ["GD-50"], "milestone": "M3", "acceptance": "In Mode.GROUND InputRouter samples a ground mapper for the active input class, not the flight mapper. Gamepad: LS Y forward -> thrust, LS Y back -> BRAKE, LS X -> yaw, RT -> FIRE1, RB / LB held -> pitch +1 / -1. KBM: W -> thrust, S -> BRAKE, A / D -> yaw, LMB -> FIRE1, E / Q held -> pitch +1 / -1; mouse motion never reaches PilotInput. Touch: stick Y / X -> drive / steer, ux_fire1 -> FIRE1, ux_barrel_up / ux_barrel_down -> pitch +1 / -1. Always: roll 0; no BOOST, FLIP, DOCK or FIRE2 bits; invert_pitch not applied; yaw sign as sim/ground (+ = left); right stick and mouse are emitted as the camera orbit intent the PR names (06 s3.2). barrel_up / barrel_down (and ground steer actions if the PR needs them) are remappable actions in content/ui/remap.json, and the default set raises no BindingStore conflict flag (the PR states the per-mode conflict rule). Unit tests per class through the existing poller seams, including 'stick Y and mouse Y leave pitch at 0 in GROUND' and 'FLIGHT, TURRET and PEEK output is unchanged'; RELEASE and the menu / peek / ping intents still work in GROUND; input/MODULE.md current", "docs": ["docs/reviews/R0-amendments-25.md", "06 s3.2", "06 s2"]},
    {"id": "UX-49", "title": "ui/hud: barrel elevation readout for a possessed ground unit with a barrel (R0 B.31 A-155)", "lane": "ui/hud", "tier": "Sonnet", "size_days": 0.5, "depends_on": ["GD-50", "UX-16"], "milestone": "M3", "acceptance": "While the possessed entity is a ground unit whose def has a barrel, the Chase HUD shows the elevation in whole degrees from SimView.barrel_elevation with the def's min and max as end marks; nothing is shown for a unit without a barrel, and nothing while the view reports the field as not received (the existing HUD handling of unknown fields, 06 s6.1); HudMath unit test for the conversion and clamping; windowed screenshot in the PR; no new SimView function (a predicted-impact marker is a contract question, not this task)", "docs": ["docs/reviews/R0-amendments-25.md", "06 s3.2", "06 s6.1"]},
    {"id": "ART-40", "title": "presentation: the view of a ground unit with a barrel pitches its Barrel node by SimView.barrel_elevation (R0 B.31 A-155)", "lane": "presentation", "tier": "Sonnet", "size_days": 0.5, "depends_on": ["GD-50", "ART-08", "TA-26"], "milestone": "M3", "acceptance": "For an entity whose def has a barrel, EntityViewPool rotates the mesh's Barrel node (07 s4.2 'Parts that move') about its local X by SimView.barrel_elevation each synced frame; 0.0 (level) when the view has not received the value; a mesh without a Barrel node is skipped without an error; no per-frame allocation; unit test with a fixture scene (0, 20 and 45 deg); perf note against the 800-view sync row; windowed screenshot of a raised Crawler barrel", "docs": ["docs/reviews/R0-amendments-25.md", "07 s4.2"]}
  ],
  "acceptance_append": {
    "GD-50": "; R0 B.31 A-152: the base SimView.barrel_elevation returns 0.0 (no NAN), 'barrel_elevation' is in NetUnknown.NEVER and the net_sim_view_factory exemption is dropped if the clause passes; A-151 / A-153 cited in the Crawler _doc, the schema $comments and the MODULE.md lines",
    "AI-18b": "; R0 B.31 A-153 / A-155: the brain reads SimView.barrel_elevation and writes pitch = clamp((e* - e) / (barrel rate x dt), -1, 1) through CommandSink.drive; SiegeAim.loft solves from the sim muzzle by calling the static BarrelSlew.muzzle_dir / muzzle_up (no second copy of the formula), so the 1.7-2.1 m muzzle bias is gone; the PR reports the highest elevation at which a siege shell still reaches the ground inside lifetime_s on flat ground and on cradle, and what happens above it, for GD-34 (A-151)",
    "ART-08": "; the Siege Crawler's barrel is a separate object named Barrel, modelled level (elevation 0), pivoting about its local X at the trunnion (07 s4.2 'Parts that move', R0 B.31 A-155)",
    "UX-06": "; in GROUND mode for a unit with a barrel the thrust slider is replaced by two hold buttons BARREL UP / BARREL DOWN that drive ux_barrel_up / ux_barrel_down (R0 B.31 A-154); they count against the 06 s4.3 right-half budget"
  },
  "depends_on_append": {
    "UX-39": ["UX-48"]
  },
  "note": {
    "GD-50": "Ruling R0-amendments-25 (B.31 A-151..A-155): the acceptance clause 'Architect confirms whether an R0 row is needed' is answered (rows A-151, A-152, A-153). The GD-50 author may add the one string to godot/src/net/client/net_unknown.gd (NEVER) under A-152.",
    "UX-39": "R0 B.31 A-154: match_controller enters InputRouter Mode.GROUND only with UX-48's ground mapper; never on the flight mappers."
  }
}
```

## Not ruled here

- **TURRET mode has the same gap.** It also samples the flight mappers, while 06 s3.2 gives a tower drag / RS / mouse aim. Nobody asked and no player reaches it before UX-39. The orchestrator may widen UX-48 to both modes (about +0.5 d) or file a twin; either needs no Architect.
- **`barrel_max_deg` 45 against the 12 s shell lifetime.** Arithmetic only (A-151). AI-18b measures, GD-34 decides.
- **A predicted-impact marker for a possessed Crawler.** It would be a new `SimView` function or a `ui` reference to `Ballistics`; the first task that wants it raises it.
- **The kinematics row over its 3.0 ms budget on the dev laptop** (PR #182 perf note; it was over on `main` before this PR, and `BarrelSlew.step` adds 56 / 86 us p50 / p95). Not a GD-50 matter; it belongs to the next PM re-baseline on the pinned runner.

## Decisions for the owner

1. A-154, barrel controls: RB / LB on a gamepad, E / Q on KBM, two hold buttons on touch; stick Y and mouse Y never move the barrel. Alternative: bind the barrel to mouse Y / right-stick Y and give up the ground camera orbit on that axis (changes 06 s3.2). Recommendation: the digital holds. Default if silent: the digital holds.
2. A-152, no NAN: `barrel_elevation` returns 0.0 with `field_unknown` true when not received; PR #182 changes three small places before merge. Alternative: merge with NAN and fix it in NET-61 (leaves a second "no data" convention in `sim/MODULE.md` until M4). Recommendation: change now. Default: change now.
3. A-151, Siege Crawler 10 deg/s, 0-45 deg as tuning anchors. Alternative: cap `barrel_max_deg` near 20 now, on arithmetic alone. Recommendation: keep 45 until AI-18b measures. Default: 10 / 0 / 45.
4. The backlog patch: NET-61 (Opus, 1.0 d, M4), CONTENT-5 (Haiku, 0.2 d, M3), UX-48 (Sonnet, 1.5 d, M3), UX-49 (Sonnet, 0.5 d, M3), ART-40 (Sonnet, 0.5 d, M3); UX-39 depends on UX-48. Total 3.7 agent-days, 2.7 of them in M3. Recommendation: as written. Default: as written.
5. TURRET mode mapper: widen UX-48 or leave it for a later task. Recommendation: widen UX-48 to 2.0 d. Default: UX-48 stays GROUND only.
