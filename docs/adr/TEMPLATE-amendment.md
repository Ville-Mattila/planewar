# ADR-NN amendment: <short title>

Copy this file to `docs/adr/NN-<slug>.md` (or to `docs/adr/ADR-NN-amendment-<slug>.md` when it amends an existing ADR in 01 s7). Fields follow the ADR layout of `docs/01-vision-and-core-decisions.md` section 7 (Decision / Alternatives / Rationale / Consequences), with the register and impact fields added. Delete this paragraph and every `<...>` placeholder before committing.

| Field | Value |
|---|---|
| **Register id** | `ADR-NN` (the ADR being amended, or the next free number). Add the amendment to the change log in `docs/01` when accepted. |
| **Amendment id** | `ADR-NN-A<k>` (k counts amendments to that ADR, starting at 1) |
| **Status** | Proposed / Accepted / Superseded by ADR-MM |
| **Date** | YYYY-MM-DD |
| **Raised by** | role or agent, and the task id that found the conflict |
| **Decided by** | owner (ADR changes are owner decisions; the Architect drafts) |

## Context

What is true today, and why the current decision no longer fits. Cite the doc section, the task id and the measurement or spike that exposed the conflict (for example `S-SIM-1 (TA-22)`, `R2 s4.2`). State the constraint that forces a change. No solution yet.

## Decision

The new rule, as one or more bold, binding sentences. Name the exact values, enumerations, def fields or module boundaries that change. Anything not named here stays as the parent ADR says.

## Alternatives

- **<option>.** Why it was rejected.
- **<option>.** Why it was rejected.

## Rationale

Why this option beats the alternatives under the project's pillars and budgets (`docs/01` sections 8 and 9). Cite evidence.

## Consequences

- What becomes easier, and what becomes harder or riskier.
- Budgets, tolerances or milestone dates that move, with the new numbers.
- Migration steps for code, data and docs that already exist.
- Contract changes: append-only enumerations keep their frozen ordinals (`CLAUDE.md`, "Binding rules").

## Register and impact

| Item | Entry |
|---|---|
| **Affected MODULE.md files** | `godot/src/<module>/MODULE.md` (one line per file: what changes in Public API or Invariants) |
| **Affected tasks** | task ids from `docs/backlog/backlog.json`, with the change to each (new dependency, changed acceptance, re-tier) |
| **Affected docs** | sections of `docs/0x-*.md` and `docs/reviews/R0-resolution-register.md` Part B that must be patched in their next revision |
| **Contract tests to update first** | test paths under `godot/test/<layer>/<lane>/` (CLAUDE.md: contract tests change first, in the same PR) |
| **Gate** | `tools/gen_module_api.py --check` green after the MODULE.md edits |

## Sign-off

| Role | Name | Date | Verdict |
|---|---|---|---|
| Architect | | | |
| Owner | | | |
