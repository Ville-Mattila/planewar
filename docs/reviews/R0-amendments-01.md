# R0 amendments 01: CONTRACT-0 questions Q1-Q8

| Field | Value |
|---|---|
| **Register id** | R0 Part B, new subsection B.8 (append-only). No ADR is amended, so no `docs/adr/ADR-NN-amendment-*.md` and no line in 01's amendment log (10 s4.2 requires one only when an ADR changes). |
| **Status** | Decided by the Architect; A-3's OWNER question was ruled by the owner on 2026-10-13 (no modifier for ground guns). |
| **Date** | 2026-10-10 |
| **Raised by** | CONTRACT-0 (PR #13, "QUESTIONS" section), Opus sim+tools engineer |
| **Decided by** | Architect (Fable), per 10 s4.1 "Change" row; the owner rules on the OWNER item |
| **Size** (10 s4.1) | Appends: three optional def fields / enum values, two `ContentDB` accessors, four type specifications. No signature changes, no reorders, no deletes, no new `deps.json` edge. |

Reading order for a lane engineer: the B.8 table in `docs/reviews/R0-resolution-register.md` is the binding text; this file is the why. 02 s4.1, s7, s14, 03 s5.2, s15.3 and 05 s7.7 were patched in the same PR so that no doc contradicts B.8.

## A-1 (Q1) `bomb` is both a weapon id and a projectile id

**Context.** 02 s4.1 names the Bomber's weapon `bomb` and 02 s4.2 names its projectile `bomb`; R0 B.1 repeats both. 03 s15.3 declared `ContentDB.def_index(id: StringName) -> int` as a single global lookup over the N2 ranges, which has no answer for `bomb`. 02 s1.2 already shows per-kind accessors (`weapon(id)`, `projectile(id)`), and 03 s3.3 stores projectiles by local `projectile_def` / `weapon_def` indices, never by a global id.

**Decision.** Entity defs (`ships`, `ground_units`, `structures`, `towers`) share one id namespace; `def_index(id)` resolves exactly that namespace. Weapons and projectiles are per-file namespaces with `weapon_index(id)` and `projectile_index(id)` appended to `ContentDB` (03 s15.3). Both `bomb` ids stay. The def_id ranges of N2 are unchanged, so `kind_of` stays pure arithmetic.

**Alternatives.** Rename the projectile (`bomb_shell`): touches 02 s2.3, s4.1, s4.2, R0 B.1's canonical rows and every future `ships.json`, for a problem that only exists in one accessor's signature. Make `def_index` take a kind argument: a signature change to a frozen API where an append does the same job.

**Consequences.** `validate_content.py` already enforces this namespace rule; its comment now cites A-1. The sim resolves `WeaponDef.projectile` through `projectile_index`, never `def_index` (noted in `sim/MODULE.md` Open items). TA-09 implements the two accessors and tests them in `test_def_ranges.gd`.

## A-2 (Q2) `siege_gun` minimum range has no field

**Context.** 02 s4.1 and R0 B.1 give `siege_gun` "1,200 (min 300)" but the B.1 weapon field list has no minimum-range field; the canonical fixture could not carry the 300 m.

**Decision.** Append `range_min_m` (number, optional, default 0, `< range_m`) to the `weapons.json` field list and schema; `siege_gun` sets 300. `validate_content.py` checks the ordering.

**Alternatives.** Encode the minimum in `autopilots.json` for `ap_crawler` only: the human-possessed Crawler would then have no minimum range, contradicting 02 s3 ("300-1,200 m").

**Consequences.** A new optional field with a default (10 s4.1 "Append"). GD-01 keeps the bound; `Combat` (TA-14/TA-18) refuses fire inside `range_min_m`; 06's range ring draws both radii.

## A-3 (Q3) `siege_gun` is ground-mounted but `weapon_mount` is `ship | tower`

**Context.** B.1's `weapon_mount` enum has two values; `siege_gun` is carried by the Siege Crawler, a ground unit. The fixture used `ship`, which would make Foundry's `select {weapon_mount: "ship"}` x0.85 damage modifier apply to it, something 02 s7 never says.

**Decision.** Append `ground` to the `weapon_mount` enum (weapons schema and doctrine selector; enums are append-only). `siege_gun` is `ground`. Foundry's modifier keeps selecting `ship` only, which is what 02 s7's text ("ship-mounted weapons") says.

**OWNER.** Should Foundry's x0.85 also cover `ground`, making the Foundry Crawler shell 102 instead of 120? **Owner ruling 2026-10-13: no** (Foundry's x0.85 stays ship-mounted only; the Crawler shell stays 120). The Crawler is the one `core` siege unit (O-4) and BAL-14 already polices its share of structure damage; Foundry already discounts its cost by 15 %; and the literal reading of 02 s7 needs no data change. Default applied: no.

