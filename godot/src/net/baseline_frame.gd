class_name BaselineFrame extends RefCounted
## What one client holds for every roster index after a snapshot tick (04 s3.4 baseline rule): quantised
## position (vec3q), full and coarse orientation, fine velocity (DeadReckon, 1/1024 m/s), hp, flags, ai_tag, the last C-BLIP, and the
## tick at which pos/vel are valid (`etick`, the dead-reckoning origin). The server keeps one per client per
## tick as a mirror; the client keeps its own. Both mutate it only through the set_* functions below, so the
## two copies stay bit-identical (codec_delta_test).

const CAPACITY: int = Roster.CAPACITY
## `ori` / `ori_c` after a record of the other form: unknown, so the next record in that form carries ORI.
## (Re-deriving one form from the other costs ~2 us per record; FULL records still derive `ori_c`.)
const ORI_UNKNOWN: int = -1

var tick: int = 0                           # 0 = unused
var base_tick: int = 0                      # the baseline this frame was decoded against
var usable: bool = false                    # server: may serve as a delta baseline once acked (every emitted frame)
var present: PackedByteArray = PackedByteArray()
var pos: PackedInt64Array = PackedInt64Array()
var ori: PackedInt64Array = PackedInt64Array()     # quat_s3 u32
var ori_c: PackedInt32Array = PackedInt32Array()   # coarse 17 bits (no spare)
var vel: PackedInt64Array = PackedInt64Array()     # DeadReckon fine velocity, not wire bits
var hp: PackedByteArray = PackedByteArray()
var flags: PackedByteArray = PackedByteArray()
var ai: PackedByteArray = PackedByteArray()
var blip: PackedInt32Array = PackedInt32Array()
var etick: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var _a: int = present.resize(CAPACITY)
	var _b: int = pos.resize(CAPACITY)
	var _c: int = ori.resize(CAPACITY)
	var _d: int = ori_c.resize(CAPACITY)
	var _e: int = vel.resize(CAPACITY)
	var _f: int = hp.resize(CAPACITY)
	var _g: int = flags.resize(CAPACITY)
	var _h: int = ai.resize(CAPACITY)
	var _i: int = blip.resize(CAPACITY)
	var _j: int = etick.resize(CAPACITY)
	clear(0)


## Empties every entry and tags the frame with tick `t`.
func clear(t: int) -> void:
	tick = t
	base_tick = 0
	usable = true
	present.fill(0)
	pos.fill(0)
	ori.fill(0)
	ori_c.fill(0)
	vel.fill(0)
	hp.fill(0)
	flags.fill(0)
	ai.fill(0)
	blip.fill(DeadReckon.BLIP_UNKNOWN)
	etick.fill(0)


## Copies `src` (packed arrays are shared by reference, so duplicate) and tags the copy with tick `t` and base `src.tick`.
func copy_from(src: BaselineFrame, t: int) -> void:
	tick = t
	base_tick = src.tick
	usable = true
	present = src.present.duplicate()
	pos = src.pos.duplicate()
	ori = src.ori.duplicate()
	ori_c = src.ori_c.duplicate()
	vel = src.vel.duplicate()
	hp = src.hp.duplicate()
	flags = src.flags.duplicate()
	ai = src.ai.duplicate()
	blip = src.blip.duplicate()
	etick = src.etick.duplicate()


## FULL record: every field replaced. `ai_tag` < 0 keeps the stored tag (other team's entity).
func set_full(i: int, t: int, pos_q: int, ori_bits: int, vel_bits: int, hp_b: int, flag_b: int, ai_tag: int) -> void:
	present[i] = 1
	pos[i] = pos_q
	ori[i] = ori_bits & 0xFFFFFFFF
	ori_c[i] = coarse_of_full(ori_bits)
	vel[i] = DeadReckon.fine_from_bits(vel_bits)
	hp[i] = hp_b & 0xFF
	flags[i] = flag_b & 0xFF
	if ai_tag >= 0:
		ai[i] = ai_tag & 0xFF
	blip[i] = DeadReckon.BLIP_UNKNOWN
	etick[i] = t


