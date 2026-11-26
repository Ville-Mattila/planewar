class_name MatchJudge extends RefCounted
## The match rules of 02 s12.1 that decide who loses and who wins (GD-20; sim/match/MODULE.md M1-M9): Commander
## elimination when a player's last Core falls, the self-destruct of an eliminated player's structures, team defeat
## (`ControlMachine.release_team`, C16), the surrender vote, the hard end by structure value, MATCH_END and the
## CORE_EXPOSURE event. State lives in `MatchState` (S4, the clock section). No Nodes, no signals, no RNG, no
## allocation on the per-tick path.

enum EndReason { CORES_DESTROYED, HARD_END_VALUE, SURRENDER }   ## MATCH_END extra[0]; Protocol.MatchEndReason 0-2

const NO_WINNER: int = -2   ## `winner()` while the match runs

var _store: EntityStore
var _players: PlayerTable
var _defs: WorldDefs
var _rules: MatchRules
var _events: SimEvents
var _applier: CommandApplier
var _control: ControlMachine
var _score: ScoreKeeper
var _state: MatchState
var _mr: MatchRulesDef
var _core_def: int = -1
var _cores: PackedInt32Array = PackedInt32Array()      # scratch: live Cores per player slot, rebuilt each step 10
var _members: PackedInt32Array = PackedInt32Array()    # scratch: active players per team
var _killer: PackedInt32Array = PackedInt32Array()     # scratch: per slot, team whose damage destroyed its Core this tick (-1 unknown)
var _fresh_defeat: bool = false
var _reason: int = EndReason.CORES_DESTROYED


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, rules: MatchRules, events: SimEvents,
		applier: CommandApplier, control: ControlMachine, score: ScoreKeeper, state: MatchState) -> void:
	_store = store
	_players = players
	_defs = defs
	_rules = rules
	_events = events
	_applier = applier
	_control = control
	_score = score
	_state = state
	_mr = defs.content.match_rules
	_core_def = defs.content.entity_index.get(&"core", -1)
	var e: int = _cores.resize(PlayerTable.SLOTS) | _members.resize(PlayerTable.TEAMS) | _killer.resize(PlayerTable.SLOTS)
	assert(e == OK)
	_killer.fill(-1)


## Step 1: a SURRENDER from `player`, counted when `check_vote` accepts it; the verdict (unanimity) is `step`'s.
func vote(player: int, tick: int) -> void:
	if check_vote(player, tick) == CommandResult.Code.ACCEPTED:
		_state.votes[player] = 1


## The verdict on a SURRENDER from `player` applied at `tick` (02 s12.1, 04 V-TEAM): REJECTED_PHASE before the minimum
## clock or after the match; REJECTED_NO_RIGHTS unless the player is a connected human of a team still in the match.
## The validator asks this at intake (applied tick = intake tick + 1) and again in step 1; `vote` counts exactly what passes.
func check_vote(player: int, tick: int) -> int:
	if _mr == null or not _players.is_active(player):
		return CommandResult.Code.REJECTED_MALFORMED
	if _state.ended() or tick < _ticks(_mr.surrender_min_s_1v1 if _one_v_one() else _mr.surrender_min_s):
		return CommandResult.Code.REJECTED_PHASE
	var t: int = _players.team[player]
	if _players.kind[player] != PlayerTable.KIND_HUMAN or _players.connected[player] == 0 or t < 0 or t >= PlayerTable.TEAMS \
			or _state.defeated[t] != 0:
		return CommandResult.Code.REJECTED_NO_RIGHTS
	return CommandResult.Code.ACCEPTED


## Step 9, before the score pass: the structures and sites of every player whose deadline came die with SELF_DESTRUCT
## (Salvage leaves the normal wrecks). Once per player.
func step_selfdestruct(tick: int) -> void:
	if _state.ended():
		return
	_note_core_killers()
	for p: int in PlayerTable.SLOTS:
		var due: int = _state.selfdestruct[p]
		if due < 0 or tick < due:
			continue
		_state.selfdestruct[p] = -1
		for s: int in _store.structures:
			if _store.owner[s] == p:
				_store.attacker[s] = 0                       # nobody is credited with a self-destruct
				_applier.kill_for(s, SimEvent.DeathCause.SELF_DESTRUCT)


# M1: the Cores dying this tick (still in the store) name the team of their last attacker for PLAYER_ELIMINATED.
func _note_core_killers() -> void:
	_killer.fill(-1)
	for s: int in _applier.dying:
		if _store.def_id[s] == _core_def and _store.owner[s] < PlayerTable.SLOTS:
			_killer[_store.owner[s]] = shooter_team(_store.attacker[s])


