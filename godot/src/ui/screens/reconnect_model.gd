class_name ReconnectModel extends RefCounted
## Reconnecting overlay state (06 s8, s9.1 Stall detection, 04 s9 120 s ticket; UX-27). Pure: the host feeds `tick(dt)` and,
## when it returns true, makes one reconnect attempt. A hidden-tab stall starts RESYNCING ("Resyncing...", keyframe
## requested); past `resync_drop_s` or on a transport loss it is RETRYING, auto-retrying every `reconnect_retry_s` until
## `reconnect_window_s` after `begin` (the commander window), then REJOIN_OFFERED (the Adjutant holds the slot).

enum State { IDLE, RESYNCING, RETRYING, REJOIN_OFFERED, RECOVERED }

var state: State = State.IDLE
var elapsed_s: float = 0.0
var attempts: int = 0
var _since_attempt_s: float = 0.0


## `resync` true after a stall (keyframe requested), false after a transport loss.
func begin(resync: bool) -> void:
	elapsed_s = 0.0
	attempts = 0
	state = State.RESYNCING if resync else State.RETRYING
	_since_attempt_s = ScreenParams.param("reconnect_retry_s")


## Advances the clock; true when the host should attempt a reconnect now.
func tick(dt: float) -> bool:
	if state != State.RESYNCING and state != State.RETRYING:
		return false
	elapsed_s += maxf(dt, 0.0)
	if elapsed_s >= window_s():
		state = State.REJOIN_OFFERED
		return false
	if state == State.RESYNCING:
		if elapsed_s <= ScreenParams.param("resync_drop_s"):
			return false
		state = State.RETRYING
	_since_attempt_s += maxf(dt, 0.0)
	if _since_attempt_s < ScreenParams.param("reconnect_retry_s"):
		return false
	_since_attempt_s = 0.0
	attempts += 1
	return true


## A keyframe or reconnect succeeded: the overlay closes.
func on_recovered() -> void:
	if state == State.RESYNCING or state == State.RETRYING or state == State.REJOIN_OFFERED:
		state = State.RECOVERED


## The "Rejoin" button: a fresh window of auto-retries. False unless it is being offered.
func rejoin() -> bool:
	if state != State.REJOIN_OFFERED:
		return false
	elapsed_s = 0.0
	state = State.RETRYING
	_since_attempt_s = ScreenParams.param("reconnect_retry_s")
	return true


func window_s() -> float:
	return ScreenParams.param("reconnect_window_s")


func remaining_s() -> float:
	return maxf(window_s() - elapsed_s, 0.0)


func is_open() -> bool:
	return state == State.RESYNCING or state == State.RETRYING or state == State.REJOIN_OFFERED
