class_name ShotRouter extends RefCounted
## Per-client PROJECTILE_BATCH assembly (R0 C2-35): only shots whose shooter is in the client's roster are sent,
## each batch goes out on the tick it was fired and once more on the next tick (loss tolerance; the client dedupes
## by (shooter, seed, tick), `ShotTracker`). Packets split at COUNT_MAX items so none exceeds 1,200 B.

var _refs: PackedInt32Array = PackedInt32Array()


## Appends the previous tick's packets, then this tick's, to `aud.shot_out`; remembers this tick's for the re-send.
func route(tick: int, shots: ShotBuffer, aud: EventAudience) -> void:
	for p: PackedByteArray in aud.shots_last:
		aud.shot_out.append(p)
	var fresh: Array[PackedByteArray] = []
	var _r: int = _refs.resize(shots.count)
	var picked: PackedInt32Array = PackedInt32Array()
	for i: int in shots.count:
		var ref: int = EventRouter.ref_of(shots.shooter[i], aud)
		if ref != EventCodec.NONE_REF:
			_refs[i] = ref
			var _a0: bool = picked.append(i)
	var at: int = 0
	while at < picked.size():
		var to: int = mini(at + ProjectileBatch.COUNT_MAX, picked.size())
		fresh.append(_encode_picked(tick, shots, picked, at, to))
		at = to
	for p: PackedByteArray in fresh:
		aud.shot_out.append(p)
	aud.shots_last = fresh


func _encode_picked(tick: int, shots: ShotBuffer, picked: PackedInt32Array, from: int, to: int) -> PackedByteArray:
	var sub: ShotBuffer = ShotBuffer.new()
	var refs: PackedInt32Array = PackedInt32Array()
	for k: int in range(from, to):
		var i: int = picked[k]
		sub.add_q(shots.shooter[i], shots.weapon_slot[i], shots.seed_byte[i], shots.yaw_q[i], shots.pitch_q[i], shots.fuse[i])
		var _a1: bool = refs.append(_refs[i])
	return ProjectileBatch.encode(tick, sub, refs, 0, sub.count)
