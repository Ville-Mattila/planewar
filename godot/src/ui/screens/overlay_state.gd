class_name OverlayState extends RefCounted
## The Match screen's overlay state (06 s8 Match row) and the ELIMINATED_COMMANDER trigger (UX-27, GD-20).

enum State { PLAYING, PEEK, PAUSED, RECONNECTING, ELIMINATED_COMMANDER, SPECTATING, ENDING }


## Highest priority first: ENDING, RECONNECTING, PAUSED, ELIMINATED_COMMANDER, SPECTATING, PEEK, PLAYING.
static func resolve(ending: bool, reconnecting: bool, paused: bool, eliminated: bool, spectating: bool,
		peek: bool) -> State:
	if ending:
		return State.ENDING
	if reconnecting:
		return State.RECONNECTING
	if paused:
		return State.PAUSED
	if eliminated:
		return State.ELIMINATED_COMMANDER
	if spectating:
		return State.SPECTATING
	return State.PEEK if peek else State.PLAYING


## PLAYER_ELIMINATED (a = slot) for the local slot.
static func is_local_elimination(e: SimEvent, local_slot: int) -> bool:
	return e.kind == SimEvent.Kind.PLAYER_ELIMINATED and e.a == local_slot


## The authoritative flag, for late joiners and keyframes.
static func is_eliminated(p: PlayerStateView) -> bool:
	return p.eliminated
