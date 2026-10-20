class_name Intents extends RefCounted
## Intent kind and payload-key constants (06 s2.5). Kinds are StringNames emitted by InputRouter.intent;
## consumers read payload values with typed casts.

# Selection
const SELECT: StringName = &"select"
const SELECT_BOX: StringName = &"select_box"
const SELECT_PAINT: StringName = &"select_paint"
const SELECT_SAME: StringName = &"select_same"
const DESELECT: StringName = &"deselect"
# Orders
const ORDER_CONTEXT: StringName = &"order_context"
const ORDER_MENU: StringName = &"order_menu"
const ORDER: StringName = &"order"
# Building
const BUILD_ARM: StringName = &"build_arm"
const BUILD_MOVE: StringName = &"build_move"
const BUILD_ROTATE: StringName = &"build_rotate"
const BUILD_CONFIRM: StringName = &"build_confirm"
const BUILD_CANCEL: StringName = &"build_cancel"
# Production
const PRODUCE: StringName = &"produce"
const CANCEL_PRODUCE: StringName = &"cancel_produce"
const SET_REPLENISH: StringName = &"set_replenish"
# Camera
const CAM_PAN_GRAB: StringName = &"cam_pan_grab"
const CAM_PAN_VEL: StringName = &"cam_pan_vel"
const CAM_ZOOM: StringName = &"cam_zoom"
const CAM_ROTATE: StringName = &"cam_rotate"
const CAM_TILT: StringName = &"cam_tilt"
const CAM_TIER_TOGGLE: StringName = &"cam_tier_toggle"
const CAM_HOME: StringName = &"cam_home"
const FREE_LOOK: StringName = &"free_look"
# Alerts and possession
const JUMP_ALERT: StringName = &"jump_alert"
const POSSESS: StringName = &"possess"
const REQUEST_POSSESS: StringName = &"request_possess"
const QUICK_FLY: StringName = &"quick_fly"
const RELEASE: StringName = &"release"
const PEEK: StringName = &"peek"
const HANDOVER_ACCEPT: StringName = &"handover_accept"
# Groups
const GROUP_SELECT: StringName = &"group_select"
const GROUP_ASSIGN: StringName = &"group_assign"
const GROUP_JUMP: StringName = &"group_jump"
# Pings
const PING_WHEEL: StringName = &"ping_wheel"
const PING: StringName = &"ping"
const WING_RADIAL: StringName = &"wing_radial"
# Feed and spectate
const FEED_FILTER: StringName = &"feed_filter"
const SPECTATE_NEXT: StringName = &"spectate_next"
const SPECTATE_PREV: StringName = &"spectate_prev"
# Menus
const CHAT_OPEN: StringName = &"chat_open"
const MENU: StringName = &"menu"
const BACK: StringName = &"back"
const ROSTER: StringName = &"roster"

# Payload keys
const K_POS: StringName = &"pos"
const K_RECT: StringName = &"rect"
const K_CENTER: StringName = &"center"
const K_RADIUS: StringName = &"radius"
const K_ADD: StringName = &"add"
const K_ORDER: StringName = &"order"
const K_DEF_ID: StringName = &"def_id"
const K_STEPS: StringName = &"steps"
const K_COUNT: StringName = &"count"
const K_FROM: StringName = &"from"
const K_TO: StringName = &"to"
const K_VEL: StringName = &"vel"
const K_LOG_DELTA: StringName = &"log_delta"
const K_ANCHOR: StringName = &"anchor"
const K_RAD: StringName = &"rad"
const K_VEC: StringName = &"vec"
const K_INDEX: StringName = &"index"
const K_ENTITY: StringName = &"entity"
const K_ON: StringName = &"on"
const K_SLOT: StringName = &"slot"
const K_OPEN: StringName = &"open"
const K_PING: StringName = &"ping"
const K_LANE: StringName = &"lane"


## Every kind in 06 s2.5 order (for catalogue tests and remap UIs).
static func all_kinds() -> Array[StringName]:
	return [
		SELECT, SELECT_BOX, SELECT_PAINT, SELECT_SAME, DESELECT, ORDER_CONTEXT, ORDER_MENU, ORDER,
		BUILD_ARM, BUILD_MOVE, BUILD_ROTATE, BUILD_CONFIRM, BUILD_CANCEL, PRODUCE, CANCEL_PRODUCE,
		SET_REPLENISH, CAM_PAN_GRAB, CAM_PAN_VEL, CAM_ZOOM, CAM_ROTATE, CAM_TILT, CAM_TIER_TOGGLE,
		CAM_HOME, FREE_LOOK, JUMP_ALERT, POSSESS, REQUEST_POSSESS, QUICK_FLY, RELEASE, PEEK,
		HANDOVER_ACCEPT, GROUP_SELECT, GROUP_ASSIGN, GROUP_JUMP, PING_WHEEL, PING, WING_RADIAL,
		FEED_FILTER, SPECTATE_NEXT, SPECTATE_PREV, CHAT_OPEN, MENU, BACK, ROSTER,
	]
