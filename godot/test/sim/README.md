# Scenario layer (TA-33, 01 ADR-11)

`scenarios/*.json` are data-driven sim matches: scripted commands by tick, expected events, queries on the world.
`test_scenarios.gd` loads every file and runs it through `scenario_runner.gd` headless (whole directory < 60 s). The
format is `tools/schemas/sim_scenario.schema.json`; `python tools/validate_content.py` checks every file.

- `id` equals the file stem; `refs` name the doc ids the expected values come from (02 s6.3, 05 C6, ...).
- `status: planned` + `planned_reason`: the rule is not implemented yet. The runner counts it and does not run it.
  When the feature lands, flip it to `active` and fill in the script.
- `world.kind`: `standard` (WorldTestKit: players 0 and 2 team 0, 1 team 1), `solo_kit` (EconomyTestKit: players 0 and 1,
  player 0 start kit), `combat` (CombatTestKit: five players). Optional `seed`, `core_exposure_s`, `hard_end_s`, `unit_cap`.
- `script` steps run at tick `at`, queued before step `at`, so their events carry tick `at`. `do`: `spawn` (name it with
  `as`; `pin` holds it still), `possess`, `release`, `build` (`west_m` of the Core), `produce` (`factory` = a name from
  `bind_structures`), `kill`, `remove_player`, `hold` (buttons driven every tick). `expect` is the CommandResult.Code key
  (default ACCEPTED); `expect_reject` the Build.Reject key.
- `events` is the exact ordered list of the `event_filter` kinds; only the listed fields are compared. `checks` run after
  step `at`: `possessor`, `alive`, `hp01`, `ore`, `queue_size`, `ship_count`, `structure_count`, `event_count`, with
  `op` (eq default, ge, le, gt, lt, approx + `tol`).
- Every active scenario is also run with its first expectation corrupted and must then report a mismatch.
