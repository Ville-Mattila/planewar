class_name OrderRules extends RefCounted
## Validity of an order and the tunable numbers of 05 s3.2-3.3, read from order_rules.json (OrderRulesDef.raw).
## `validate` is the single structural + per-class check that 04 V-ORD and the sim's command intake share; it
## does not look at the world (target liveness, team and visibility are checked by the caller against SimView).

enum Verdict { OK, UNKNOWN_KIND, RESERVED_KIND, DISABLED_KIND, NOT_ALLOWED, BAD_FLAGS, BAD_POINTS, BAD_HAUL_MODE, BAD_ESCORT }

var queue_max: int = OrderQueue.QUEUE_MAX
var patrol_points_min: int = 2
var patrol_points_max: int = 8
var arrival_radius_ship_m: float = 0.0
var arrival_radius_ground_m: float = 0.0
var default_move_agl_m: float = 0.0
var ghost_timeout_s: float = 0.0
var attack_gun_duration_s: float = 0.0
var patrol_engage_radius_m: float = 0.0
var escort_engage_radius_m: float = 0.0
var hold_orbit_radius_m: float = 0.0
var guard_orbit_radius_m: float = 0.0
var guard_engage_radius_m: float = 0.0
var haul_defended_fail_s: float = 0.0
var no_pad_loiter_altitude_m: float = 0.0
var no_pad_retry_s: float = 0.0
var escort_slot_max: int = 0

var _enabled: int = 0                          # bit per OrderSpec.Kind
var _by_key: Dictionary = {}                   # allowed_kinds key (StringName) -> kind bitmask
var _mask: PackedInt32Array = PackedInt32Array()   # def_id -> kind bitmask, filled by bind()


static func from_def(d: OrderRulesDef) -> OrderRules:
	var r: OrderRules = OrderRules.new()
	var raw: Dictionary = d.raw
	r.queue_max = clampi(roundi(Def.num(raw.get("queue_max", OrderQueue.QUEUE_MAX))), 1, OrderQueue.QUEUE_MAX)
	var pp: Dictionary = raw.get("patrol_points", {})
	r.patrol_points_min = roundi(Def.num(pp.get("min", 2)))
	r.patrol_points_max = roundi(Def.num(pp.get("max", 8)))
	r.arrival_radius_ship_m = Def.num(raw.get("arrival_radius_ship_m", 0.0))
	r.arrival_radius_ground_m = Def.num(raw.get("arrival_radius_ground_m", 0.0))
	r.default_move_agl_m = Def.num(raw.get("default_move_agl_m", 0.0))
	r.ghost_timeout_s = Def.num(raw.get("ghost_timeout_s", 0.0))
	r.attack_gun_duration_s = Def.num(raw.get("attack_gun_duration_s", 0.0))
	r.patrol_engage_radius_m = Def.num(raw.get("patrol_engage_radius_m", 0.0))
	r.escort_engage_radius_m = Def.num(raw.get("escort_engage_radius_m", 0.0))
	r.hold_orbit_radius_m = Def.num(raw.get("hold_orbit_radius_m", 0.0))
	r.guard_orbit_radius_m = Def.num(raw.get("guard_orbit_radius_m", 0.0))
	r.guard_engage_radius_m = Def.num(raw.get("guard_engage_radius_m", 0.0))
	r.haul_defended_fail_s = Def.num(raw.get("haul_defended_fail_s", 0.0))
	r.no_pad_loiter_altitude_m = Def.num(raw.get("no_pad_loiter_altitude_m", 0.0))
	r.no_pad_retry_s = Def.num(raw.get("no_pad_retry_s", 0.0))
	r.escort_slot_max = roundi(Def.num(raw.get("escort_slot_max", 0)))
	r._enabled = _mask_of(raw.get("enabled_kinds", []))
	var allowed: Dictionary = raw.get("allowed_kinds", {})
	for key: Variant in allowed.keys():
		r._by_key[StringName(str(key))] = _mask_of(allowed[key])
	return r


