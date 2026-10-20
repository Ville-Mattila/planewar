class_name InputClass extends RefCounted
## Input device classes, boot defaults and assist-tier defaults (06 s2.4). Pure statics.

enum Kind { TOUCH, GAMEPAD, POINTER }

const TIER_RAW: int = 0
const TIER_STANDARD: int = 1
const TIER_FULL: int = 2


## Boot default: mobile and mobile-web -> TOUCH; Steam Deck -> GAMEPAD; else POINTER (06 s2.4).
static func boot_class_from(mobile: bool, web_touch: bool, steam_deck: bool) -> int:
	if mobile or web_touch:
		return Kind.TOUCH
	if steam_deck:
		return Kind.GAMEPAD
	return Kind.POINTER


static func boot_class() -> int:
	var mobile: bool = OS.has_feature("mobile")
	var web_touch: bool = OS.has_feature("web_android") or OS.has_feature("web_ios")
	var deck: bool = OS.get_environment("SteamDeck") == "1"
	return boot_class_from(mobile, web_touch, deck)


## Default assist tier per class: touch Full, gamepad Standard, pointer Raw (01 s3.1.4).
static func default_tier(kind: int) -> int:
	match kind:
		Kind.TOUCH:
			return TIER_FULL
		Kind.GAMEPAD:
			return TIER_STANDARD
	return TIER_RAW


## Ranked applied tier: min of the queued class default and the active device default (06 s2.4).
## A match class of -1 (offline) uses the active class alone.
static func ranked_tier(match_class: int, active_class: int) -> int:
	var active: int = default_tier(active_class)
	if match_class < 0:
		return active
	return mini(default_tier(match_class), active)
