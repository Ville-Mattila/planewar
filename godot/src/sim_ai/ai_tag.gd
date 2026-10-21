class_name AiTag
## Enum holder for the replicated `ai_tag` u8 (05 s6.1; R0 B.3, B.17 A-94; append-only, ordinals frozen). Every brain
## writes only these values through `CommandSinkBase.set_ai_tag` and keeps the same ordinal in `AiState.mode`; the sim
## and `net` stay opaque to it; 06's `content/ui/ai_tags.json` (UX-43) maps each ordinal to a HUD label. 0-15 are the
## Dart's modes (AI-13), 16-33 are reserved for the 05 s6 brains of AI-14 / AI-16 / AI-17 / AI-18.

enum Tag { NONE, LAUNCH, PATROL, INTERCEPT, ENGAGE, EXTEND, EVADE, BOMB, RETURN, DOCKED, PULL_UP, MOVE, HOLD, GUARD,
		ESCORT, LOITER, FLEE, SEARCH, FERRY_PICK, LOAD, FERRY_DROP, TOW, CAPTURE, PICK_FIELD, TO_FIELD, MINE, TO_REFINERY,
		QUEUE, UNLOAD, SIEGE, RELOCATE, TRACK, OFFLINE, IDLE }
