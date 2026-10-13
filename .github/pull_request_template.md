<!-- PR title: `<ID>: <title>` exactly as in docs/backlog/backlog.json. Commit subjects also start with the id (CI lint: tools/lint_commits.py). -->

**Task:** <!-- ID, e.g. TA-03 -->
**Lane / tier:** <!-- lane from backlog.json, tier Fable/Opus/Sonnet/Haiku -->

## Acceptance -> evidence

<!-- One row per acceptance line of the task. Evidence = named test, REPORT path, or command output. -->

| Acceptance (from backlog.json) | Evidence (test name, REPORT path, or command output) |
|---|---|
| | |

## Definition of done (CLAUDE.md, "Picking up a task" step 5)

- [ ] Acceptance demonstrated by the named tests or a REPORT (table above)
- [ ] `python tools/check_deps.py` green (D1-D10)
- [ ] `python tools/validate_content.py` green
- [ ] `godot --headless --path godot -s tools/validate_scenes.gd` green
- [ ] `python tools/gen_module_api.py --check` green
- [ ] Zero warnings in the Godot run
- [ ] Every public symbol added or changed has a gdUnit4 test (ADR-11)
- [ ] `godot/src/<lane>/MODULE.md` is current (public API and invariants)
- [ ] Perf note for `sim/`, `net/`, `presentation/` changes (`perf_tick.gd` delta, cited in the PR)
- [ ] Screenshot attached for `presentation/` or `ui/` changes (see below)
- [ ] Only the lane's own paths are touched (`godot/src/<lane>/**`, `godot/test/**/<lane>/**`, its `MODULE.md`); anything else is a `needs <lane>:` comment or a follow-up task
- [ ] No new dependency, autoload, or contract edit without the Architect and owner (or a `BLOCKED:` note below)

## Screenshot rule

PRs that touch `godot/src/presentation/` or `godot/src/ui/` **must attach a local screenshot** of the change (windowed build). PRs without one are not reviewable.

Screenshot: <!-- drag the PNG here, or write "not applicable" -->

## Notes for reviewers

<!-- Contract questions, deviations, or `BLOCKED: <reason>` if the acceptance cannot be met inside the contract. -->
