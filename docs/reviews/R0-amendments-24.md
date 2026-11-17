# R0 amendments 24: a capturer lands on an open objective pad; a pad serves its holder's team only; the Relay capture fields and their layout (GD-23 PR #175, four Architect questions from its Opus review)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, subsection B.30 (append-only): A-146 .. A-150 added 2026-11-17. B.21 A-109 gains one trailing pointer (a named exception, A-146); the B.1 `ships.json` and `structures.json` sentences gain one clause each (A-148). 03 s3.2 rows 31-33, 03 s6.1, 03 s6.4 and 02 s5.3 are patched in place. No ADR is amended; no enumeration, signature, `deps.json` edge, wire layout, autoload, addon or thread change; `PROTOCOL_VERSION` and `SimSerialize.FORMAT` unchanged. |
| **Status** | Decided by the Architect 2026-11-17; the OWNER items below carry their default until the owner rules. |
| **Raised by** | GD-23 (PR #175), Opus review comment 6950452145, verdict "escalate (Architect)": the PR changes the ratified ram rule (A-109) and the pad service rule on its own authority, adds required def fields, and departs from 03 s3.2 row 33. |
| **Decided by** | Architect (Fable), 10 s4.1 (a changed invariant and a required def field are Changes) and 10 s4.3 (`tools/schemas/*.schema.json`: "Architect for required fields"). |
| **Size** (10 s4.1) | Five register rows, two B.1 clauses, four in-place doc patches, two new tasks, three acceptance appends. The Architect edits no `godot/src/**`, no `godot/test/**`, no schema, no def, no `MODULE.md`. |

Reading order: the B.30 rows in `docs/reviews/R0-resolution-register.md` are the binding text; this file is the why and the author's work list.

## Two definitions (data, A-148)

- **Open pad:** a structure whose def carries `capture_s` (today: `relay_station`).
- **Capturer:** a ship whose def has `captures: true` (today: `hauler`; 02:162 "the only unit that captures the Relay Station").

Both replace inferences in the PR: `invulnerable and pads > 0 and not buildable` (the Core is already `buildable: false` with a pad, one flag away from matching) and `cargo_ice > 0` (the review's nit: any future Ice carrier would capture).

## A-146 Collision: a capturer, and nobody else, lands on an open pad it does not hold

**Evidence.** A-109 exempts own-team ships only; a neutral pad (team 255) has no own team, so before the PR every approach to a Relay Station was a `RAM` and 02 s5.3 could not happen. The PR's fix exempts every team. `Touchdown` D1 has no team test of its own (Collision is the gate: it lands whatever `C_PAD` it is given), so under the PR any enemy Dart can dock on the holder's Relay pad and occupy it. 02 s5.3 gives the pad to the holder; 02:162 names the Hauler as the only capturing unit. A-109's sentence "enemy ships ram the whole sphere at every altitude" was ratified four weeks ago on measured geometry and nothing here measures against it.

**Decision.** In `Collision._ship_structure` the pad-friendly test `team[o] == team[s]` becomes `team[o] == team[s] or (open_pad[def_id[o]] != 0 and capturer[def_id[s]] != 0)`. Everything behind that test is A-109 unchanged: DOCKED is exempt against its own `link` only (A-82 (4)); not DOCKED takes no RAM at `alt >= -(r + 0.5)` at any horizontal offset, the sphere test below the plane, and a `C_PAD` contact at offset <= `pad_radius_m`, abs(alt) <= r + 0.5.

| Ship | Open pad held by its team | Open pad, neutral or held by another team | Any other pad of another team |
|---|---|---|---|
| capturer | A-109 (own team) | **A-109 shape (A-146)** | whole sphere |
| any other ship | A-109 (own team) | whole sphere, every altitude | whole sphere |

The shape is the deck half-space and not something narrower for A-109's own reason: the Relay Station's interim sphere is 26.03 m against a 12 m pad and a 25 m hover approach. GD-42 (footprint puck) carries this exception together with A-109's.

**Not accepted.** (1) Every team above the deck (PR as built): enemy pad squatting, above. (2) A check in `Touchdown` instead of `Collision`: the ship would already be dead of the RAM. (3) A separate `relay_capture` contact kind: an enumeration append for no gain.

**`sim/MODULE.md` (300 / 300 lines).** Line 194 is rewritten in place, no line added:

```
class_name Collision extends RefCounted                                      # sim/collision.gd (TA-14), step 8 + 8b; _init(store, projectiles, spatial, terrain); by def_id, set by SimWorld: `var launch_pad: PackedByteArray` (A-87), `var open_pad: PackedByteArray`, `var capturer: PackedByteArray` (A-146); own-team pad structures never RAM a not-docked ship above the deck (A-53 widened by A-109, BUG-1), nor does an open pad a capturer of any team (A-146)
```

The long form is `sim/relay/MODULE.md` R10 and 03 s6.1 (patched here).

## A-147 Docking: a pad serves ships of its own team only; launch is ungated

**Ratified as the PR builds it, as docking invariant D14.** Same team, not same owner: 02 s5.3 says "the holder gets the pad", and a teammate's Pad already serves today (D6 queues by team). The A-119 hold runs before the gate, so a capturer leaves a pad it does not hold exactly as D13 says.

> D14 Team gate (R0 B.30 A-147; 02 s5.3). Step 10 serves a DOCKED ship only while `team[pad] == team[ship]`, tested every tick. On a pad of another team (only a capturer on an open pad gets there, A-146) the stay opened at landing stands still: no timer advances, nothing is spent, no WAITING_FOR_ICE / WAITING_FOR_ORE, no SERVICED, and `service_progress` is ZERO. The launch hold (D13) is not gated. When the pad's team becomes the ship's (the capture completes after `Docking` in the same step 10) service starts on the next tick under D7-D9, D8's bonus included. A ship never queues for a pad of another team (D6 unchanged), and D1's queue-head and occupied-pad rules apply to a capturer as written.

Two consequences, stated so nobody reports them as bugs: a capturer cannot land while the pad is occupied or the holder's queue is non-empty (those ships are inside `contest_radius_m` and would pause the capture anyway); and a docked capturer's brain gets no SERVICED, so AI-15 waits on the capture, not on service.

## A-148 Def home: `structures.json`, per def; `captures` on `ships.json`

**Decision (OWNER, default applied).** `capture_s` (number, > 0, <= 600) and `contest_radius_m` (number, > 0, <= 5000) are per-def keys of `structures.json`, next to `pad_radius_m` and `sensor_radius`; `relay_station` carries 20 and 300 (02 s5.3, C2-20). `scoring.json` `relay` keeps `capture` and `hold_per_min` only: it is the score-event table (B.1 `ScoringDef`), and a capture rule there could not differ between two objectives.

**Required how.** The two keys are required as a pair, and a def that carries them needs `pads` >= 1 and `pad_radius_m` > 0. The structures schema has no conditionals; the rule goes in `validate_content.py` beside the `launch_pad` rule (A-19 precedent) with two negative cases. No default exists: a structure without the pair is not capturable and is not an open pad. `ships.json` gains optional `captures` (boolean, default false; `hauler` true), an append.

**Name.** `contest_radius_m` stands (02 writes `contest_radius`; the `_doc` says so).

**Typed fields.** `StructureDef` / `ShipDef` are the content lane's. PR #175 reads the three keys through `raw` in `WorldDefs` with the usual `# needs content: typed field` marker (the `launch_pad` precedent); CONTENT-4 closes it.

## A-149 Field layout: 03 s3.2 row 33 as written

| Field of the Relay Station slot | Value | 03 s3.2 |
|---|---|---|
| `timer_b` | capture progress in seconds, 0 .. `capture_s` | row 33, unchanged ("structure: capture progress (Relay Station)") |
| `link` | EntityId of the capturer whose capture is running, 0 for none | row 31, clause appended (an EntityId, as the column is) |
| `timer_a` | 1.0 while the capture is paused by a contest, else 0.0 | row 32, clause appended (an open pad is pre-placed: never built, never a factory) |

**Why not the PR's layout.** Row 33 is ratified and nothing measured argues against it. `link` = team + 1 puts a non-id in a field `SimView.link(id)` hands to `ui` and `sim_ai` as an EntityId: values 1-8 read as slots 1-8 at generation 0, which can be alive. With the capturer's id in `link`, the candidate team is `team[slot(link)]` and the HUD and brains can already read who is capturing.

**Reset (R3 restated).** All three are 0 on any tick with no capturer of a non-holder team DOCKED on the pad; a docked capturer whose id differs from `link` zeroes the progress and takes `link`. "Its team changed" narrows to "its team is now the holder's" (no v1 mechanic changes a unit's team). S4 and `SimSerialize.FORMAT` are unaffected.

## A-150 The other questions

- **PR question (2), no Relay Station on any map.** Follow-up GD-50; until it lands the capture is reachable only in tests.
- **PR question (3), a `SimView` read of the progress.** `SimView.link(relay)` gives the capturer (A-149), `SimView.team(relay)` the holder, the two ALERTs the edges. A progress read is a new `SimView` function with a 04 s3.7 row for `NetSimView`; no task needs it yet. The first `ui` task that draws the bar raises it as a contract question; do not add an accessor on `RelayCapture` for other lanes.
- **Review nit, `load_plateaus` ignores `radius_m`.** Correct as built (R9). The rule radius is `economy.json` `solar_plateau_radius_m` 1,000 (02 s8.4, 02:449); the feature's `radius_m` is the recipe's terrain shape (`poles.noon_plateau_radius_m`, 600 on `s_world1_r6000`), not an economy input.

## What PR #175 changes before merge (author)

**Collision** (`collision.gd`, `sim/MODULE.md`, `test_collision.gd`)
1. Add `var capturer: PackedByteArray`; the condition of A-146; `SimWorld.load_map` sets `collision.capturer = _defs.capturer_by_def`.
2. `sim/MODULE.md` line 194: the text above, in place.
3. `godot/test/unit/sim/test_collision.gd`, added before the code:
   - `test_a_capturer_above_an_open_pad_deck_is_not_rammed` (neutral pad and enemy-held pad, hover height, offset outside `pad_radius_m`)
   - `test_a_capturer_inside_an_open_pad_volume_gets_a_pad_contact` (neutral and enemy-held)
   - `test_a_non_capturer_is_rammed_by_an_open_pad_of_another_team_at_every_altitude` (a Dart above the deck: neutral and enemy-held; no `C_PAD`)
   - `test_a_capturer_below_an_open_pad_deck_plane_is_rammed`
   - `test_a_capturer_is_rammed_by_an_enemy_pad_that_is_not_open` (a `pad` or Core def)
   `test_no_pad_contact_outside_volume_enemy_pad_or_docked` and the three A-109 tests stay green unchanged.

**Docking** (`docking.gd` as built, `sim/docking/MODULE.md`, docking suites)
4. `sim/docking/MODULE.md`: add D14 (text above); D1 "of the ship's team, or an open pad for a capturer (Collision emits no other PAD contact, A-146)"; D7 "of its own team (D14)"; Test entry points.
5. `test_service.gd`: `test_a_ship_on_a_pad_of_another_team_is_not_served_and_spends_nothing` (timers, pools, no WAITING_*, no SERVICED), `test_service_starts_when_the_pad_becomes_the_ships_team`, `test_a_teammates_pad_serves` (two owners, one team), `test_service_progress_is_zero_on_a_pad_of_another_team`.
6. `test_launch.gd`: `test_a_ship_launches_from_a_pad_of_another_team` (D13 timing unchanged).
7. `test_touchdown.gd`: `test_a_capturer_lands_on_a_neutral_open_pad_through_collision` and `..._on_an_enemy_held_open_pad_...` (a flown approach through `Collision.step` -> `C_PAD` -> `Touchdown.land` -> DOCKED, not `DockingTestKit.dock`), `test_a_non_capturer_never_lands_on_an_open_pad_of_another_team`.

**Fields** (A-148)
8. Revert `scoring.json` (`capture_s`, `contest_radius_m`, the `_doc` clause) and `scoring.schema.json`.
9. `structures.json` `relay_station`: `capture_s` 20, `contest_radius_m` 300; `_doc` cites 02 s5.3, R0 C2-20, R0 B.30 A-148 and the `contest_radius` rename. `structures.schema.json`: the two optional properties (the PR's bounds), `$comment` "required as a pair, needs pads (validate_content; R0 B.30 A-148)".
10. `ships.json` `hauler`: `captures: true`; `ships.schema.json`: optional boolean `captures`, `$comment` citing 02 s2 (02:162) and A-146.
11. `tools/validate_content.py` beside the `launch_pad` rule: both keys or neither; with them `pads` >= 1 and `pad_radius_m` > 0. `tools/tests/test_validate_content.py`: one negative case each. The canonical fixtures follow the shipped defs.
12. `WorldDefs`: `open_pad_by_def` = def has `capture_s` > 0 (delete the three-field inference); `capture_s_by_def`, `contest_radius_by_def` (PackedFloat32Array) and `capturer_by_def` (PackedByteArray), raw reads marked `# needs content: typed field`; all four in `sim/world/MODULE.md` Public API.

**RelayCapture** (`sim/relay/**`)
13. A target is any structure whose def has `capture_s` > 0 (not the id `relay_station`); the numbers come per relay from `WorldDefs`; a Hauler is `capturer_by_def`. The public `capture_s` / `contest_radius_m` vars leave the API.
14. State per A-149: progress `timer_b`, capturer id `link`, contested `timer_a`. Tests assert the fields by name, including `SimView.link(relay)` == the capturer while capturing and 0 after.
15. `sim/relay/MODULE.md`: Status row, the numbers paragraph, R1, R3, R8, R10 (cite A-146 / D14; tests in the owning suites), "How to add X"; `harvest/MODULE.md` I8 cites A-146 and D14.
16. Review nits: the kit docstring and the perf test cite R11; PR body "Contract impact: change (R0 B.30 A-146 .. A-149)".

No commit split is required (squash merge, the B.29 A-144 precedent); the tests of 3 and 5-7 are in the same PR.

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

```json
{
  "new": [
    {"id": "GD-50", "title": "sim: SimWorld.load_map spawns the map's Relay Stations (features.json relay_station entries, 02 s9.1) as finished neutral structures (R0 B.30 A-150)", "lane": "sim", "tier": "Sonnet", "size_days": 0.5, "depends_on": ["GD-23"], "milestone": "M3", "acceptance": "load_map of a map id spawns one finished structure (F_BUILDING clear, team 255, owner 255, up = the surface normal) per relay_station entry the baked features.json carries (neutral_structures entries and the 02 s9.1 relay_station resource features; the PR names the exact keys it reads and files 'needs maps:' for any map whose bake has none); a fixture map dir with one entry yields one capturable Relay Station that a Hauler lands on and captures in a SimWorld-driven test; a map with none spawns none; spawn order is the file order (deterministic), S4 round trip byte-exact; no def or schema change; sim/relay/MODULE.md responsibility row and sim/world/MODULE.md updated; perf note (load time only)", "docs": ["docs/reviews/R0-amendments-24.md", "02 s5.3", "02 s9.1", "03 s8.1"]},
    {"id": "CONTENT-4", "title": "content+sim: typed StructureDef.capture_s / contest_radius_m and ShipDef.captures; WorldDefs reads them (R0 B.30 A-148)", "lane": "content+sim", "tier": "Haiku", "size_days": 0.2, "depends_on": ["GD-23"], "milestone": "M3", "acceptance": "StructureDef gains var capture_s: float = 0.0 and contest_radius_m: float = 0.0 (not req), ShipDef gains var captures: bool = false (not req); def unit tests assert relay_station 20 / 300, hauler true and that an absent key reads 0.0 / false; WorldDefs reads the typed fields and grep of src/sim/** finds no raw.get and no 'needs content' comment for the three keys; relay, collision and docking suites unchanged and green (no behaviour change); validate_content green", "docs": ["docs/reviews/R0-amendments-24.md", "R0 B.1"]}
  ],
  "acceptance_append": {
    "GD-23": "; R0 B.30 A-146: a capturer (ships.json captures) of another team gets the A-109 deck half-space and the PAD contact on an open pad (a structure def with capture_s), every other ship rams it as A-109 says, with the five test_collision.gd cases of R0-amendments-24; A-147: docking D14 (a pad serves its own team only, launch ungated) with the test_service / test_launch / test_touchdown cases incl. one flown approach onto a neutral and an enemy-held pad; A-148: capture_s 20 / contest_radius_m 300 live on structures.json relay_station (pair rule in validate_content with negative cases), scoring.json relay unchanged from main; A-149: progress in timer_b, the capturer's EntityId in link, the contested flag in timer_a; sim/MODULE.md line 194, sim/docking, sim/world, sim/relay and harvest MODULE.md updated",
    "AI-15": "; R0 B.30 A-146 / A-147: the Hauler brain captures by landing on an open pad its team does not hold (only a def with captures: true may) and stays DOCKED until SimView.team(relay) is its own team or the order is replaced; it never waits for SERVICED on a pad of another team (D14: none comes) and aborts when the pad is occupied",
    "GD-42": "; the R0 B.30 A-146 capturer exemption on open pads is kept together with A-109's (the five A-146 cases of test_collision.gd stay green)"
  },
  "note": {
    "GD-23": "Ruling R0-amendments-24 (B.30 A-146..A-150). The GD-23 author may edit tools/schemas/structures.schema.json, ships.schema.json, structures.json, ships.json, tools/validate_content.py and tools/tests/test_validate_content.py for the three keys only (10 s4.3: fields its task adds; Architect for the pair rule)."
  }
}
```

## Not ruled here

- Where a map's Relay Station stands (02 s5.3 and 02:726 say the Noon Pole; the 03 s8.1 recipe example shows a ring feature at latitude 0). C2-20 gives 02 the Relay Station; GD-50 spawns what the bake emits and the maps lane authors it.
- Whether a second neutral objective ever exists. A-148 makes it a def, not code.

## Decisions for the owner

1. A-146: only a capturer (the Hauler) lands on an open pad it does not hold; every other ship rams it. Alternative: every team above the deck (PR as built; simpler, lets enemies squat on the holder's pad). Recommendation: capturer only. Default if silent: capturer only.
2. A-147: a pad serves its own team only (D14). Recommendation: approve. Default: applied.
3. A-148: `capture_s` / `contest_radius_m` on `structures.json` per def, required as a pair; `captures` on `ships.json`. Alternative: keep them in `scoring.json` `relay` and the `cargo_ice` proxy. Recommendation: structures and the flag. Default: structures and the flag.
4. A-149: follow 03 s3.2 row 33 (`timer_b` progress, `link` capturer id, `timer_a` contested). Alternative: amend rows 31-33 to the PR's layout. Recommendation: row 33. Default: row 33.
5. GD-50 (sim, Sonnet, 0.5 d, M3) and CONTENT-4 (content+sim, Haiku, 0.2 d, M3). Alternative for CONTENT-4: a content task and a sim task (the CONTENT-3 / GD-44 pair). Recommendation: as written. Default: as written.
