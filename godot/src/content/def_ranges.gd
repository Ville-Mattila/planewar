class_name DefRanges extends RefCounted
## def_id ranges (N2). kind_of is pure arithmetic.

const SHIP_BASE: int = 0
const GROUND_BASE: int = 256
const STRUCTURE_BASE: int = 512  ## structures then towers
const WEAPON_BASE: int = 1024
const PROJECTILE_BASE: int = 1280
const END: int = 1536

const K_NONE: int = -1
const K_SHIP: int = 0
const K_GROUND: int = 1
const K_STRUCTURE: int = 2
const K_WEAPON: int = 3
const K_PROJECTILE: int = 4

const _BASES: PackedInt32Array = [SHIP_BASE, GROUND_BASE, STRUCTURE_BASE, WEAPON_BASE, PROJECTILE_BASE, END]
const _SIZES: PackedInt32Array = [256, 256, 512, 256, 256]


static func kind_of(def_id: int) -> int:
	if def_id < SHIP_BASE or def_id >= END:
		return K_NONE
	if def_id < GROUND_BASE:
		return K_SHIP
	if def_id < STRUCTURE_BASE:
		return K_GROUND
	if def_id < WEAPON_BASE:
		return K_STRUCTURE
	if def_id < PROJECTILE_BASE:
		return K_WEAPON
	return K_PROJECTILE


static func base_of(kind: int) -> int:
	return _BASES[kind]


static func size_of(kind: int) -> int:
	return _SIZES[kind]
