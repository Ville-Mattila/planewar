class_name OrderSpec extends RefCounted
## One order as a value (05 s3.1, R0 B.3, C2-06). Ordinals are frozen and append-only.
## The entity store never holds these per entity: `OrderQueue` packs them into arrays; an OrderSpec
## is the wire/command form and the reused scratch that `OrderQueue.read` fills.

enum Kind { MOVE = 0, PATROL = 1, ATTACK = 2, ESCORT = 3, HARVEST_HERE = 4, HAUL = 5, RETURN = 6, HOLD = 7, GUARD = 8,
		SUPPLY_DROP = 9,     # SL-5, v1 stretch: built only when the C1-13 scope gate opens
		PATROL_ROUTE = 10,   # reserved, v1.x (08 SL-4)
		ATTACK_VIA = 11 }    # reserved, v1.x (08 SL-4)
enum HaulMode { FERRY = 0, TOW = 1, CAPTURE = 2 }
enum EscortMode { FORM = 0, FOCUS = 1, BREAK = 2 }   # SL-2 (v1)

const FLAG_QUEUE: int = 1       # append instead of replace
const FLAG_PREPEND: int = 2     # system use only (forced RETURN); never accepted from clients
const FLAG_LOW: int = 4         # fly the leg in the Deck band (raids)
const FLAGS_CLIENT: int = 5     # QUEUE | LOW

const KIND_COUNT: int = 12
const KIND_RESERVED_FIRST: int = 10
## Lower-case JSON names of the kinds, indexed by ordinal (order_rules.json).
const KIND_NAMES: PackedStringArray = ["move", "patrol", "attack", "escort", "harvest_here", "haul", "return", "hold",
		"guard", "supply_drop", "patrol_route", "attack_via"]
## 04 s2.5 ORDER layout: 8 bytes of header, 4 per id, 8 per point; at most 256 bytes.
const WIRE_HEADER_BYTES: int = 8
const WIRE_MAX_BYTES: int = 256
const WIRE_MAX_POINTS: int = 16
const WIRE_MAX_IDS: int = 32

var kind: Kind = Kind.MOVE
var target: int = 0                     # EntityId or 0 (ESCORT: the leader / escortee)
var point: Vector3 = Vector3.ZERO       # world position; altitude = its own |p| - PLANET_RADIUS
var points: PackedVector3Array = PackedVector3Array()   # PATROL waypoints (2..8 validated; wire allows 0-16)
var haul_mode: HaulMode = HaulMode.FERRY
var escort_slot: int = -1               # SL-2 formation slot; -1 = class default slots (05 s5.6)
var focus: int = 0                      # SL-2 focus target EntityId (EscortMode.FOCUS)
var escort_mode: EscortMode = EscortMode.FORM
var flags: int = 0
var issuer: int = -1                    # player slot, -1 system
var issue_tick: int = 0
var progress: int = 0                   # leg index / cycle phase, preserved across possession


static func make(order_kind: Kind, order_target: int = 0, order_point: Vector3 = Vector3.ZERO, order_flags: int = 0) -> OrderSpec:
	var s: OrderSpec = OrderSpec.new()
	s.kind = order_kind
	s.target = order_target
	s.point = order_point
	s.flags = order_flags
	return s


static func kind_name(k: int) -> String:
	return KIND_NAMES[k] if k >= 0 and k < KIND_COUNT else ""


## Ordinal of a lower-case kind name, -1 if unknown.
static func kind_from_name(n: String) -> int:
	return KIND_NAMES.find(n)


static func is_reserved(k: int) -> bool:
	return k >= KIND_RESERVED_FIRST and k < KIND_COUNT


## Bytes of the 04 ORDER payload for `count` selected ids and `point_count` points.
static func wire_size(count: int, point_count: int) -> int:
	return WIRE_HEADER_BYTES + 4 * count + 8 * point_count


static func fits_wire(count: int, point_count: int) -> bool:
	return count >= 1 and count <= WIRE_MAX_IDS and point_count >= 0 and point_count <= WIRE_MAX_POINTS \
			and wire_size(count, point_count) <= WIRE_MAX_BYTES


func copy_from(o: OrderSpec) -> void:
	kind = o.kind
	target = o.target
	point = o.point
	var _e: int = points.resize(o.points.size())
	for i: int in o.points.size():
		points[i] = o.points[i]
	haul_mode = o.haul_mode
	escort_slot = o.escort_slot
	focus = o.focus
	escort_mode = o.escort_mode
	flags = o.flags
	issuer = o.issuer
	issue_tick = o.issue_tick
	progress = o.progress


func equals(o: OrderSpec) -> bool:
	if kind != o.kind or target != o.target or point != o.point or points != o.points or haul_mode != o.haul_mode:
		return false
	return escort_slot == o.escort_slot and focus == o.focus and escort_mode == o.escort_mode and flags == o.flags \
			and issuer == o.issuer and issue_tick == o.issue_tick and progress == o.progress
