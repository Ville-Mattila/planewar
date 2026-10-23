class_name ClientClock extends RefCounted
## The client's one clock (04 s5.1): an estimate of the server tick counter. Every snapshot header tick and every
## PONG feeds `observe(server_tick, now_ms)`: the sample `server_tick - now_ms / tick_ms` (so the estimate is
## `last_snapshot_tick + elapsed_since_arrival / DT`) is smoothed by an exponential drift estimator (alpha 0.05).
## The tick that render and input read (`clock`) never jumps while synced: `advance` runs it at up to 1.05x / down to
## 0.95x of real time toward the estimate (time dilation, proportional below half a tick of error). It jumps only on
## the first sample after `reset` (connect, reconnect) or a discontinuity above 500 ms (`resyncs` counts both).
## render_tick = clock - INTERP_DELAY_TICKS (100 ms, ADR-07); input_tick = clock + ceil(rtt / 2 / DT) +
## INPUT_LEAD_TICKS + the dilated input lead that late / early input reports move (NET-18 feeds them).

const INTERP_DELAY_TICKS: int = 3
const INPUT_LEAD_TICKS: int = 1
const DRIFT_ALPHA: float = 0.05
const RTT_ALPHA: float = 0.2                ## PONG is 1 Hz: a faster filter than the 30 Hz offset
const DILATION_MAX: float = 0.05            ## 1.05x / 0.95x
const DILATION_GAIN: float = 0.1            ## rate change per tick of clock error (saturates at 0.5 tick)
const RESYNC_MS: float = 500.0
const EARLY_TICKS: int = 6                  ## inputs arriving more than this many ticks early slow the input clock
const LEAD_MAX: float = 8.0                 ## the server's jitter window (InputBuffer.WINDOW_FUTURE)

var tick_ms: float = 1000.0 / 30.0
var synced: bool = false
var offset: float = 0.0                     ## filtered `server_tick - now_ms / tick_ms`
var clock: float = 0.0                      ## dilated server tick: what render and input read
var rate: float = 1.0                       ## dilation applied by the last advance
var rtt_ms: float = 0.0
var lead: float = 0.0                       ## extra input lead in ticks (time-dilated, +-LEAD_MAX)
var samples: int = 0
var resyncs: int = 0
var _last_ms: float = 0.0


func _init(tick_hz: int = 30) -> void:
	tick_ms = 1000.0 / float(maxi(tick_hz, 1))


## Back to unsynced (connect / reconnect): the next sample sets the clock directly.
func reset() -> void:
	synced = false
	offset = 0.0
	clock = 0.0
	rate = 1.0
	lead = 0.0
	samples = 0


## One arrival: a SNAPSHOT header tick or a PONG's server_tick, received at local time `now_ms`.
func observe(server_tick: int, now_ms: float) -> void:
	var s: float = float(server_tick) - now_ms / tick_ms
	samples += 1
	if not synced or absf(s - offset) * tick_ms > RESYNC_MS:
		offset = s
		clock = estimate(now_ms)
		_last_ms = now_ms
		synced = true
		resyncs += 1
		return
	offset += DRIFT_ALPHA * (s - offset)


## PONG round trip: `now_ms - client_ms` of the echoed PING (smoothed like the offset).
func observe_rtt(rtt: float) -> void:
	if rtt < 0.0:
		return
	rtt_ms = rtt if rtt_ms <= 0.0 else rtt_ms + RTT_ALPHA * (rtt - rtt_ms)


## The filtered server tick estimate at local time `now_ms`.
func estimate(now_ms: float) -> float:
	return now_ms / tick_ms + offset


## Moves `clock` to local time `now_ms`, dilated toward the estimate (never backwards, never by a jump while synced).
func advance(now_ms: float) -> void:
	if not synced:
		return
	var dt_ticks: float = maxf(now_ms - _last_ms, 0.0) / tick_ms
	_last_ms = maxf(now_ms, _last_ms)
	var err: float = estimate(_last_ms) - (clock + dt_ticks)
	if absf(err) * tick_ms > RESYNC_MS:
		clock = estimate(_last_ms)
		rate = 1.0
		resyncs += 1
		return
	rate = 1.0 + clampf(err * DILATION_GAIN, -DILATION_MAX, DILATION_MAX)
	clock += dt_ticks * rate


## Presentation samples NetSimView here (04 s5.1).
func render_tick() -> float:
	return clock - float(INTERP_DELAY_TICKS)


## The tick the client predicts and sends input for: ahead of the server by half the RTT plus one tick.
func input_tick() -> int:
	return floori(clock) + ceili(rtt_ms * 0.5 / tick_ms) + INPUT_LEAD_TICKS + roundi(lead)


## Once per tick from the input path: `late_inputs` > 0 (server report or a lagging ack) runs the input clock at
## 1.05x, inputs more than EARLY_TICKS early at 0.95x (04 s5.1); otherwise the lead holds.
func note_input_timing(late_inputs: int, early_ticks: int) -> void:
	if late_inputs > 0:
		lead = minf(lead + DILATION_MAX, LEAD_MAX)
	elif early_ticks > EARLY_TICKS:
		lead = maxf(lead - DILATION_MAX, -LEAD_MAX)
