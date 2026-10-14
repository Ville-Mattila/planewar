class_name ShotBuffer extends RefCounted
## Straight-line shots of one tick (gun slugs, flak shells, rail slugs; R0 C2-35) as packed arrays. The server
## fills it from combat (`add`), `PROJECTILE_BATCH` decoding fills it with roster indices in `shooter`. Direction is
## kept quantised (yaw / pitch i8 around the weapon boresight, `ProjectileBatch.DIR_STEP_RAD`); `fuse` is the flak
## burst time in ticks, -1 for none.

var tick: int = 0
var count: int = 0
var shooter: PackedInt32Array = PackedInt32Array()   # EntityId on the server, roster index after decode
var weapon_slot: PackedInt32Array = PackedInt32Array()
var seed_byte: PackedInt32Array = PackedInt32Array()
var yaw_q: PackedInt32Array = PackedInt32Array()
var pitch_q: PackedInt32Array = PackedInt32Array()
var fuse: PackedInt32Array = PackedInt32Array()


func clear(for_tick: int = 0) -> void:
	tick = for_tick
	count = 0
	shooter.clear()
	weapon_slot.clear()
	seed_byte.clear()
	yaw_q.clear()
	pitch_q.clear()
	fuse.clear()


## Appends a shot with an already quantised direction.
func add_q(who: int, slot: int, seed_value: int, yaw: int, pitch: int, fuse_ticks: int = -1) -> void:
	var _a0: bool = shooter.append(who)
	var _a1: bool = weapon_slot.append(slot & 0x7F)
	var _a2: bool = seed_byte.append(seed_value & 0xFF)
	var _a3: bool = yaw_q.append(yaw)
	var _a4: bool = pitch_q.append(pitch)
	var _a5: bool = fuse.append(-1 if fuse_ticks < 0 else mini(fuse_ticks, 255))
	count += 1


## Appends a shot, quantising `dir` against `boresight` (x right, y up, z forward; ProjectileBatch.quantize_*).
func add(who: int, slot: int, seed_value: int, boresight: Basis, dir: Vector3, fuse_ticks: int = -1) -> void:
	add_q(who, slot, seed_value, ProjectileBatch.quantize_yaw(boresight, dir),
			ProjectileBatch.quantize_pitch(boresight, dir), fuse_ticks)
