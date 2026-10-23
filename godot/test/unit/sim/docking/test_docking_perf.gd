extends GdUnitTestSuite
## GD-15 perf note (03 s4.2 row 10 "economy / production / build / docking service", 0.8 ms p95; row 9 hosts the
## landings). Measured with ships actually being serviced: 48 pads, each with a ship docked and refuelling, rearming and
## repairing (Ice / Ore plentiful), 40 RETURN ships queued at the busy pads and 600 ships in flight elsewhere, so the
## step's one pass over the ships, every service timer and the queue update all do real work. Hard counters (ships
## serviced per tick, queue length, landings resolved) are asserted exactly; the wall-clock bounds go through PerfGate
## (report-only on a hosted runner, R0 B.17 A-97). Bounds: `Docking.step` at this stress load (48 ships in service at
## once, 40 queued) 50 % of the economy row (400 us; ~4 us per ship in service, ~0.05 us per ship scanned), a tick
## with 8 landings (one hot scan each over the 700 ships) 25 % of the 1.2 ms combat row it runs in (300 us).

const PADS: int = 48
const WAITING: int = 40
const FLYING: int = 600
const TICKS: int = 60
const LANDINGS: int = 8
const BOUND_STEP_US: float = 400.0
const BOUND_LAND_US: float = 300.0

static var _saved: PackedByteArray = PackedByteArray()


# The shipped rules with the per-player caps lifted to the S-SIM-1 scale (one player owns most of this crowd).
static func _rules() -> MatchRules:
	var r: MatchRules = WorldTestKit.rules()
	r.caps.units = PADS + WAITING + FLYING
	r.caps.structures = PADS
	return r
static var _pads: PackedInt32Array = PackedInt32Array()


# Pads on a ring 1.8 km around the +X pole (alternating teams, ~235 m apart), a damaged empty Lancer docked on each,
# RETURN Darts hovering over team-0 pads 0, 2, .., 8 (8 each), a crowd far away on the -X side. Built once through
# DEBUG_SPAWN, saved, restored per test.
func _build() -> void:
	if not _saved.is_empty():
		return
	var w: SimWorld = WorldTestKit.world(5, _rules())
	var st: EntityStore = w.store()
	var sd: ShipDef = DockingTestKit.ship_def(&"lancer")
	for k: int in PADS:
		var ang: float = TAU * float(k) / float(PADS)
		var at: Vector3 = Vector3(WorldTestKit.R, 0.0, 0.0).rotated(Vector3(0.0, cos(ang), sin(ang)), 0.3)
		var _a: bool = _pads.push_back(DockingTestKit.direct(w, &"pad", k % 2, k % 2, at))
	for pad: int in _pads:
		var team: int = st.team[EntityId.slot(pad)]
		var id: int = DockingTestKit.direct(w, &"lancer", team, team, DockingTestKit.far(w))
		DockingTestKit.dock(w, id, pad)
		var s: int = EntityId.slot(id)
		st.fuel[s] = 0.0
		st.ammo[s] = 0
		st.rockets[s] = 0
		st.hp[s] = float(sd.hp) * 0.2
	var waiters: PackedInt32Array = PackedInt32Array()
	for _k: int in WAITING:
		var _r: bool = waiters.push_back(DockingTestKit.direct(w, &"dart", 0, 0, DockingTestKit.far(w)))
	for k: int in FLYING:
		var _f: int = DockingTestKit.direct(w, &"dart", k % 2, k % 2, _crowd(k))
	w.step()
	assert_int(_pads.count(0) + waiters.count(0)).is_equal(0)
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.RETURN)
	for k: int in range(0, WAITING, 8):                                         # 8 ids per ORDER (wire limit)
		assert_int(w.apply_command(Command.order(0, waiters.slice(k, k + 8), spec)).code).is_equal(CommandResult.Code.ACCEPTED)
	w.step()
	for k: int in waiters.size():
		var pad: int = _pads[2 * (k % 5)]
		DockingTestKit.pose(w, waiters[k], pad, 40.0 + 13.0 * floorf(float(k) / 5.0), 30.0, Vector3.ZERO)   # < 150 m, 13 m apart
	for t: int in 2:
		w._players.team_ore[t] = 1 << 20
		w._players.team_ice[t] = 1 << 20
	w.step()
	_saved = w.serialize()


static func _crowd(k: int) -> Vector3:
	return Vector3(-(WorldTestKit.R + 900.0), float(k % 40) * 40.0 - 800.0, floorf(float(k) / 40.0) * 40.0 - 300.0)


func _world() -> SimWorld:
	_build()
	var w: SimWorld = SimWorld.deserialize(_saved, WorldTestKit.content(), null)
	assert_object(w).is_not_null()
	return w


