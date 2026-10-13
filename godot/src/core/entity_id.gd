class_name EntityId
## EntityId packing (03 s3.1): slot in bits 0-19, generation in bits 20-31.
## Slot 0 is reserved; NULL_ID == 0. Generation runs 1..4095 and wraps 4095 -> 1.

const NULL_ID: int = 0
const SLOT_MASK: int = 0xFFFFF
const GEN_MASK: int = 0xFFF
const GEN_SHIFT: int = 20
const GEN_MAX: int = 4095
const PROJECTILE_SLOT_MIN: int = 4096
## Exclusive end of the projectile slot range (03 s3.1: 4,096 .. 6,143; R0 B.9 A-20).
const PROJECTILE_SLOT_END: int = 6144
const WRECK_SLOT_MIN: int = 1280
const WRECK_SLOT_END: int = 1536


static func make(slot_index: int, gen_value: int) -> int:
	return (slot_index & SLOT_MASK) | ((gen_value & GEN_MASK) << GEN_SHIFT)


static func slot(id: int) -> int:
	return id & SLOT_MASK


static func gen(id: int) -> int:
	return (id >> GEN_SHIFT) & GEN_MASK


## Next generation after g: 1..4095, wrapping 4095 -> 1 (never 0).
static func bump_gen(g: int) -> int:
	return 1 if g >= GEN_MAX else g + 1


static func is_projectile(id: int) -> bool:
	return slot(id) >= PROJECTILE_SLOT_MIN


static func is_wreck(id: int) -> bool:
	var s: int = slot(id)
	return s >= WRECK_SLOT_MIN and s < WRECK_SLOT_END