**Alternatives.** Keep two values and call the Crawler's gun `ship`: wrong in the doctrine resolver and in 06's loadout UI. Model the Crawler as a tower: it moves.

**Consequences.** Bulwark's `tower` range modifier is unaffected. The doctrine schema's selector enum mirrors the weapon enum; `test_a3_weapon_mount_enum_appended_in_both_schemas` pins both.

## A-4 (Q4) Typing of the 02 s14 / s15 prose cells; 2v2 rating weight

**Context.** 02 s14 and s15 are prose tables ("2-4", "LOBBY 20 s blind", "not before 6:00", "rarely"). CONTRACT-0 typed them and asked 02 to confirm; B.6's "weight 0.5" for bot-filled 2v2 matches had no field.

**Decision.** CONTRACT-0's typing is canonical (full list in B.8 A-4 and now in 02 s14 "Field typing"). `modes.json` gains the optional `fill_rating_weight` (0-1): `pvp_1v1` 0 (B.6 "no MMR change"), `pvp_2v2` 0.5, omitted = 1.0 (used by `pvp_team`, for which B.6 states no weight). `null` means "per mission / host / per slot" wherever B.6 says so.

**Alternatives.** Free-text cells: unusable by 04's matchmaker and 06's lobby without a parser per cell.

**Consequences.** GD-05 authors the files to this typing. 04's rating update multiplies by `fill_rating_weight` when a bot filled a slot (NET lane reads `modes.json`; no protocol change).

## A-5 (Q5) `bot_profiles` rosters: per phase (B.1) vs per phase per doctrine (05 s7.7)

**Context.** R0 B.1 gives `rosters {phase: {class: n}}`; 05 s7.7 says "per phase per doctrine", one nesting level more.

**Decision.** B.1 stands (Architect rule: resolve contradictions by citing R0). 05 s7.7 is corrected; doctrine-specific composition is what the opening books (`books[]`, 05 s7.3) already provide, and the reactive production manager works from one roster per tier.

**Alternatives.** Add an optional `rosters_by_doctrine` override: widens the contract for a need 05 can meet with books; AI-26 may request it later with soak evidence.

**Consequences.** No schema change. AI-26 implements against the B.1 shape.

## A-6 (Q6) Adjutant profiles have no promise

**Context.** B.1 allows `promise: tier id or null`; 05 s8 gives every Adjutant profile "Normal cadence, 20 commands/min", which matches no tier promise (Normal is 40/min). CONTRACT-0 skipped the C2-13 cross-check for them.

**Decision.** `promise` is `null` for `adjutant_*` and non-null for the four tiers. The validator mirrors a tier profile against its promise (think, reaction, rate) and an Adjutant profile against the `normal` promise's think and reaction only; `max_commands_per_min` (20) is 05's own data, verified by SC-45-class soaks.

**Alternatives.** A fifth promise `adjutant`: promises are 02's player-facing tier table and the Adjutant is not a tier. Hardcoding 20 in the validator: a sim-affecting constant outside JSON (ADR-09).

**Consequences.** Three new negative fixtures (`tier_profile_without_promise`, `adjutant_profile_with_promise`, `adjutant_cadence_not_normal`); AI-28 / AI-29 inherit the rule.

## A-7 (Q7) `ShipState`: inner class (B.5) or own `class_name` (03 s15.4)

**Decision.** Own file `sim/ship_state.gd` with `class_name ShipState`, as 03 s15.4 and ADR-14 (one public class per file) require; B.5's inner-class notation is shorthand for the same fields. 03 s5.2 is rewritten to match.

**Consequences.** None for consumers: `net` names `ShipState` through `Kinematics` already; D7 and `gen_module_api --check` see one class per file.

