class_name TokenBucket extends RefCounted
## Token bucket on caller-supplied integer milliseconds (04 s11.4): refills at `rate_per_s` up to `burst`, never reads a
## wall clock, so a link replays identically under LocalTransport. Starts full.

var rate_per_s: float
var burst: float
var _tokens: float
var _last_ms: int


func _init(p_rate_per_s: float, p_burst: float, now_ms: int) -> void:
	rate_per_s = p_rate_per_s
	burst = p_burst
	_tokens = p_burst
	_last_ms = now_ms


## Takes `cost` tokens when available. A clock that moves backwards refills nothing.
func take(now_ms: int, cost: float = 1.0) -> bool:
	_refill(now_ms)
	if _tokens < cost:
		return false
	_tokens -= cost
	return true


func available(now_ms: int) -> float:
	_refill(now_ms)
	return _tokens


func _refill(now_ms: int) -> void:
	if now_ms > _last_ms:
		_tokens = minf(burst, _tokens + rate_per_s * float(now_ms - _last_ms) * 0.001)
	_last_ms = maxi(_last_ms, now_ms)
