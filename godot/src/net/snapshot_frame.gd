class_name SnapshotFrame extends RefCounted
## One tick of authoritative entity state handed to SnapshotCodec.prepare_tick (04 s3.4, R0 C1-02), as plain
## parallel arrays indexed 0..count-1. `slot` is the sim slot: 0-1,535 for units / structures / wrecks, 4,096-6,143 for
## projectiles (set_projectile); prepare_tick and Interest read the roster index through `index_of_row` (R0 B.22 A-112).
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
## Entity generation per row (EntityId.gen; 0 = unknown). Interest (NET-08) re-sends ENTITY_META when a slot's
## generation changes; the codec ignores it.
var gen: PackedInt32Array = PackedInt32Array()
## Projectile rows (R0 B.22 A-112): ProjectileStore.kind (mirrored below, pinned by test_projectile_roster.gd), the shooter
## and target EntityIds (0 none). Only BOMB / ROCKET / SIEGE_SHELL / CANISTER rows are replicated entities (04 s3.6).
var kind: PackedByteArray = PackedByteArray()
var shooter: PackedInt32Array = PackedInt32Array()
var target: PackedInt32Array = PackedInt32Array()

const SLUG: int = 0                         ## ProjectileStore.kind ordinals (sim/MODULE.md)
const BOMB: int = 1
const ROCKET: int = 2
const FLAK: int = 3
const RAIL: int = 4
const SIEGE_SHELL: int = 5
const CANISTER: int = 6
const REPLICATED_KINDS: int = (1 << BOMB) | (1 << ROCKET) | (1 << SIEGE_SHELL) | (1 << CANISTER)


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
	var _l: int = gen.resize(count)
	var e: int = kind.resize(count) | shooter.resize(count) | target.resize(count)
	assert(e == OK)


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
	kind[i] = 0
	shooter[i] = 0
	target[i] = 0


## Fills row i with a projectile entity: `slot_id` 4,096-6,143, `projectile_kind` = ProjectileStore.kind, `team_id` =
## the shooter's team, `has_gravity` = the ProjectileDef's gravity (bomb, siege shell: 04 s3.4 gravity branch), identity
## orientation, hp 0, flags 0, no own visibility bits (V follows team, shooter and target, 04 s4.1).
func set_projectile(i: int, slot_id: int, projectile_kind: int, p: Vector3, v: Vector3, team_id: int, has_gravity: bool,
		shooter_id: int, target_id: int, generation: int) -> void:
	set_entity(i, slot_id, p, v, Quaternion.IDENTITY, 0.0, 0, team_id, 0, has_gravity, 0)
	kind[i] = projectile_kind & 0xFF
	shooter[i] = shooter_id
	target[i] = target_id
	gen[i] = generation


## True for the ProjectileStore kinds that are replicated entities (bomb, rocket, siege shell, canister; never slug,
## flak or rail, 04 s3.6 bullet 1).
static func replicated_kind(projectile_kind: int) -> bool:
	return projectile_kind >= 0 and projectile_kind < 8 and ((REPLICATED_KINDS >> projectile_kind) & 1) != 0


## Roster index of row i (Roster.index_of_slot), or -1 when its slot is outside every roster or it is a projectile of a
## kind that is never replicated.
func index_of_row(i: int) -> int:
	var s: int = Roster.index_of_slot(slot[i])
	if s >= Roster.PROJECTILE_INDEX_MIN and ((REPLICATED_KINDS >> (kind[i] & 7)) & 1) == 0:
		return -1
	return s
