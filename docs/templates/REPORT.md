# <SPIKE-ID> REPORT: <spike name>

| | |
|---|---|
| **Task** | <backlog id, e.g. TA-30> |
| **Spike** | <S-XXX-n> (01 Appendix A; long form in the owning doc section) |
| **Branch** | `spike/<id>-<name>` at `<sha>` |
| **Author / tier** | <agent persona> / <tier> |
| **Date** | <yyyy-mm-dd> |
| **Owner gate decision** | <blank until the owner writes: PASS / PASS WITH FALLBACK <x> / FAIL -> PM decision; date> |

## 1. Scope

What was built for the spike, what was stubbed, and what was deliberately left out. Name the doc sections the scope comes from.

## 2. Harness

How to reproduce: exact commands, scene or script, devices, builds, network presets, tester protocol. Raw data lives in `docs/spikes/<id>/`.

## 3. Measurements

| Metric | Device / setup | Value | Unit | Notes |
|---|---|---|---|---|
| | | | | |

## 4. Pass / fail per criterion

Every pass criterion from 01 Appendix A and the owning doc, verbatim, with the result.

| Criterion (verbatim) | Result | Evidence |
|---|---|---|
| | PASS / FAIL | section 3 row, file, or screenshot |

## 5. Fallback taken or recommended

If any criterion failed: which fallback branch from the owning doc (09 s6 table) applies, as a data change where possible. A code-path split is never a fallback.

## 6. Plan changes requested

Backlog ids to add, re-size or re-tier, and any ADR amendment request (use `docs/adr/TEMPLATE-amendment.md`). The Architect turns these into a backlog patch at the next PM task.

## 7. Notes for humans

Anything to file upstream (a human files it; agents never do), surprises, and open questions.
