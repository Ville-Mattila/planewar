class_name ShotTracker extends RefCounted
## Client side of PROJECTILE_BATCH (R0 C2-35): decodes a batch, drops duplicates by (shooter, seed, tick) so the
## re-sent batch never spawns a shot twice, and keeps the live shots: spawn tick, quantised direction, flak burst
## tick (spawn tick + fuse). The session spawns the presentation projectile from the shooter's interpolated state
## with `Kinematics.step_projectile` (NET-17); `due_bursts` names the flak shells whose fuse tick has come and
## `remove_hit` retires a shot named by a HIT event (shooter + seed). Not a hot path: a Dictionary holds the keys.

const KEY_KEEP_TICKS: int = 8
const MAX_LIVE: int = 1024

var shooter: PackedInt32Array = PackedInt32Array()
var weapon_slot: PackedInt32Array = PackedInt32Array()
var seed_byte: PackedInt32Array = PackedInt32Array()
var yaw_q: PackedInt32Array = PackedInt32Array()
var pitch_q: PackedInt32Array = PackedInt32Array()
var spawn_tick: PackedInt32Array = PackedInt32Array()
var burst_tick: PackedInt32Array = PackedInt32Array()      # -1 for slugs and rail slugs
var duplicates: int = 0
var rejected: int = 0
var _seen: Dictionary[int, int] = {}                        # key -> tick
var _scratch: ShotBuffer = ShotBuffer.new()


func count() -> int:
	return shooter.size()


## Decodes and registers one PROJECTILE_BATCH. Returns the number of NEW shots, or -1 for a malformed packet
## (counted in `rejected`, nothing registered).
func accept(bytes: PackedByteArray, now_tick: int) -> int:
	if ProjectileBatch.decode(bytes, _scratch) < 0:
		rejected += 1
		return -1
	var fresh: int = 0
	for i: int in _scratch.count:
		var key: int = _scratch.shooter[i] | (_scratch.seed_byte[i] << 16) | (_scratch.tick << 24)
		if _seen.has(key):
			duplicates += 1
			continue
		if shooter.size() >= MAX_LIVE:
			continue
		_seen[key] = _scratch.tick
		_register(i)
		fresh += 1
	_prune_keys(now_tick)
	return fresh


func _register(i: int) -> void:
	var _a0: bool = shooter.append(_scratch.shooter[i])
	var _a1: bool = weapon_slot.append(_scratch.weapon_slot[i])
	var _a2: bool = seed_byte.append(_scratch.seed_byte[i])
	var _a3: bool = yaw_q.append(_scratch.yaw_q[i])
	var _a4: bool = pitch_q.append(_scratch.pitch_q[i])
	var _a5: bool = spawn_tick.append(_scratch.tick)
	var _a6: bool = burst_tick.append(-1 if _scratch.fuse[i] < 0 else _scratch.tick + _scratch.fuse[i])


## Appends the indices of flak shells whose burst tick is `now_tick` or earlier to `out`, and removes them.
func take_due_bursts(now_tick: int, out: PackedInt32Array) -> void:
	var i: int = shooter.size() - 1
	while i >= 0:
		if burst_tick[i] >= 0 and burst_tick[i] <= now_tick:
			var _a: bool = out.append(shooter[i] | (seed_byte[i] << 16))
			_remove_at(i)
		i -= 1


## Retires the live shot named by a HIT (attacker roster index + seed). True when one was found.
func remove_hit(attacker_ref: int, seed_value: int) -> bool:
	for i: int in shooter.size():
		if shooter[i] == attacker_ref and seed_byte[i] == seed_value:
			_remove_at(i)
			return true
	return false


## Drops shots older than `max_age_ticks` (max range reached).
func expire(now_tick: int, max_age_ticks: int) -> void:
	var i: int = shooter.size() - 1
	while i >= 0:
		if now_tick - spawn_tick[i] > max_age_ticks:
			_remove_at(i)
		i -= 1


func _remove_at(i: int) -> void:
	shooter.remove_at(i)
	weapon_slot.remove_at(i)
	seed_byte.remove_at(i)
	yaw_q.remove_at(i)
	pitch_q.remove_at(i)
	spawn_tick.remove_at(i)
	burst_tick.remove_at(i)


func _prune_keys(now_tick: int) -> void:
	if _seen.size() < 256:
		return
	for k: int in _seen.keys():
		if now_tick - _seen[k] > KEY_KEEP_TICKS:
			var _e: bool = _seen.erase(k)
