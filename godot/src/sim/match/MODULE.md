# sim/match - MODULE.md

Contract for `godot/src/sim/match/**`: the match rules of 02 s12.1 that decide who loses and who wins (GD-20; R0 C3-19,
B.11 A-61, B.20 A-106). R0 B.9 A-21 split: `SimWorld`, `MatchRules` and every type other lanes may name stay in
`sim/MODULE.md`; this subsystem holds the lane-internal `MatchJudge`. A change to "Public API" or "Invariants" is a
contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Commander elimination on Core loss, the 60 s self-destruct of an eliminated player's structures, team defeat (`ControlMachine.release_team`), the surrender vote, the hard end by structure value and MATCH_END. The Exposure clock event moves here from `SimWorld`. Not here: shield expiry (`ShieldDomes`, GD-10), the Core bomb factor (`Blast`), Ore Field regen stop (`Harvest`, GD-12): they read `MatchRules.phase`. |
| Lane owner tier | Sonnet against this file; Opus reviews |
| May depend on | `core`, `content`, `sim` (inside the sim module) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads (D2, D3) |
| Autoloads used | None |
| Status | implemented (GD-20); `SimSerialize.FORMAT` 17 (the judge state rides in `MatchState`, the clock section) |

## Public API

```gdscript
class_name MatchJudge extends RefCounted                                     # one per SimWorld; steps 1 (vote), 9 (self-destruct) and 10 (the rest)
enum EndReason { CORES_DESTROYED, HARD_END_VALUE, SURRENDER }                # MATCH_END extra[0]; same ordinals as Protocol.MatchEndReason 0-2
func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, rules: MatchRules, events: SimEvents, applier: CommandApplier, control: ControlMachine, score: ScoreKeeper, state: MatchState) -> void
func vote(player: int, tick: int) -> void                                    # step 1: SURRENDER from `player`; ignored before the minimum clock, from a bot, an eliminated player or a defeated team
func step_selfdestruct(tick: int) -> void                                    # step 9, before the score pass: due structures are killed with SELF_DESTRUCT
func step(tick: int) -> void                                                 # step 10: Exposure event, elimination, team defeat, surrender, hard end, MATCH_END
func structure_value(team: int) -> float                                     # 02 s12.1: sum((cost_ore + cost_ice) * hp01) over finished structures, the Core `core_value * hp01`
func note_damage(team: int, amount: float) -> void                          # DamageSink: damage dealt to a finished enemy structure by `team` (the tie-break)
func structure_damage(team: int) -> float
func winner() -> int                                                         # team id, -1 draw, -2 not ended (02 s12.1 sketch)
func end_reason() -> int                                                     # EndReason once ended, else -1
func selfdestruct_tick(player: int) -> int                                   # tick the eliminated player's structures are due, -1 when not eliminated
```

## Invariants

- M1 (elimination): a player that owned a Core (`had_core`) and owns none gets `PlayerTable.eliminated = 1`, one
  `PLAYER_ELIMINATED` (a = slot, b = -1 unknown killer team, team = its team) and `selfdestruct_tick = tick +
  round(eliminated_selfdestruct_s * tick_hz)`. A player that never owned a Core is never eliminated by this rule. Its
  units stay, keep their owner and are ordered by teammates; BUILD / PRODUCE / queue edits are the validator's (`eliminated`).
- M2 (self-destruct): at `selfdestruct_tick` every structure and site the player still owns is killed in step 9 with
  `DEATH` cause `SELF_DESTRUCT` (3), so Salvage leaves the normal wrecks (GD-19); once, then the deadline is cleared.
- M3 (team defeat): a team whose members own no Core is defeated: `ControlMachine.release_team(team)` (C16, A-61), its
  members eliminated. When at most one team with active players is left the match ends at once: MATCH_END (a = winner
  team, or -1 when none is left) with reason CORES_DESTROYED (0). No Core was ever seen: no defeat (test worlds).
- M4 (surrender): a vote counts from `surrender_min_s` of match clock (`surrender_min_s_1v1` when exactly two teams of one
  active player each); unanimous among the team's connected, non-eliminated human members (bots never vote; the validator
  answers a bot SURRENDER with `REJECTED_NO_RIGHTS`) defeats the team as in M3 with reason SURRENDER (2). Votes survive S4.
- M5 (Exposure): `CORE_EXPOSURE` fires once at `core_exposure_s` (the first tick the phase is not PLAYING).
- M6 (hard end): at `hard_end_s` the surviving team with the higher `structure_value` wins; equal: the higher
  `structure_damage`; equal: draw (-1). Reason HARD_END_VALUE (1). Every possession is released (C16, reason MATCH).
- M7: after MATCH_END nothing changes (`step` returns at once; commands answer REJECTED_PHASE).
- M8 (S4): the state is in `MatchState` (`had_core`, `selfdestruct`, `votes`, `defeated`, `structure_damage`, `end_reason`).
- M9 (shield): `TeamStateView.CORE_SHIELD_UP` is set from tick 0 until `core_shield_until_s` (GD-10 owns it; tested here).

## Performance budget

Not a hot path: step 10 scans `store.structures` once (<= 480 entries, no allocation, scratch arrays are members) and
8-slot tables; step 9 reads a `PackedInt32Array` of 8. Well under 0.05 ms at 4v4.

## Test entry points

`godot/test/unit/sim/match/test_match_flow.gd` (one test per transition of the 02 s12.1 diagram, each run with the
`pvp_1v1` and `pvp_team` timers at 1 Hz), `test_match_judge_state.gd` (structure value, S4, enum ordinals, validator).

## How to add X

- **A new end condition:** a branch in `MatchJudge.step` calling `_end(tick, winner, reason)`, a new `EndReason`
  ordinal appended (never reordered; `Protocol.MatchEndReason` mirrors it) and a test in `test_match_flow.gd`.
- **A new DEATH cause:** append to `SimEvent.DeathCause`, `sim/MODULE.md` Enumerations and R0 B.3 in the same PR.
