class_name OrderResolver extends RefCounted
## Pure tap / RMB / X -> Command resolver (docs/06 s7.2, R0 C2-06). The caller classifies the target under the
## cursor and each selected entity; this maps the pair to ORDER / SET_RALLY commands. Units a rule does not
## cover get no command, so a mixed selection never sends an order the sim would reject as NOT_ALLOWED.
## Towers accept ATTACK, HOLD, GUARD only (HOLD is a button, not a tap).

enum Target { NEUTRAL, ENEMY, FRIENDLY_PAD, RELAY_STATION, FRIENDLY_UNIT, FRIENDLY_STRUCTURE, ORE_FIELD, ICE_EXTRACTOR, WRECK, GROUND }
## FRIENDLY_PAD = friendly Pad, Hangar, Core or Outpost.
enum Sel { SHIP_ARMED, SHIP_UNARMED, HARVESTER, HAULER, GROUND_ARMED, GROUND_UNARMED, FACTORY, TOWER }

const NONE: int = -1
const RALLY: int = -2


static func is_ship(s: Sel) -> bool:
	return s == Sel.SHIP_ARMED or s == Sel.SHIP_UNARMED or s == Sel.HARVESTER or s == Sel.HAULER


static func is_armed(s: Sel) -> bool:
	return s == Sel.SHIP_ARMED or s == Sel.GROUND_ARMED


static func is_mobile(s: Sel) -> bool:
	return is_ship(s) or s == Sel.GROUND_ARMED or s == Sel.GROUND_UNARMED


## Order kind for one selected entity (OrderSpec.Kind, RALLY for SET_RALLY, NONE for no command).
## `any_armed`: the selection holds an armed unit (decides attack vs move on an enemy).
static func plan_kind(target: Target, sel: Sel, any_armed: bool) -> int:
	if sel == Sel.TOWER:
		return _tower_kind(target)
	if sel == Sel.FACTORY:
		return RALLY if target == Target.GROUND else NONE
	if target == Target.ENEMY:
		return OrderSpec.Kind.ATTACK if any_armed else OrderSpec.Kind.MOVE
	if target == Target.GROUND:
		return OrderSpec.Kind.MOVE
	if not is_ship(sel):
		return _ground_unit_kind(target)
	return _ship_kind(target, sel)


static func plan_haul_mode(target: Target) -> OrderSpec.HaulMode:
	match target:
		Target.WRECK:
			return OrderSpec.HaulMode.TOW
		Target.RELAY_STATION:
			return OrderSpec.HaulMode.CAPTURE
	return OrderSpec.HaulMode.FERRY


static func _tower_kind(target: Target) -> int:
	if target == Target.ENEMY:
		return OrderSpec.Kind.ATTACK
	if target == Target.FRIENDLY_PAD or target == Target.RELAY_STATION or target == Target.FRIENDLY_UNIT or target == Target.FRIENDLY_STRUCTURE:
		return OrderSpec.Kind.GUARD
	return NONE


static func _ground_unit_kind(target: Target) -> int:
	match target:
		Target.FRIENDLY_PAD, Target.RELAY_STATION, Target.FRIENDLY_UNIT, Target.FRIENDLY_STRUCTURE:
			return OrderSpec.Kind.MOVE
	return NONE


static func _ship_kind(target: Target, sel: Sel) -> int:
	match target:
		Target.FRIENDLY_PAD:
			return OrderSpec.Kind.RETURN
		Target.RELAY_STATION:
			return OrderSpec.Kind.HAUL if sel == Sel.HAULER else OrderSpec.Kind.GUARD
		Target.FRIENDLY_UNIT:
			return OrderSpec.Kind.ESCORT
		Target.FRIENDLY_STRUCTURE:
			return OrderSpec.Kind.GUARD
		Target.ORE_FIELD:
			return OrderSpec.Kind.HARVEST_HERE if sel == Sel.HARVESTER else NONE
		Target.ICE_EXTRACTOR, Target.WRECK:
			return OrderSpec.Kind.HAUL if sel == Sel.HAULER else NONE
	return NONE


## Commands for a tap on `target` (entity `target_id` at `target_pos`; id 0 for the ground) with the selection
## `ids` classified by `kinds` (parallel). `queue` sets the QUEUE flag (shift / selection-bar toggle).
static func resolve(player: int, target: Target, target_id: int, target_pos: Vector3, ids: PackedInt32Array, kinds: Array[Sel], queue: bool = false) -> Array[Command]:
	var out: Array[Command] = []
	var any_armed: bool = false
	for k: Sel in kinds:
		any_armed = any_armed or is_armed(k)
	var flags: int = OrderSpec.FLAG_QUEUE if queue else 0
	var groups: Dictionary = {}   # key = kind * 4 + haul_mode -> PackedInt32Array
	var order_keys: Array[int] = []
	for i: int in ids.size():
		var kind: int = plan_kind(target, kinds[i], any_armed)
		if kind == NONE:
			continue
		if kind == RALLY:
			out.append(Command.set_rally(player, ids[i], target_pos))
			continue
		var key: int = kind * 4 + plan_haul_mode(target) if kind == OrderSpec.Kind.HAUL else kind * 4
		if not groups.has(key):
			groups[key] = PackedInt32Array()
			order_keys.append(key)
		var g: PackedInt32Array = groups[key]
		var _a: bool = g.append(ids[i])
		groups[key] = g
	for key: int in order_keys:
		var spec: OrderSpec = _spec(key >> 2, key & 3,target_id, target_pos, flags)
		var g: PackedInt32Array = groups[key]
		for c: int in range(0, g.size(), OrderSpec.WIRE_MAX_IDS):
			out.append(Command.order(player, g.slice(c, c + OrderSpec.WIRE_MAX_IDS), spec))
	return out


## SUPPLY button (SL-5): ORDER supply_drop(target) for the commander `ids`.
static func resolve_supply(player: int, target_id: int, ids: PackedInt32Array, queue: bool = false) -> Array[Command]:
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.SUPPLY_DROP, target_id, Vector3.ZERO, OrderSpec.FLAG_QUEUE if queue else 0)
	var out: Array[Command] = []
	for c: int in range(0, ids.size(), OrderSpec.WIRE_MAX_IDS):
		out.append(Command.order(player, ids.slice(c, c + OrderSpec.WIRE_MAX_IDS), spec))
	return out


static func _spec(kind: int, haul: int, target_id: int, pos: Vector3, flags: int) -> OrderSpec:
	var k: OrderSpec.Kind = kind as OrderSpec.Kind
	var spec: OrderSpec
	if k == OrderSpec.Kind.MOVE:
		spec = OrderSpec.make(k, 0, pos, flags)
	else:
		spec = OrderSpec.make(k, target_id, Vector3.ZERO, flags)
	if k == OrderSpec.Kind.HAUL:
		spec.haul_mode = haul as OrderSpec.HaulMode
	return spec