func test_docking_step_with_48_ships_in_service_and_40_queued() -> void:
	var w: SimWorld = _world()
	var d: Docking = w.economy().docking
	assert_int(w.store().ships.size()).is_greater_equal(PADS + WAITING + FLYING)
	var dt: float = 1.0 / float(WorldTestKit.content().rules.tick_hz)
	var us: PackedFloat64Array = PackedFloat64Array()
	var ice0: int = w.economy().economy.stockpile(0).y
	for i: int in TICKS:
		var t0: int = Time.get_ticks_usec()
		d.step(w.tick() + i + 1, dt)
		var _p: bool = us.push_back(float(Time.get_ticks_usec() - t0))
		assert_int(d.service.serviced).is_equal(PADS)                           # hard counter: every docked ship served
	assert_int(d.queue.q_ship.size()).is_equal(WAITING)                          # hard counter: 5 pads x 8 waiting
	assert_int(w.economy().economy.stockpile(0).y).is_less(ice0)                 # the service paid Ice
	var per_tick: float = _median(us)
	print("PERF_NOTE docking_step min %.1f us median %.1f us" % [_min(us), per_tick])
	assert_bool(PerfGate.check("docking_step_48_serviced_40_queued_688_ships", per_tick, BOUND_STEP_US,
			"03 s4.2 row 10 economy 0.8 ms p95, 25 % share")).override_failure_message("measured %.1f us" % per_tick).is_true()


func test_eight_landings_in_one_tick() -> void:
	var calls: int = 12
	var us: PackedFloat64Array = PackedFloat64Array()
	var landed: int = 0
	for i: int in calls:
		var w: SimWorld = _world()
		var st: EntityStore = w.store()
		var c: Collision = w.collision
		var n: int = 0
		for k: int in range(25, PADS, 2):                                        # team-1 pads >= 2 km from every team-0 ship:
			var pad: int = _pads[k]                                              # each hot scan runs over all ships
			if n == LANDINGS:
				continue
			var occ: int = w.view().pad_occupant(pad)
			DockingTestKit.clear(w, occ)
			DockingTestKit.pose(w, occ, pad, 6.0, 1.0, Vector3.ZERO)
			c.c_kind[n] = Collision.C_PAD
			c.c_class[n] = Collision.L_SAFE
			c.c_a[n] = occ
			c.c_b[n] = pad
			c.c_value[n] = 1.0
			c.c_vec[n] = Vector3(2.0, 1.0, 3.0)
			n += 1
		c.contact_count = n
		var t0: int = Time.get_ticks_usec()
		w.economy().docking.land(w.tick() + i, c)
		var _p: bool = us.push_back(float(Time.get_ticks_usec() - t0))
		landed += w.economy().docking.touchdown.landed
	assert_int(landed).is_equal(LANDINGS * calls)                                # hard counter: every arrival landed
	var per_call: float = _median(us)
	print("PERF_NOTE docking_land min %.1f us median %.1f us" % [_min(us), per_call])
	assert_bool(PerfGate.check("docking_land_8_landings_688_ships", per_call, BOUND_LAND_US,
			"03 s4.2 row 9 combat 1.2 ms p95, 25 % share (landings run at the end of step 9)")).override_failure_message("measured %.1f us" % per_call).is_true()


func test_a_world_without_docked_ships_pays_only_the_ship_pass() -> void:
	var w: SimWorld = WorldTestKit.world(5, _rules())
	for k: int in FLYING:
		var _f: int = DockingTestKit.direct(w, &"dart", k % 2, k % 2, _crowd(k))
	w.step()
	assert_int(w.store().ships.size()).is_equal(FLYING)
	var d: Docking = w.economy().docking
	var dt: float = 1.0 / float(WorldTestKit.content().rules.tick_hz)
	var us: PackedFloat64Array = PackedFloat64Array()
	for i: int in TICKS:
		var t0: int = Time.get_ticks_usec()
		d.step(w.tick() + i + 1, dt)
		var _p: bool = us.push_back(float(Time.get_ticks_usec() - t0))
	var per_tick: float = _median(us)
	print("PERF_NOTE docking_step_idle min %.1f us median %.1f us" % [_min(us), per_tick])
	assert_int(d.service.serviced).is_equal(0)                                  # hard counter: nothing docked
	assert_int(d.queue.q_ship.size()).is_equal(0)
	assert_bool(PerfGate.check("docking_step_600_flying_none_docked", per_tick, 100.0, "03 s4.2 row 10 economy 0.8 ms p95")).is_true()


static func _median(v: PackedFloat64Array) -> float:
	var c: PackedFloat64Array = v.duplicate()
	c.sort()
	return c[c.size() >> 1]


static func _min(v: PackedFloat64Array) -> float:
	var c: PackedFloat64Array = v.duplicate()
	c.sort()
	return c[0]
