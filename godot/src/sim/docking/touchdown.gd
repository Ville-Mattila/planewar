class_name Touchdown extends RefCounted
## The landing of 03 s6.4 / R0 B.5 (GD-15), run by `Docking.land` at the end of step 9 (after Combat, before the deferred
## deaths, so a crash dies this tick like a ram) on every PAD contact of step 8 (A-31: each tick a not-DOCKED ship is in
## a friendly pad volume). The pad must be a finished service pad (`pad_radius_m` > 0, not BUILDING) that is free: no
## ship docked on it and no queue, or this ship at the queue head (`PadQueue`); otherwise the ship holds (nothing
## happens) unless its band is DESTROY. A landing, in this order: grade inputs from the contact (v_vert, v_horiz,
## tilt, offset), manual (`PilotTrack`), hot (an enemy ship within `hot_radius_m` of the pad, or a hit within
## `hot_window_s`), dead stick (fuel01 < `dead_stick_fuel01`); then the band: DAMAGE takes `hp_max * max(ratio_vert,
## ratio_hor, ratio_tilt)`, ratio = clamp((x - safe) / (damage - safe), 0, 1) through `DamageSink` (HIT), DESTROY
## destroys the ship; `LandingGrade` grades it (a hull emptied by the damage band grades CRASH) into `LandingLog`; the
## LANDING event (a ship, b pad, value q, extra = grade, round(q * 255), flags bit0 manual, bit1 hot, bit2 dead stick,
## v_vert and v_horiz in 0.1 m/s clamped to 0..255); a ship that survives docks: DOCKED | LANDED, `vel` and `rates` 0,
## `pos` on the socket `pad.pos + pad.up * radius` (A-82), nose along the pad normal, body up = its old up in the pad
## plane, `link` = pad, a new service stay, the DOCKED event. A CRASH (DESTROY band, or a hull emptied by the damage
## band) first deals `flight_common.crash_pad_damage` to the pad through `DamageSink` (HIT, attacker = the ship; 02 s2.2,
## R0 B.24 A-120). A contact whose ship moves up the pad normal (`vel . up > 0`, strictly) is a launch leaving the pad
## volume and is never judged (R0 B.24 A-119); exactly 0 lands.

const _PER_MPS: int = 10    ## 04 s3.6 LANDING speed unit 0.1 m/s (a unit, not a tunable)
const _Q_MAX: int = 255     ## 04 s3.6 LANDING q byte = round(q * 255)

var landed: int = 0                     ## landings resolved in the last `land` call (perf counter, not state)

var _store: EntityStore
var _defs: WorldDefs
var _events: SimEvents
var _sink: DamageSink
var _queue: PadQueue
var _service: PadService
var _log: LandingLog
var _grade: LandingGrade
var _pilots: PilotTrack
var _hz: int = 30
var _pad_dmg: float = 0.0                ## flight_common.crash_pad_damage (A-120)
var _occ: PackedInt32Array = PackedInt32Array()   ## per entity slot (scratch per call): ship docked on that pad, 0 none


func _init(store: EntityStore, defs: WorldDefs, events: SimEvents, sink: DamageSink, queue: PadQueue, service: PadService,
		landings: LandingLog, grade: LandingGrade, pilots: PilotTrack, hz: int) -> void:
	_store = store
	_defs = defs
	_events = events
	_sink = sink
	_queue = queue
	_service = service
	_log = landings
	_grade = grade
	_pilots = pilots
	_hz = hz
	_pad_dmg = Def.num(defs.common.raw.get("crash_pad_damage", 0.0)) if defs.common != null else 0.0   # needs content: typed field
	var e: int = _occ.resize(InputSlots.ENTITY_SLOTS)
	assert(e == OK)
	_occ.fill(0)


## Every PAD contact of `collision`'s last step, in contact order (ascending ship slot).
func land(t: int, collision: Collision) -> void:
	landed = 0
	var any: bool = false
	for k: int in collision.contact_count:
		if collision.c_kind[k] == Collision.C_PAD:
			if not any:
				any = true
				_occupancy()
			_contact(collision, k, t)


# Which ship is docked on which pad (any DOCKED ship with a live link), from the store: one pass over the ships on a
# tick with a PAD contact (a landing tick, or a ship holding over a busy pad).
func _occupancy() -> void:
	_occ.fill(0)
	var flags: PackedByteArray = _store.flags
	var links: PackedInt32Array = _store.link
	for s: int in _store.ships:
		if (flags[s] & EntityStore.F_DOCKED) != 0 and _store.alive(links[s]):
			_occ[links[s] & EntityId.SLOT_MASK] = _store.id_of(s)


