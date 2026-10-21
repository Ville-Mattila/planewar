class_name TeamIntel extends RefCounted
## The AI driver's per-team perception and threat map (05 s6: the team's map behind the brains' read-only sampler,
## "shared per team, refreshed at 1 Hz by the AI driver whether or not a Commander bot exists"; AI-22). Team t refreshes
## (Perception.refresh, then ThreatMap.update, one slice) on the ticks with (tick + STAGGER * t + PHASE) % period == 0,
## so 8 teams spread over the period on odd residues and never share a tick with the bots (tick + 4 k, even). Only
## tracked teams cost anything.
## Brains read `threat_map(team)` / `perception(team)` and never write them.

const FORMAT: int = 1
const STAGGER: int = 4
const PHASE: int = 1

var tables: ThreatParams = null
var profile: PerceptionParams = null
var period: int = 1                       ## ticks between a team's refreshes (tick_hz: 1 Hz)
var stats_updates: int = 0                ## refresh + update slices run (work counter)

var _perc: Array[Perception] = []
var _maps: Array[ThreatMap] = []
var _mask: int = 0


func _init(t: ThreatParams, team_profile: PerceptionParams, period_ticks: int) -> void:
	tables = t
	profile = team_profile
	period = maxi(period_ticks, 1)
	for k: int in PlayerTable.TEAMS:
		_perc.append(null)
		_maps.append(null)


## Starts (or stops and drops) team `team`'s intel.
func track(team: int, on: bool) -> void:
	if team < 0 or team >= PlayerTable.TEAMS:
		return
	if on and _perc[team] == null:
		_perc[team] = Perception.new(team, -1, profile, tables)
		_maps[team] = ThreatMap.new(tables)
	elif not on:
		_perc[team] = null
		_maps[team] = null
	_mask = (_mask | (1 << team)) if on else (_mask & ~(1 << team))


func tracked(team: int) -> bool:
	return team >= 0 and team < PlayerTable.TEAMS and (_mask & (1 << team)) != 0


## Whether team `team` refreshes on `tick`.
func due(team: int, tick: int) -> bool:
	return MathX.posmod_i(tick + STAGGER * team + PHASE, period) == 0


## The due teams' slices of `tick`.
func step(tick: int, v: SimView) -> void:
	if _mask == 0:
		return
	for t: int in PlayerTable.TEAMS:
		if (_mask & (1 << t)) != 0 and due(t, tick):
			_perc[t].refresh(v, tick)
			_maps[t].update(v, _perc[t], tick)
			stats_updates += 1


## Team `team`'s map (null when not tracked). Read only.
func threat_map(team: int) -> ThreatMap:
	return _maps[team] if tracked(team) else null


## Team `team`'s perception (null when not tracked). Read only.
func perception(team: int) -> Perception:
	return _perc[team] if tracked(team) else null


## S4 bytes: FORMAT, the tracked mask, per tracked team (ascending) the length-prefixed Perception and ThreatMap bytes.
func serialize() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(FORMAT)
	b.put_u8(_mask)
	for t: int in PlayerTable.TEAMS:
		if tracked(t):
			var pb: PackedByteArray = _perc[t].serialize()
			var mb: PackedByteArray = _maps[t].serialize()
			b.put_u32(pb.size())
			var _e1: Error = b.put_data(pb)
			b.put_u32(mb.size())
			var _e2: Error = b.put_data(mb)
	return b.data_array


## Restores `serialize` bytes and re-runs each map's update on its restored perception (identical channels); false
## (nothing tracked) on a wrong FORMAT or bad section.
func deserialize(bytes: PackedByteArray) -> bool:
	for t: int in PlayerTable.TEAMS:
		track(t, false)
	if bytes.size() < 2 or bytes[0] != FORMAT:
		return false
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	b.seek(1)
	var mask: int = b.get_u8()
	for t: int in PlayerTable.TEAMS:
		if (mask & (1 << t)) == 0:
			continue
		track(t, true)
		if not _perc[t].deserialize(_section(b)) or not _maps[t].deserialize(_section(b)):
			for u: int in PlayerTable.TEAMS:
				track(u, false)
			return false
		if _maps[t].updated >= 0:
			_maps[t].update(null, _perc[t], _maps[t].updated)
	return true


static func _section(b: StreamPeerBuffer) -> PackedByteArray:
	if b.get_available_bytes() < 4:
		return PackedByteArray()
	var n: int = b.get_u32()
	var pos: int = b.get_position()
	if n > b.get_available_bytes():
		return PackedByteArray()
	b.seek(pos + n)
	return b.data_array.slice(pos, pos + n)
