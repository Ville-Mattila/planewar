class_name SnapshotFrame extends RefCounted
## One tick of authoritative entity state handed to SnapshotCodec.prepare_tick (04 s3.4, R0 C1-02), as plain
## parallel arrays indexed 0..count-1. `slot` is the sim slot == roster index (04 s3.1, < Roster.CAPACITY).
## `flags` is the wire flags byte (Codec.make_flags); `gravity` is 1 for gravity-bearing defs (bomb, siege
## shell; 04 s3.4 dead reckoning); `visible_mask` bit t = visible to team t (own team is always implied);
## `under_fire` feeds the C-BLIP state. The SimView adapter that fills it lands with ServerSession (NET-15):
## `SimView` is still planned in sim/MODULE.md, so the codec takes the named data, not the view.

var tick: int = 0
var count: int = 0
var slot: PackedInt32Array = PackedInt32Array()
var pos: PackedVector3Array = PackedVector3Array()
var vel: PackedVector3Array = PackedVector3Array()
var rot: PackedVector4Array = PackedVector4Array()     # quaternion x, y, z, w
var hp01: PackedFloat32Array = PackedFloat32Array()
var flags: PackedByteArray = PackedByteArray()
var ai_tag: PackedByteArray = PackedByteArray()
var team: PackedByteArray = PackedByteArray()
var gravity: PackedByteArray = PackedByteArray()
var under_fire: PackedByteArray = PackedByteArray()
var visible_mask: PackedInt32Array = PackedInt32Array()


## Sets count and sizes every array; new rows are zero.
func resize(n: int) -> void:
	count = maxi(n, 0)
	var _a: int = slot.resize(count)
	var _b: int = pos.resize(count)
	var _c: int = vel.resize(count)
	var _d: int = rot.resize(count)
	var _e: int = hp01.resize(count)
	var _f: int = flags.resize(count)
	var _g: int = ai_tag.resize(count)
	var _h: int = team.resize(count)
	var _i: int = gravity.resize(count)
	var _j: int = under_fire.resize(count)
	var _k: int = visible_mask.resize(count)


## Fills row i. `visible` is the team bitmask (0 = own team only).
func set_entity(i: int, slot_id: int, p: Vector3, v: Vector3, q: Quaternion, hp: float, flag_byte: int,
		team_id: int, tag: int = 0, has_gravity: bool = false, visible: int = 0) -> void:
	slot[i] = slot_id
	pos[i] = p
	vel[i] = v
	rot[i] = Vector4(q.x, q.y, q.z, q.w)
	hp01[i] = hp
	flags[i] = flag_byte & 0xFF
	team[i] = team_id & 0xFF
	ai_tag[i] = tag & 0xFF
	gravity[i] = 1 if has_gravity else 0
	under_fire[i] = 0
	visible_mask[i] = visible