## set_full with the values it derives passed in (SnapshotCodec's per-tick cache, A-40): `ori_c_bits` =
## coarse_of_full(ori_bits), `fine_vel` = DeadReckon.fine_from_bits(vel bits). Same state as set_full.
func set_full_cached(i: int, t: int, pos_q: int, ori_bits: int, ori_c_bits: int, fine_vel: int, hp_b: int,
		flag_b: int, ai_tag: int) -> void:
	present[i] = 1
	pos[i] = pos_q
	ori[i] = ori_bits & 0xFFFFFFFF
	ori_c[i] = ori_c_bits
	vel[i] = fine_vel
	hp[i] = hp_b & 0xFF
	flags[i] = flag_b & 0xFF
	if ai_tag >= 0:
		ai[i] = ai_tag & 0xFF
	blip[i] = DeadReckon.BLIP_UNKNOWN
	etick[i] = t


## A- or B-DELTA record: `pos_q` / `fine_vel` are the reconstructed values (dead reckoning + residual; the
## sent velocity or DeadReckon.dr_fine when VEL is absent); optional groups by `mask` (SnapshotCodec.MASK_*).
func set_delta(i: int, t: int, tier_b: bool, mask: int, pos_q: int, fine_vel: int, ori_bits: int, hp_b: int,
		flag_b: int, ai_tag: int) -> void:
	pos[i] = pos_q
	vel[i] = fine_vel
	etick[i] = t
	blip[i] = DeadReckon.BLIP_UNKNOWN
	if mask & SnapshotCodec.MASK_ORI:
		if tier_b:
			ori_c[i] = ori_bits & 0x1FFFF
			ori[i] = ORI_UNKNOWN
			flags[i] = Codec.spare_to_flags(Codec.coarse_spare(ori_bits))
		else:
			ori[i] = ori_bits & 0xFFFFFFFF
			ori_c[i] = ORI_UNKNOWN
	if mask & SnapshotCodec.MASK_HP:
		hp[i] = hp_b & 0xFF
	if mask & SnapshotCodec.MASK_FLAGS:
		if not tier_b:
			flags[i] = flag_b & 0xFF
		if ai_tag >= 0:
			ai[i] = ai_tag & 0xFF


## C-BLIP record: position becomes the blip's bucket centre in the stored cell, velocity zero.
func set_blip(i: int, t: int, blip_bits: int) -> void:
	pos[i] = DeadReckon.blip_pos(Codec.pos_cell(pos[i]), blip_bits)
	vel[i] = 0
	blip[i] = blip_bits
	etick[i] = t


## set_blip with the bucket position passed in: `pos_q` = DeadReckon.blip_pos(cell of pos[i], blip_bits).
func set_blip_at(i: int, t: int, blip_bits: int, pos_q: int) -> void:
	pos[i] = pos_q
	vel[i] = 0
	blip[i] = blip_bits
	etick[i] = t


## The blip entry `i` shows at tick `t` (NET-54, server-side encoder rule): the stored blip when known, otherwise
## DeadReckon.entry_blip of its dead reckoning from `etick` (gravity term for `def_grav` or DYING, as the DELTA rule).
func shown_blip(i: int, t: int, def_grav: bool, g: float, dt: float) -> int:
	if blip[i] != DeadReckon.BLIP_UNKNOWN:
		return blip[i]
	var grav: bool = def_grav or (flags[i] & Codec.FLAG_DYING) != 0
	return DeadReckon.entry_blip(pos[i], flags[i], vel[i], t - etick[i], grav, g, dt)


static func coarse_of_full(ori_bits: int) -> int:
	return Codec.quantize_quat_coarse(Codec.dequantize_quat(ori_bits), 0) & 0x1FFFF


## True when every entry (present ones field by field) equals `other`'s.
func same_state(other: BaselineFrame) -> bool:
	return present == other.present and pos == other.pos and ori == other.ori and ori_c == other.ori_c \
			and vel == other.vel and hp == other.hp and flags == other.flags and ai == other.ai \
			and blip == other.blip and etick == other.etick


func state_hash() -> int:
	return hash([present, pos, ori, ori_c, vel, hp, flags, ai, blip, etick])
