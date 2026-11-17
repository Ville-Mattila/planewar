class_name PauseModel extends RefCounted
## Pause menu contents and scope (06 s8 Pause; R0 B.9 A-16). Offline pauses the in-process server; online is an overlay
## with neutral input to the possessed unit; Co-op (`pause_scope` "listen_host") pauses for the listen host only and has
## no Save/Load. Items: Resume, Save, Load, Settings, Players, Chat, Surrender, Leave.

const SCOPE_LISTEN_HOST: String = "listen_host"
const SCOPE_IN_PROCESS: String = "in_process"

const IDS: Array[StringName] = [&"resume", &"save", &"load", &"settings", &"players", &"chat", &"surrender", &"leave"]


## `online` = other humans are connected (queue, custom lobby, Co-op); `pause_save` and `pause_scope` are the mode's
## `modes.json` fields; `surrender_ok` = SimView says the vote is accepted now (min match clock, not eliminated).
static func items(online: bool, pause_save: bool, pause_scope: String, surrender_ok: bool) -> Array[PauseItem]:
	var save_ok: bool = pause_save and pause_scope != SCOPE_LISTEN_HOST and not online
	var out: Array[PauseItem] = []
	out.append(PauseItem.make(&"resume"))
	out.append(PauseItem.make(&"save", save_ok, &"ui.pause.reason.no_save"))
	out.append(PauseItem.make(&"load", save_ok, &"ui.pause.reason.no_save"))
	out.append(PauseItem.make(&"settings"))
	out.append(PauseItem.make(&"players", online, &"ui.pause.reason.offline"))
	out.append(PauseItem.make(&"chat", online, &"ui.pause.reason.offline"))
	var sur_reason: StringName = &"ui.pause.reason.offline" if not online else &"ui.pause.reason.too_early"
	out.append(PauseItem.make(&"surrender", online and surrender_ok, sur_reason))
	out.append(PauseItem.make(&"leave"))
	return out


## True when opening the menu stops the sim: offline always, Co-op for the listen host only; other online play
## only overlays the menu (neutral input to the possessed unit).
static func pauses_sim(online: bool, pause_scope: String, is_listen_host: bool) -> bool:
	if not online:
		return true
	return pause_scope == SCOPE_LISTEN_HOST and is_listen_host