## A-8 (Q8) `ProjectileState`, `CapsDef`, `TeamStateView`, `PlayerStateView`

**Context.** All four appear in B.5 / 03 s15.4 signatures with no field list. Sources used: 03 s5.4 (projectile step), 03 s3.2 side tables `TeamState` and `PlayerState`, 03 s3.3, `match_rules.json` caps (B.1, B.7), 04 `TEAM_STATE` 0x85, `TEAM_DETAIL` 0x92 players block and `PLAYER_STATUS` 0x8D, 02 s12.1 (elimination), 05 s8 (`SET_ADJUTANT`).

**Decision.** Fields as listed in B.8 A-8 and `sim/MODULE.md`:

- `ProjectileState` carries only `p`, `v`: `step_projectile` is the pure motion step of 03 s5.4; terrain and entity hits are collision's (step 8), `ttl` and guided re-aim are `ProjectileStore` / `ProjectileMotion`'s. One reused scratch per `ProjectileMotion`, the same exception rule as `ShipState`.
- `CapsDef` is a content type (owner 03 s15.3) with the five `match_rules.json` caps fields plus `id`, so `MatchRules.caps` and `ContentDB.caps(profile)` share it.
- `TeamStateView` mirrors `TeamState` and the `TEAM_STATE` wire fields one to one (ints for ore/ice, floats for power, caps per player, member slots, `eliminated`, flag bits in 0x85 order), so `NetSimView` fills it from one message and the contract test compares field by field. Per-player counts are not duplicated on the team view; they live on `PlayerStateView`.
- `PlayerStateView` mirrors `PlayerState` plus what `TEAM_DETAIL` players and `PLAYER_STATUS` replicate; `early_spend_left_ore` uses 04's -1 convention for "lock over or not own team". Scores stay in `player_score(slot)`.
- Both views carry `unknown` (04 s3.7 replication map) and are reused per slot (S3).

**Alternatives.** Returning `Dictionary`s: `Variant` boxing on a 2 Hz read path and no contract test surface. Putting `unit_count` on both views: two sources for one number.

**Consequences.** TA-18 implements the views in `LocalSimView`; NET-39 fills them in `NetSimView`; `godot/test/contract/test_sim_view_contract.gd` compares them. `sim/MODULE.md` grows from 265 to 287 lines (limit 300).

## Register and impact

| Item | Entry |
|---|---|
| **Affected MODULE.md files** | `godot/src/sim/MODULE.md` (Public API: `ProjectileState`, `TeamStateView`, `PlayerStateView` appended; `ShipState` file noted; Open items rewritten). `godot/src/content/MODULE.md` (not yet on disk; 03 s15.3 draft patched: `weapon_index`, `projectile_index`, `CapsDef`, N2). |
| **Affected tasks** | TA-09 (two accessors, `CapsDef`), GD-01 (keeps `range_min_m`, `weapon_mount` ground), GD-05 (`fill_rating_weight`, typing), TA-14 (`ProjectileState`, `range_min_m` in Combat), TA-18 (views in `LocalSimView`), NET-39 (views in `NetSimView`), AI-26 (rosters shape), AI-28 / AI-29 (promise rule). No re-tier, no new dependency. |
| **Affected docs** | R0 Part B.8 (new, append-only); 02 s4.1, s7, s14, revision log; 03 s5.2, s15.3, revision log; 05 s7.7, revision log. 01 unchanged (no ADR touched). |
| **Contract tests to update first** | `tools/tests/test_validate_content.py` (`Amendments01`, 8 new negative fixtures) in this PR; `godot/test/unit/content/test_def_ranges.gd` (TA-09) and `godot/test/contract/test_sim_view_contract.gd` (TA-18 / NET-39) when those tasks open. |
| **Gate** | `python tools/validate_content.py`, `python -m unittest discover -s tools/tests`, `python tools/check_deps.py`, `python tools/extract_doc_examples.py --check` green in this PR; `gen_module_api.py --check` when TA-27 lands. |

## Sign-off

| Role | Name | Date | Verdict |
|---|---|---|---|
| Architect | Fable 5.1 | 2026-10-10 | A-1..A-8 decided; A-3 default applied pending the owner |
| Owner | Ville Mattila | 2026-10-13 | A-3: no; Foundry's x0.85 does not apply to `ground` |