## Resolves allowed kinds per def id: a ship or ground unit by its id, a structure by its id or, when it has a
## tower block, by the shared "tower" key; structures with neither accept no orders. Call once at load_map.
func bind(ships: Array[ShipDef], ground: Array[GroundUnitDef], structures: Array[StructureDef]) -> void:
	var _e: int = _mask.resize(DefRanges.END)
	_mask.fill(0)
	for i: int in ships.size():
		_mask[DefRanges.SHIP_BASE + i] = _get_mask(ships[i].id)
	for i: int in ground.size():
		_mask[DefRanges.GROUND_BASE + i] = _get_mask(ground[i].id)
	for i: int in structures.size():
		var s: StructureDef = structures[i]
		var m: int = _get_mask(s.id)
		if not s.tower.is_empty():
			m |= _get_mask(&"tower")
		_mask[DefRanges.STRUCTURE_BASE + i] = m


## True when `kind` is enabled and the class of `def_id` accepts it.
func allows(kind: int, def_id: int) -> bool:
	if kind < 0 or kind >= OrderSpec.KIND_COUNT or def_id < 0 or def_id >= _mask.size():
		return false
	return (_enabled & _mask[def_id] & (1 << kind)) != 0


func kind_enabled(kind: int) -> bool:
	return kind >= 0 and kind < OrderSpec.KIND_COUNT and (_enabled & (1 << kind)) != 0


## Structure and class check of `spec` for an entity of `def_id`; `from_client` also rejects FLAG_PREPEND.
## OK is the only accepted verdict. Map malformed() verdicts to REJECTED_MALFORMED, the rest to REJECTED_INVALID_ORDER.
func validate(spec: OrderSpec, def_id: int, from_client: bool) -> Verdict:
	var k: int = spec.kind
	if k < 0 or k >= OrderSpec.KIND_COUNT:
		return Verdict.UNKNOWN_KIND
	if OrderSpec.is_reserved(k):
		return Verdict.RESERVED_KIND
	if not kind_enabled(k):
		return Verdict.DISABLED_KIND
	var bad: int = _structure_verdict(spec, k, from_client)
	if bad != Verdict.OK:
		return bad as Verdict
	return Verdict.OK if allows(k, def_id) else Verdict.NOT_ALLOWED


static func malformed(v: Verdict) -> bool:
	return v == Verdict.BAD_FLAGS or v == Verdict.BAD_POINTS or v == Verdict.BAD_HAUL_MODE or v == Verdict.UNKNOWN_KIND


func _structure_verdict(spec: OrderSpec, k: int, from_client: bool) -> int:
	var allowed_flags: int = OrderSpec.FLAGS_CLIENT if from_client else OrderSpec.FLAGS_CLIENT | OrderSpec.FLAG_PREPEND
	if (spec.flags & ~allowed_flags) != 0 or ((spec.flags & OrderSpec.FLAG_QUEUE) != 0 and (spec.flags & OrderSpec.FLAG_PREPEND) != 0):
		return Verdict.BAD_FLAGS
	var np: int = spec.points.size()
	if k == OrderSpec.Kind.PATROL:
		if np < patrol_points_min or np > patrol_points_max:
			return Verdict.BAD_POINTS
	elif np != 0:
		return Verdict.BAD_POINTS
	if spec.haul_mode != OrderSpec.HaulMode.FERRY and k != OrderSpec.Kind.HAUL:
		return Verdict.BAD_HAUL_MODE
	if k == OrderSpec.Kind.ESCORT:
		if spec.escort_slot < -1 or spec.escort_slot > escort_slot_max:
			return Verdict.BAD_ESCORT
	elif spec.escort_slot != -1 or spec.focus != 0 or spec.escort_mode != OrderSpec.EscortMode.FORM:
		return Verdict.BAD_ESCORT
	return Verdict.OK


func _get_mask(key: StringName) -> int:
	var m: int = _by_key.get(key, 0)
	return m


static func _mask_of(names: Variant) -> int:
	var m: int = 0
	if typeof(names) == TYPE_ARRAY:
		var arr: Array = names
		for n: Variant in arr:
			var k: int = OrderSpec.kind_from_name(str(n))
			m |= (1 << k) if k >= 0 else 0
	return m