func _contact(c: Collision, k: int, t: int) -> void:
	var id: int = c.c_a[k]
	var pad: int = c.c_b[k]
	var band: int = c.c_class[k]
	if not _store.alive(id) or not _store.alive(pad):
		return
	var s: int = EntityId.slot(id)
	var p: int = EntityId.slot(pad)
	if not _sink.standing(s) or (_store.flags[s] & EntityStore.F_DOCKED) != 0:
		return
	if _store.vel[s].dot(_store.up[p]) > 0.0:                 # ascending (a launch, A-119): never judged, no band, no hold
		return
	var head: int = _queue.head(pad)
	var free: bool = PadQueries.serves(_store, _defs, p) and (_store.flags[p] & EntityStore.F_BUILDING) == 0 \
			and _occ[p] == 0 and (head == 0 or head == id)
	if not free and band != Collision.L_DESTROY:
		return                                               # the ship holds (03 s6.4 "pad free")
	landed += 1
	var v: Vector3 = c.c_vec[k]                              # v_vert, v_horiz, tilt_deg
	var up_p: Vector3 = _store.up[p]
	var sd: ShipDef = _defs.ship(_store.owner[s], _store.def_id[s])
	var flags: int = 1 if _pilots.manual(id, _store.pos[p], up_p, _grade.manual_window_m) else 0
	flags |= 2 if _hot(s, p, t) else 0
	flags |= 4 if sd != null and sd.fuel_s > 0.0 and _store.fuel[s] / sd.fuel_s < _grade.dead_stick_fuel01 else 0
	var q: float = _grade.q(v.x, v.y, v.z, c.c_value[k], _defs.pad_radius_by_def[_store.def_id[p]])
	var g: int = _grade.grade(band, q, (flags & 1) != 0)
	if band == Collision.L_DAMAGE:
		var _d: bool = _sink.damage(s, _hull_damage(s, v), 0, t)
		g = LandingGrade.Grade.CRASH if not _sink.standing(s) else g
	if g == LandingGrade.Grade.CRASH:
		var _p: bool = _sink.damage(p, _pad_dmg, id, t)             # the pad takes the crash, named after the ship
	if band == Collision.L_DESTROY:
		var _x: bool = _sink.destroy(s, 0, t)
	_log.record(id, g, q)
	var e: SimEvent = _events.emit(SimEvent.Kind.LANDING, id, pad, _store.pos[s], q, _store.team[s])
	e.extra = PackedByteArray([g, roundi(q * _Q_MAX), flags, _wire(v.x), _wire(v.y)])
	if g != LandingGrade.Grade.CRASH:
		_dock(s, p, id, pad)


# 02 s2.2: hp_max * max(ratio_vert, ratio_hor, ratio_tilt), each ratio = excess / (damage - safe) clamped to [0, 1].
func _hull_damage(s: int, v: Vector3) -> float:
	var fc: FlightCommonDef = _defs.common
	var rv: float = _ratio(v.x, fc.landing_safe_v_vert, fc.landing_damage_v_vert)
	var rh: float = _ratio(v.y, fc.landing_safe_v_hor, fc.landing_damage_v_hor)
	var rt: float = _ratio(v.z, fc.landing_safe_pitch_deg, fc.landing_damage_tilt_deg)
	return _defs.hp_max(_store.owner[s], _store.def_id[s]) * maxf(rv, maxf(rh, rt))


static func _ratio(x: float, safe: float, damage: float) -> float:
	return clampf((x - safe) / (damage - safe), 0.0, 1.0) if damage > safe else 0.0


# Hot (02 s17.1): an enemy ship within hot_radius_m of the pad, or the ship took a hit within hot_window_s.
func _hot(s: int, p: int, t: int) -> bool:
	var hit: int = _store.last_damage_tick[s]
	if hit > 0 and float(t - hit) <= _grade.hot_window_s * float(_hz):
		return true
	var team: int = _store.team[s]
	var at: Vector3 = _store.pos[p]
	var r2: float = _grade.hot_radius_m * _grade.hot_radius_m
	var teams: PackedByteArray = _store.team                 # O(ships) once per landing: local handles, no copy
	var pos: PackedVector3Array = _store.pos
	for o: int in _store.ships:
		var to: int = teams[o]
		if to != team and to != EntityStore.NONE_U8 and at.distance_squared_to(pos[o]) <= r2:
			return true
	return false


func _dock(s: int, p: int, id: int, pad: int) -> void:
	var n: Vector3 = _store.up[p]
	var u: Vector3 = _store.up[s] - n * _store.up[s].dot(n)
	_store.up[s] = u.normalized() if u.length_squared() > 0.0 else _store.fwd[p]
	_store.fwd[s] = n
	_store.pos[s] = _store.pos[p] + n * _store.radius[s]
	_store.vel[s] = Vector3.ZERO
	_store.rates[s] = Vector3.ZERO
	_store.timer_b[s] = 0.0                                  # the launch hold starts from zero (A-119)
	_store.flags[s] |= EntityStore.F_DOCKED | EntityStore.F_LANDED
	_store.link[s] = pad
	_store.dirty[s] |= EntityStore.DIRTY_POSE | EntityStore.DIRTY_CONTROL
	_occ[p] = id
	_queue.remove(id)
	_service.begin(s)
	var _e: SimEvent = _events.emit(SimEvent.Kind.DOCKED, id, pad, _store.pos[s], 0.0, _store.team[s])


static func _wire(mps: float) -> int:
	return clampi(roundi(mps * _PER_MPS), 0, 255)
