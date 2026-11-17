class_name LoadingModel extends RefCounted
## Loading screen state (06 s8): DOWNLOADING_MAP, PREWARMING, WAITING_PLAYERS, TIMEOUT. Pure; the host feeds progress.
## Roster rows reveal the doctrines (06 s8 Lobby: "doctrines are revealed on the loading screen").

enum State { DOWNLOADING_MAP, PREWARMING, WAITING_PLAYERS, TIMEOUT }

var map01: float = 0.0
var prewarm01: float = 0.0
var ready_count: int = 0
var player_count: int = 0
var waited_s: float = 0.0
var names: PackedStringArray = PackedStringArray()
var doctrines: PackedStringArray = PackedStringArray()   ## localised doctrine names, "" while hidden
var ready_flags: PackedByteArray = PackedByteArray()


func set_progress(map_fraction: float, prewarm_fraction: float) -> void:
	map01 = clampf(map_fraction, 0.0, 1.0)
	prewarm01 = clampf(prewarm_fraction, 0.0, 1.0)


func set_roster(p_names: PackedStringArray, p_doctrines: PackedStringArray, p_ready: PackedByteArray) -> void:
	names = p_names
	doctrines = p_doctrines
	ready_flags = p_ready
	player_count = p_names.size()
	ready_count = 0
	for f: int in p_ready:
		if f != 0:
			ready_count += 1


## Counts only while waiting for the others (the local load is done).
func tick(dt: float) -> void:
	if state() == State.WAITING_PLAYERS:
		waited_s += maxf(dt, 0.0)


func state() -> State:
	if waited_s >= _timeout_s():
		return State.TIMEOUT
	if map01 < 1.0:
		return State.DOWNLOADING_MAP
	if prewarm01 < 1.0:
		return State.PREWARMING
	return State.WAITING_PLAYERS


## `match_rules.json` `load_timeout_s`, read from ContentDB (0 when content is not loaded).
func _timeout_s() -> float:
	return ContentDB.match_rules.load_timeout_s if ContentDB.match_rules != null else 0.0


func ready_fraction() -> float:
	return 0.0 if player_count <= 0 else float(ready_count) / float(player_count)


## Weighted overall progress 0..1 (weights in screens.json).
func progress01() -> float:
	var w_map: float = ScreenParams.param("loading_map_weight")
	var w_pre: float = ScreenParams.param("loading_prewarm_weight")
	var w_rdy: float = ScreenParams.param("loading_ready_weight")
	var total: float = w_map + w_pre + w_rdy
	if total <= 0.0:
		return 0.0
	return clampf((map01 * w_map + prewarm01 * w_pre + ready_fraction() * w_rdy) / total, 0.0, 1.0)