## Step 10 (after the economy): the Exposure event, elimination, team defeat, surrender, then the hard end.
func step(tick: int) -> void:
	if _state.ended():
		return
	var ph: MatchRules.Phase = _rules.phase(tick)
	if ph != MatchRules.Phase.PLAYING and _state.exposure_tick < 0:
		_state.exposure_tick = tick
		var _e: SimEvent = _events.emit(SimEvent.Kind.CORE_EXPOSURE, 0, 0, Vector3.ZERO, _clock(tick), -1)
	_fresh_defeat = false
	_scan_cores()
	_eliminate_lost_cores(tick)
	_defeat_lost_teams(tick)
	_count_surrenders(tick)
	if _fresh_defeat:
		var left: int = _teams_left()
		if left != -1 or _alive_teams() == 0:
			_end(tick, left, _reason)
			return
	if ph == MatchRules.Phase.ENDED:
		_end(tick, _hard_end_winner(), EndReason.HARD_END_VALUE)


## 02 s12.1: `sum((cost_ore + cost_ice) * hp01)` over the finished structures of `team`; the Core counts `core_value * hp01`.
func structure_value(team: int) -> float:
	var v: float = 0.0
	for s: int in _store.structures:
		if _store.team[s] != team or (_store.flags[s] & EntityStore.F_BUILDING) != 0:
			continue
		var o: int = _store.owner[s]
		var base: float = 0.0
		if _store.def_id[s] == _core_def and _mr != null:
			base = float(_mr.core_value)
		else:
			var sd: StructureDef = _defs.resolved(o).structure(_store.def_id[s])
			base = float(sd.cost_ore + sd.cost_ice) if sd != null else 0.0
		var full: float = _defs.hp_max(o, _store.def_id[s])
		v += base * clampf(_store.hp[s] / full, 0.0, 1.0) if full > 0.0 else 0.0
	return v


## The team of entity `id`, alive or dead (a shot outlives its shooter: `ScoreKeeper.shooters` remembers the dead); -1 unknown.
func shooter_team(id: int) -> int:
	if id == 0:
		return -1
	if _store.alive(id):
		return _store.team[EntityId.slot(id)]
	var i: int = _score.shooters.find(id)
	return _score.shooters.team[i] if i >= 0 else -1


## The 02 s12.1 value per team rounded to whole points: what `MatchResult.structure_value` reports (one formula).
func values_by_team() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var e: int = out.resize(PlayerTable.TEAMS)
	assert(e == OK)
	for t: int in PlayerTable.TEAMS:
		out[t] = roundi(structure_value(t))
	return out


## DamageSink: `amount` of damage dealt to a finished enemy structure by an entity of `team` (the hard-end tie-break).
func note_damage(team: int, amount: float) -> void:
	if team >= 0 and team < PlayerTable.TEAMS and amount > 0.0:
		_state.structure_damage[team] += amount


func structure_damage(team: int) -> float:
	return _state.structure_damage[team] if team >= 0 and team < PlayerTable.TEAMS else 0.0


## The winning team (-1 a draw); `NO_WINNER` while the match runs.
func winner() -> int:
	return _state.winner_team if _state.ended() else NO_WINNER


## The `EndReason` once ended, else -1.
func end_reason() -> int:
	return _state.end_reason if _state.ended() else -1


## The tick `player`'s structures are due to self-destruct; -1 when not eliminated (or already done).
func selfdestruct_tick(player: int) -> int:
	return _state.selfdestruct[player] if player >= 0 and player < PlayerTable.SLOTS else -1


# --- elimination and defeat ------------------------------------------------------------------------------------------

func _scan_cores() -> void:
	_cores.fill(0)
	for s: int in _store.structures:
		if _store.def_id[s] == _core_def and _store.owner[s] < PlayerTable.SLOTS:
			_cores[_store.owner[s]] += 1
	for p: int in PlayerTable.SLOTS:
		if _cores[p] > 0:
			_state.had_core[p] = 1


# M1: an active player that owned a Core and owns none is eliminated; its structures are due in `eliminated_selfdestruct_s`.
func _eliminate_lost_cores(tick: int) -> void:
	for p: int in PlayerTable.SLOTS:
		if _players.is_active(p) and _players.eliminated[p] == 0 and _state.had_core[p] != 0 and _cores[p] == 0:
			_eliminate(p, tick)


