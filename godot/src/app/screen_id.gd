class_name ScreenId extends RefCounted
## Screen ids and the allowed-transition table of the 06 s8 flowchart (UX-24).
## Ids are stable StringNames; scenes live in godot/scenes/ui/screens/ (06 s8 table).

const BOOT: StringName = &"boot"
const START_GATE: StringName = &"start_gate"
const AGE_GATE: StringName = &"age_gate"
const MAIN_MENU: StringName = &"main_menu"
const ONLINE: StringName = &"online"
const ACCOUNT: StringName = &"account"
const QUEUE: StringName = &"queue"
const SETUP_CUSTOM: StringName = &"setup_custom"
const SETUP_SKIRMISH: StringName = &"setup_skirmish"
const SETUP_COOP: StringName = &"setup_coop"
const CAMPAIGN: StringName = &"campaign"
const BRIEFING: StringName = &"briefing"
const REPLAYS: StringName = &"replays"
const REPLAY_VIEWER: StringName = &"replay_viewer"
const SETTINGS: StringName = &"settings"
const PROFILE: StringName = &"profile"
const LOBBY: StringName = &"lobby"
const LOADING: StringName = &"loading"
const MATCH: StringName = &"match"
const PAUSE: StringName = &"pause"
const SAVE_LOAD: StringName = &"save_load"
const RECONNECTING: StringName = &"reconnecting"
const RESULTS: StringName = &"results"


static func all_ids() -> Array[StringName]:
	return [
		BOOT, START_GATE, AGE_GATE, MAIN_MENU, ONLINE, ACCOUNT, QUEUE, SETUP_CUSTOM,
		SETUP_SKIRMISH, SETUP_COOP, CAMPAIGN, BRIEFING, REPLAYS, REPLAY_VIEWER, SETTINGS,
		PROFILE, LOBBY, LOADING, MATCH, PAUSE, SAVE_LOAD, RECONNECTING, RESULTS,
	]


## Allowed targets from `from`: the 06 s8 mermaid edges (docs/06 lines 745-767) plus these, each cited:
## AGE_GATE->LOADING (06:748, Age -> M1, a match, so it loads); PAUSE->SETTINGS, PAUSE->MAIN_MENU (Leave),
## PAUSE->SAVE_LOAD and SAVE_LOAD->PAUSE / SAVE_LOAD->LOADING (Load restarts via Loading), all from the
## Pause items list (06:796).
static func targets(from: StringName) -> Array[StringName]:
	match from:
		BOOT:
			return [START_GATE, AGE_GATE, MAIN_MENU]
		START_GATE:
			return [AGE_GATE, MAIN_MENU]
		AGE_GATE:
			return [LOADING]  # first run goes straight into Campaign M1
		MAIN_MENU:
			return [ONLINE, SETUP_SKIRMISH, SETUP_COOP, CAMPAIGN, REPLAYS, SETTINGS, PROFILE]
		ONLINE:
			return [ACCOUNT, QUEUE, SETUP_CUSTOM]
		ACCOUNT:
			return [ONLINE]
		QUEUE, SETUP_CUSTOM, SETUP_SKIRMISH, SETUP_COOP:
			return [LOBBY]
		CAMPAIGN:
			return [BRIEFING]
		BRIEFING:
			return [LOADING]
		REPLAYS:
			return [REPLAY_VIEWER]
		LOBBY:
			return [LOADING]
		LOADING:
			return [MATCH]
		MATCH:
			return [PAUSE, RECONNECTING, RESULTS]
		PAUSE:
			return [MATCH, SAVE_LOAD, SETTINGS, MAIN_MENU]
		SAVE_LOAD:
			return [PAUSE, LOADING]
		RECONNECTING:
			return [MATCH]
		RESULTS:
			return [LOBBY, MAIN_MENU]
	return []


## Entering these clears the back stack (nothing meaningful to go back to).
static func clears_stack(id: StringName) -> bool:
	return id == MAIN_MENU or id == RESULTS or id == LOADING


## Leaving these never pushes them (one-shot gates, loading, results).
static func is_transient(id: StringName) -> bool:
	return id == BOOT or id == START_GATE or id == AGE_GATE or id == LOADING or id == RESULTS
