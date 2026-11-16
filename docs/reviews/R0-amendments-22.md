# R0 amendments 22: `ui` may name `TeamStateView` and `PlayerStateView` (read-only); no `SimView.core_shield_up` accessor; the `StatusMath.CORE_SHIELD_UP` mirror goes in UX-46; `DrawerContext` stays as built; `ui/MODULE.md` may split per sub-lane (PM-04, the UX-18 follow-up, and the UX-22 PR #154 Architect questions)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, subsection B.28 (append-only): A-141, A-142, A-143 added 2026-11-16. B.4 `ui` row gains two named `sim` types (A-141; `tools/deps.json`, 01 s9.2 `ui` row, 03 s12.4 D1 row patched, 01 amendment-log row 48, the A-27 / row-46 and A-111 / row-47 precedent). ADR-14's named-exception list grows (01:588 "only named exceptions may be added"); no ADR text changes, so no `docs/adr/ADR-NN-amendment-*.md` (the A-27 precedent, `R0-amendments-02.md`). No enumeration, def field, signature, wire-layout, autoload, addon or thread change; `PROTOCOL_VERSION` and `SimSerialize.FORMAT` unchanged. |
| **Status** | Decided by the Architect 2026-11-16; the OWNER items below carry their default until the owner rules. |
| **Date** | 2026-11-16 |
| **Raised by** | PM-04 (backlog; UX-18's contract question: `ui/hud/status_math.gd:6-8` mirrors `TeamStateView.CORE_SHIELD_UP` because the name is not in the `ui` allow-list). UX-22 (PR #154) "Architect: may `ui` name `PlayerStateView` / `TeamStateView` (ADR-14)? Should `ui/MODULE.md` (288/300) be split into `ui/rts/MODULE.md`?" |
| **Decided by** | Architect (Fable), 10 s4.1: a new named type in `deps.json` is "Change" (the Architect proposes, the owner approves). |
| **Size** (10 s4.1) | Two named types appended to one `deps.json` row (and its three doc mirrors), three register rows, one 10 s4 clause, 01 / 03 / 10 revision-log rows, one new task (UX-46). |

Reading order: the B.28 rows in `docs/reviews/R0-resolution-register.md` are the binding text; this file is the why. The Architect edits no `godot/src/**`, no `godot/test/**`, no `MODULE.md`.

## A-141 (PM-04) `ui` may name `TeamStateView` and `PlayerStateView`; no `SimView.core_shield_up`

**Evidence.**

1. **The same contradiction as A-111, one row down.** R0 B.5 gives `SimView` the signatures `team_state(team) -> TeamStateView` and `player_state(slot) -> PlayerStateView` (`sim/sim_view.gd:252-257`). B.4 lets `ui` name `SimView` but not the two return types. Under ADR-01's warning set (`inferred_declaration`, `untyped_declaration` are errors) a `ui` script cannot hold the value in a variable or pass it to a function, and it cannot write `TeamStateView.CORE_SHIELD_UP` at all (`tools/depscheck/rules_src.py` D1 matches by class name). UX-18 therefore copied the bit as `StatusMath.CORE_SHIELD_UP = 4` and pinned it with `test_landing_hud.gd:224`; UX-22 built `DrawerContext` as plain data filled by a host for the same reason.
2. **The fact already exists once, on both views.** `TeamStateView.flags` bit `CORE_SHIELD_UP` (4) is set by `LocalSimView.team_state` from `ShieldDomes.core_up` (GD-38, `sim/combat/MODULE.md` SH11, `test_shield_view.gd`) and travels in `TEAM_STATE.flags` (04 0x85; `Protocol.TEAM_CORE_SHIELD_UP`, `test_team_state_codec.gd:79`). A `SimView.core_shield_up(team)` accessor would be a second source of the same fact.
3. **Cost of the accessor.** One new B.5 signature = `sim/MODULE.md` (300 / 300 lines today, so a trim first, A-47), `SimView` default + `LocalSimView` + `NetSimView` overrides, a TEST-02 contract clause and a 03 s15.4 line: three lanes (sim, net, test) and two Opus reviews for one bit. The named-type form changes one `deps.json` row and no code.
4. **The accessor does not answer UX-22.** The drawer needs `PlayerStateView.commander_rights`, `early_spend_left_ore`, `TeamStateView.unit_cap` / `structure_cap` and `SPEND_LOCK_ACTIVE`. An accessor per field is how a view interface grows without bound; the value views are what B.8 A-8 built for this.
5. **Precedent and direction.** A-27 (row 46) and A-111 (row 47) appended named `sim` types for the same reason; A-111 point 4 already noted that `ui` names `OrderSpec`, a `SimView` return type, and that both views are `RefCounted` value types with no method that mutates the sim. `ui` reads `sim` public types, which 01 s9.2 already allows for nine of them; the module list and the layering direction do not change (01:990).

**Decision (OWNER, default applied as A-27 and A-111 were).** Append **`TeamStateView`, `PlayerStateView`** to `ui`'s named `sim` types in `tools/deps.json`, R0 B.4's `ui` row, 01 s9.2's `ui` row and the 03 s12.4 D1 row (all four in this PR; `check_deps.py` passes with no code change). **No `SimView.core_shield_up` accessor is added.**

**Read-only, as `Terrain` is.** `ui` reads fields and the flag constants. It never writes a field and never keeps the instance past the call that returned it: `team_state` / `player_state` return one reused instance per team / slot, refilled on every call (A-8, `team_state_view.gd:2-3`). Both may return `null` (index out of range; the `SimView` default, which `NetSimView` inherits until NET-39 implements them, A-111); `ui` treats `null` as "no data" and hides the widget, the 04 s5.6 rule for an accessor without a wire source. Nothing else is named: `TeamState`, `PlayerTable`, `ShieldDomes`, `TeamStats` stay `sim`-internal.

**Not accepted:** the accessor (points 2-4); moving the flag constants to `core` (A-111 point 3: `core` would know team economy); keeping the mirror with its pin test (a test that exists only to work around the allow-list).

**Who removes the mirror: UX-46** (below). `StatusClusterView.set_shield(team_flags: int, until_s, clock_s)` keeps its signature: an `int` of flags is a fine widget input and the host that calls it is not built yet.

## A-142 (UX-22) `DrawerContext` stays as built

`ui` may now name both views (A-141), so the reason UX-22 gave for a plain-data context is gone, but the design is still valid: a context object filled by its host is testable without a `SimView` and UX-22 is done and reviewed. It is not reopened. From now on a `ui` widget or adapter may take a `SimView` and read `team_state` / `player_state` itself, and new `ui` code does not mirror a `TeamStateView` / `PlayerStateView` constant. Whether the reference adapter in `test/unit/ui/drawer_context_kit.gd` moves into `ui/rts/` (so every host does not rewrite it) is the choice of the task that wires the drawer's host; it is lane-internal, not a contract.

UX-22's other "needs" (`SimView.production_queuer`, a construction-progress read, `LocalSimView` leaving `early_spend_left_ore` at -1 and never setting `SPEND_LOCK_ACTIVE`) are new accessors or sim defects, not naming questions; they are not ruled here (see "Not ruled here").

## A-143 (UX-22) `ui/MODULE.md` may split per sub-lane

B.9 A-21 already answers it and is not `sim`-only in effect: `gen_module_api.py` walks every nested `MODULE.md` (`tools/gen_module_api.py:430`), D10 covers them, and nested contracts exist under `net/` (six), `presentation/planet/` and `sim_ai/` (two) besides `sim/`. `ui` splits along the sub-lanes 09 s3.3 already uses (`ui/hud`, `ui/rts`): the next task in one of them that needs lines moves that sub-lane's Public API block to `godot/src/ui/<sub>/MODULE.md` from the template and leaves a one-line pointer in the parent. Signatures move verbatim; no symbol is renamed. 10 s4's definition of a contract is widened by one clause to say what the repository already does. UX-46 removes one line (288 -> 287), so the split is not forced by this ruling.

## Doc patches in this PR (Architect-owned text)

- `tools/deps.json` `ui.named_types.sim`: `+ TeamStateView, PlayerStateView` (A-141).
- 01 s9.2 `ui` row: the two types, read-only; 01 amendment log row 48 (A-141, OWNER default approve, the row-47 form).
- 03 s12.4 D1 row: `ui` list gains the two types; 03 revision-log row.
- 10 s4: nested `MODULE.md` of any module is a contract (A-143); 10 revision-log row.
- R0 register: B.4 `ui` row; new B.28 heading and rows A-141..A-143.
- Not patched here (other lanes): `godot/src/ui/hud/status_math.gd`, `godot/src/ui/MODULE.md:110`, `godot/test/unit/ui/test_landing_hud.gd:224` (UX-46).

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

```json
{
  "new": [
    {"id": "UX-46", "title": "ui/hud: remove the StatusMath.CORE_SHIELD_UP mirror; shield_visible tests TeamStateView.CORE_SHIELD_UP (R0 B.28 A-141)", "lane": "ui/hud", "tier": "Haiku", "size_days": 0.1, "depends_on": ["PM-04"], "milestone": "M3", "acceptance": "const StatusMath.CORE_SHIELD_UP and its comment deleted; StatusMath.shield_visible masks team_flags with TeamStateView.CORE_SHIELD_UP; no other signature changes (StatusClusterView.set_shield keeps team_flags: int); ui/MODULE.md drops the const line (287 lines) and gen_module_api --check is green; test_landing_hud.gd drops the mirror pin (line 224) and keeps a test that shield_visible is true with TeamStateView.CORE_SHIELD_UP set and time left, false with the bit clear or the clock past core_shield_until_s; grep finds no copy of a TeamStateView / PlayerStateView flag value under godot/src/ui/; check_deps green", "docs": ["docs/reviews/R0-amendments-22.md", "godot/src/ui/MODULE.md", "06 s6.4"]}
  ],
  "acceptance_append": {},
  "note": {
    "PM-04": "Ruling R0-amendments-22 (B.28 A-141..A-143): ui names TeamStateView / PlayerStateView read-only; no SimView.core_shield_up; mirror removed by UX-46.",
    "NET-39": "R0 B.28 A-141: until NetSimView.team_state is implemented it returns null online, so a ui widget that reads team_state hides (the Core shield timer included, once a host reads it through team_state rather than NetSimView.team_flags)."
  }
}
```

## Not ruled here

- **Online Core shield timer before NET-39 (M4).** `NetSimView.team_state` is `null` until NET-39; `NetSimView.team_flags(t)` carries the bit meanwhile (NET-17). The HUD host is not built, so nothing is broken today; the host task either reads `team_flags` on `NetSimView` until NET-39 or the timer is dark online until M4. Owner item 3.
- `SimView.production_queuer(factory, i)` and a construction-progress read (UX-22 "needs sim + net"): new B.5 signatures, each needs its own request with the wire source named; `sim/MODULE.md` is at 300 lines.
- `LocalSimView.player_state` leaves `early_spend_left_ore` at -1 and `team_state` never sets `SPEND_LOCK_ACTIVE` (UX-22 "needs sim"): a sim defect against A-8, a bug task for the orchestrator, no contract question.
- Whether `drawer_context_kit.gd`'s adapter moves into `ui/rts/` (A-142: lane-internal).

## Decisions for the owner

1. A-141: append `TeamStateView`, `PlayerStateView` (read-only) to `ui`'s named `sim` types; no `SimView.core_shield_up`. Recommendation: approve (zero code, one source of the fact, answers UX-22 too; A-27 / A-111 precedent). Default if silent: applied in this PR.
2. UX-46 (ui/hud, Haiku, 0.1 d, M3) removes the mirror. Alternative: fold it into the next `ui/hud` task. Recommendation: UX-46 now (ten lines; a standing mirror invites copies). Default: UX-46 as written.
3. Online Core shield timer before NET-39: (a) the HUD host reads `NetSimView.team_flags` until NET-39, or (b) dark online until M4, or (c) a 0.25 d net task fills `NetSimView.team_state` from `TEAM_STATE` now (without `members`, which A-111 item 2 declined once). Recommendation: (a), decided when the host task is written. Default: (a).
4. A-143: `ui` splits `MODULE.md` per sub-lane when a task needs lines. Recommendation: approve. Default: applied (10 s4 clause).
