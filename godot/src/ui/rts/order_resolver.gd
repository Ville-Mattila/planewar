class_name OrderResolver extends RefCounted
## Pure tap / RMB / X -> Command resolver (docs/06 s7.2, R0 C2-06). The caller classifies the target under the
## cursor; each selected id is classified by its class key (def id, towers &"tower"). Every kind is filtered
## through OrderClassRules (order_rules.json): the sim rejects a whole ORDER if any id's class disallows the
## kind, so a unit that cannot take a kind gets no command. order_rules.json wins over 06 s7.2 where they
## differ (Harvester return/guard, Bomber escort). HOLD is a button, not a tap.

enum Target { NEUTRAL, ENEMY, FRIENDLY_PAD, RELAY_STATION, FRIENDLY_UNIT, FRIENDLY_STRUCTURE, ORE_FIELD, ICE_EXTRACTOR, WRECK, GROUND }
## FRIENDLY_PAD = friendly Pad, Hangar, Core or Outpost.

const NONE: int = -1
const RALLY: int = -2


## Order kind for one selected class (OrderSpec.Kind, RALLY for SET_RALLY, NONE for no command).
## `any_attacker`: the selection holds a class that may ATTACK (decides attack vs move on an enemy).
static func plan_kind(rules: OrderClassRules, target: Target, cls: StringName, any_attacker: bool) -> int:
	var want: int = _wanted(rules, target, cls, any_attacker)
	if want == NONE or want == RALLY:
		return want
	return want if rules.allows(want, cls) else NONE


static func plan_haul_mode(target: Target) -> OrderSpec.HaulMode:
	match target:
		Target.WRECK:
			return OrderSpec.HaulMode.TOW
		Target.RELAY_STATION:
			return OrderSpec.HaulMode.CAPTURE
	return OrderSpec.HaulMode.FERRY


static func _wanted(rules: OrderClassRules, target: Target, cls: StringName, any_attacker: bool) -> int:
	match target:
		Target.ENEMY:
			if any_attacker:
				return OrderSpec.Kind.ATTACK
			return OrderSpec.Kind.MOVE
		Target.GROUND:
			return RALLY if rules.is_rally_class(cls) else OrderSpec.Kind.MOVE
		Target.FRIENDLY_PAD:
			return OrderSpec.Kind.RETURN
		Target.RELAY_STATION:
			return OrderSpec.Kind.HAUL if rules.allows(OrderSpec.Kind.HAUL, cls) else OrderSpec.Kind.GUARD
		Target.FRIENDLY_UNIT:
			return OrderSpec.Kind.ESCORT
		Target.FRIENDLY_STRUCTURE:
			return OrderSpec.Kind.GUARD
		Target.ORE_FIELD:
			return OrderSpec.Kind.HARVEST_HERE
		Target.ICE_EXTRACTOR, Target.WRECK:
			return OrderSpec.Kind.HAUL
	return NONE


## Commands for a tap on `target` (entity `target_id` at `target_pos`; id 0 for the ground) with the selection
## `ids` and their class keys `classes` (parallel). `queue` sets the QUEUE flag (shift / selection-bar toggle).
static func resolve(player: int, rules: OrderClassRules, target: Target, target_id: int, target_pos: Vector3, ids: PackedInt32Array, classes: Array[StringName], queue: bool = false) -> Array[Command]:
	var out: Array[Command] = []
	var any_attacker: bool = false
	for c: StringName in classes:
		any_attacker = any_attacker or rules.allows(OrderSpec.Kind.ATTACK, c)
	var flags: int = OrderSpec.FLAG_QUEUE if queue else 0
	var groups: Dictionary = {}   # kind * 4 + haul mode -> PackedInt32Array
	var order_keys: Array[int] = []
	for i: int in ids.size():
		var kind: int = plan_kind(rules, target, classes[i], any_attacker)
		if kind == NONE:
			continue
		if kind == RALLY:
			out.append(Command.set_rally(player, ids[i], target_pos))
			continue
		var key: int = kind * 4
		if kind == OrderSpec.Kind.HAUL:
			key += plan_haul_mode(target)
		if not groups.has(key):
			groups[key] = PackedInt32Array()
			order_keys.append(key)
		var g: PackedInt32Array = groups[key]
		var _a: bool = g.append(ids[i])
		groups[key] = g
	for key: int in order_keys:
		var spec: OrderSpec = _spec(key >> 2, key & 3, target_id, target_pos, flags)
		var g: PackedInt32Array = groups[key]
		for c: int in range(0, g.size(), OrderSpec.WIRE_MAX_IDS):
			out.append(Command.order(player, g.slice(c, c + OrderSpec.WIRE_MAX_IDS), spec))
	return out


## SUPPLY button (SL-5): ORDER supply_drop(target) for the commander `ids`. supply_drop is off in
## order_rules.json until the C1-13 scope gate, so the sim rejects it until then.
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