func _eliminate(p: int, tick: int) -> void:
	_players.eliminated[p] = 1
	_state.selfdestruct[p] = tick + (_ticks(_mr.eliminated_selfdestruct_s) if _mr != null else 0)
	var _e: SimEvent = _events.emit(SimEvent.Kind.PLAYER_ELIMINATED, p, _killer[p], Vector3.ZERO, 0.0, _players.team[p])


# M3: a team whose members once owned a Core and own none now is defeated.
func _defeat_lost_teams(tick: int) -> void:
	for t: int in PlayerTable.TEAMS:
		if _state.defeated[t] != 0:
			continue
		var had: bool = false
		var cores: int = 0
		for p: int in PlayerTable.SLOTS:
			if _players.is_active(p) and _players.team[p] == t:
				had = had or _state.had_core[p] != 0
				cores += _cores[p]
		if had and cores == 0:
			_defeat(t, tick, EndReason.CORES_DESTROYED)


func _defeat(t: int, tick: int, reason: int) -> void:
	_state.defeated[t] = 1
	_fresh_defeat = true
	_reason = reason
	for p: int in PlayerTable.SLOTS:
		if _players.is_active(p) and _players.team[p] == t and _players.eliminated[p] == 0:
			_eliminate(p, tick)
	_control.release_team(t)


# M4: a team whose connected human members (02 s12.1; an eliminated teammate still votes) have all voted surrenders.
func _count_surrenders(tick: int) -> void:
	for t: int in PlayerTable.TEAMS:
		if _state.defeated[t] != 0:
			continue
		var voters: int = 0
		var voted: int = 0
		for p: int in PlayerTable.SLOTS:
			if _players.is_active(p) and _players.team[p] == t and _players.kind[p] == PlayerTable.KIND_HUMAN \
					and _players.connected[p] != 0:
				voters += 1
				voted += _state.votes[p]
		if voters > 0 and voted == voters:
			_defeat(t, tick, EndReason.SURRENDER)


# Teams with an active player that are not defeated.
func _alive_teams() -> int:
	var n: int = 0
	for t: int in PlayerTable.TEAMS:
		if _team_present(t) and _state.defeated[t] == 0:
			n += 1
	return n


# The one team still in when exactly one is, else -1.
func _teams_left() -> int:
	var last: int = -1
	var n: int = 0
	for t: int in PlayerTable.TEAMS:
		if _team_present(t) and _state.defeated[t] == 0:
			last = t
			n += 1
	return last if n == 1 else -1


func _team_present(t: int) -> bool:
	for p: int in PlayerTable.SLOTS:
		if _players.is_active(p) and _players.team[p] == t:
			return true
	return false


# --- the end ---------------------------------------------------------------------------------------------------------

# M6: the team still in with the higher structure value; then the higher damage dealt to enemy structures; else -1.
func _hard_end_winner() -> int:
	var best: int = -1
	var best_v: float = 0.0
	var tied: bool = false
	for t: int in PlayerTable.TEAMS:
		if not _team_present(t) or _state.defeated[t] != 0:
			continue
		var v: float = structure_value(t)
		if best < 0 or (not is_equal_approx(v, best_v) and v > best_v):
			best = t
			best_v = v
			tied = false
		elif is_equal_approx(v, best_v):                    # equal value: the damage dealt to enemy structures decides
			if _state.structure_damage[t] > _state.structure_damage[best]:
				best = t
				tied = false
			elif is_equal_approx(_state.structure_damage[t], _state.structure_damage[best]):
				tied = true
	return -1 if tied else best


func _end(tick: int, winner_team: int, reason: int) -> void:
	_state.ended_tick = tick
	_state.winner_team = winner_team
	_state.end_reason = reason
	_score.finalize(winner_team)                             # GD-27: match_win
	_control.release_all(ControlMachine.ReleaseReason.MATCH)
	var _m: SimEvent = _events.emit(SimEvent.Kind.MATCH_END, winner_team, 0, Vector3.ZERO, _clock(tick), -1, reason)


func _one_v_one() -> bool:
	_members.fill(0)
	for p: int in PlayerTable.SLOTS:
		if _players.is_active(p) and _players.team[p] >= 0 and _players.team[p] < PlayerTable.TEAMS:
			_members[_players.team[p]] += 1
	var teams: int = 0
	for t: int in PlayerTable.TEAMS:
		if _members[t] > 1:
			return false
		teams += _members[t]
	return teams == 2


func _ticks(seconds: float) -> int:
	return roundi(seconds * float(_rules.tick_hz))


func _clock(tick: int) -> float:
	return float(tick) / float(_rules.tick_hz)
