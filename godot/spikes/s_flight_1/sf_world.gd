class_name SfWorld extends RefCounted
## The spike's local sim: one ship, one stub pad, targets and projectiles, stepped at rules.tick_hz in the
## R0 B.5 tick order (input, assist substitution, kinematics, projectiles, collision, combat, docking service).
## No Nodes: the same object runs in the windowed spike and in the headless harness.

enum State { FLYING, DOCKED, DEAD, FORCED }

var d: SfDefs
var s: ShipState = ShipState.new()
var prev_p: Vector3               # pose at the previous tick (render interpolation, 03 s10.1)
var prev_fwd: Vector3
var prev_up: Vector3
var state: State = State.DOCKED
var input: PilotInput = PilotInput.new()   # effective input of the last tick (after assist substitution)
var hp: float
var ammo: int
var bombs: int
var tick: int
var pad_p: Vector3                # pad centre on the surface
var pad_n: Vector3                # pad normal
var arena: SfArena
var ap: SfAutopilot
var assist_on: bool               # auto-dock substituted the input this tick
var assisted_final: bool          # an assist tick happened inside auto_dock_radius_m since the last launch
var last_touchdown: SfTouchdown
var events: Array[SfEvent] = []
var dock_allowed: bool = true     # assist tier gate (Raw: false)
var _in_contact: bool
var _in_vol: bool
var _guard: float
var _dead_t: float
var _gun_cd: float
var _bomb_cd: float
var _prev_buttons: int
var _latched: bool
var _ammo_f: float
var _bomb_f: float
var _terrain: Terrain = Terrain.new()


func _init(defs: SfDefs, seed_value: int) -> void:
	d = defs
	pad_n = Sphere.from_lat_lon(deg_to_rad(SfDefs.num(d.arena, "pad_lat_deg")),
		deg_to_rad(SfDefs.num(d.arena, "pad_lon_deg")), 1.0)
	pad_p = pad_n * Sphere.PLANET_RADIUS
	arena = SfArena.new(d, pad_p, seed_value)
	ap = SfAutopilot.new(d)
	respawn_docked()


func dt() -> float:
	return d.dt()


## Ship parked tail-down on the pad socket, nose up, full service (03 s6.4 "On landing").
func respawn_docked() -> void:
	var f: Basis = Sphere.tangent_frame(pad_p)
	place(pad_p + pad_n * d.ship.bounding_radius, pad_n, -f.y, Vector3.ZERO)
	hp = d.hp_max
	ammo = d.gun_ammo
	bombs = d.bomb_count
	state = State.DOCKED
	_in_contact = true
	_in_vol = true


## Put the ship at a pose (harness and debug). Flip and boost ready, full fuel.
func place(p: Vector3, fwd: Vector3, up: Vector3, v: Vector3) -> void:
	s.p = p
	s.v = v
	s.fwd = fwd.normalized()
	s.up = (up - s.fwd * up.dot(s.fwd)).normalized()
	s.rates = Vector3.ZERO
	s.flip_time = -d.ship.flip_cooldown_s
	s.boost_time = -d.ship.boost_cooldown_s
	s.fuel = d.ship.fuel_s
	prev_p = s.p
	prev_fwd = s.fwd
	prev_up = s.up
	state = State.FLYING
	_in_contact = false
	_in_vol = false
	_latched = false
	assisted_final = false
	_guard = 0.0
	ap.reset(SfAutopilot.Phase.TRANSIT)


func pad_distance() -> float:
	return s.p.distance_to(pad_p)


func altitude() -> float:
	return s.p.length() - Sphere.PLANET_RADIUS - d.ship.bounding_radius


## Angle of attack in the body vertical plane (deg), + when the nose is above the velocity.
func aoa_deg() -> float:
	return rad_to_deg(atan2(-s.v.dot(s.up), s.v.dot(s.fwd)))


func drain_events() -> Array[SfEvent]:
	var out: Array[SfEvent] = events
	events = []
	return out


## One tick. `human` is this tick's PilotInput from the device layer (or a harness autopilot).
func step(human: PilotInput) -> void:
	tick += 1
	prev_p = s.p
	prev_fwd = s.fwd
	prev_up = s.up
	_copy(human, input)
	match state:
		State.DOCKED:
			_step_docked()
		State.DEAD:
			_dead_t -= dt()
			if _dead_t <= 0.0:
				respawn_docked()
				events.append(SfEvent.make(SfEvent.Kind.RESPAWN, tick, s.p))
		_:
			_step_flying()
	arena.step(dt(), tick, events)
	_prev_buttons = human.buttons


func _step_flying() -> void:
	_assist()
	var flip_ready: bool = s.flip_time <= -d.ship.flip_cooldown_s
	var boost_ready: bool = s.boost_time <= -d.ship.boost_cooldown_s
	var _r: ShipState = Kinematics.step_ship(s, input, d.ship, d.common, d.rules, _terrain, dt())
	if flip_ready and s.flip_time > 0.0:
		events.append(SfEvent.make(SfEvent.Kind.FLIP, tick, s.p))
	if boost_ready and s.boost_time > 0.0:
		events.append(SfEvent.make(SfEvent.Kind.BOOST, tick, s.p))
	_guard = maxf(_guard - dt(), 0.0)
	_collide()
	if state == State.DEAD:
		return
	_combat()
	_ceiling()


# 03 s5.5 / 4.1 step 4: auto-dock overwrites the input while DOCK is held near a free pad; forced release
# (ceiling) hands the ship to the autopilot until it is back below ceiling_soft_m.
func _assist() -> void:
	var was: bool = assist_on
	assist_on = false
	var radius: float = d.common.auto_dock_radius_m
	var dock_held: bool = (input.buttons & PilotInput.DOCK) != 0 and dock_allowed
	var dist: float = pad_distance()
	if dock_held and (dist <= radius or (_latched and dist <= radius * SfDefs.num(d.landing, "latch_release_mult"))):
		if not _latched:
			ap.reset(SfAutopilot.Phase.TRANSITION)
		_latched = true
		var keep: int = input.buttons & (PilotInput.FIRE1 | PilotInput.FIRE2)
		ap.dock_step(s, d.ship, pad_p, pad_n, input)
		input.buttons |= keep
		assist_on = true
		assisted_final = true
	else:
		_latched = false
		if dist > radius:
			assisted_final = false
	if state == State.FORCED:
		ap.hold(s, d.ship, d.rules.ceiling_soft_m - (d.rules.ceiling_hard_m - d.rules.ceiling_soft_m),
			d.ship.v_cruise, Vector3.ZERO, input)
	if assist_on != was:
		events.append(SfEvent.make(SfEvent.Kind.ASSIST_ON if assist_on else SfEvent.Kind.ASSIST_OFF, tick, s.p))


# 03 s6.1 / s6.4: pad landing volume first, then terrain contact; ship vs target ram.
func _collide() -> void:
	var in_vol: bool = SfLanding.in_pad_volume(s.p, pad_p, pad_n, d) and _guard <= 0.0
	var contact: bool = s.terrain_hit or in_vol
	if (contact and not _in_contact) or (in_vol and not _in_vol):
		var sink: float = s.hit_normal_speed if s.terrain_hit else -s.v.dot(pad_n)
		var td: SfTouchdown = SfLanding.evaluate(s.p, s.v, s.fwd, sink, pad_p, pad_n, in_vol,
			not assisted_final, d, SfTouchdown.new())
		_apply_touchdown(td)
	# contact episode ends only once the ship is clear of the ground again (no repeated scrape per bounce)
	if contact or altitude() > SfDefs.num(d.landing, "contact_release_m"):
		_in_contact = contact and state != State.DEAD
	_in_vol = in_vol and state != State.DEAD
	if state == State.FLYING or state == State.FORCED:
		var k: int = arena.ram_test(s.p, d.ship.bounding_radius)
		if k >= 0:
			_die("ram")


func _apply_touchdown(td: SfTouchdown) -> void:
	last_touchdown = td
	var ev: SfEvent = SfEvent.make(SfEvent.Kind.TOUCHDOWN, tick, s.p)
	ev.touchdown = td
	ev.near_pad = td.offset_m <= SfDefs.num(d.landing, "attempt_radius_m")
	events.append(ev)
	hp -= td.damage_hp
	if td.outcome == SfTouchdown.Outcome.CRASH or hp <= 0.0:
		_die("crash")
		return
	if td.outcome == SfTouchdown.Outcome.LANDED or td.outcome == SfTouchdown.Outcome.HARD:
		var f: Basis = Sphere.tangent_frame(pad_p)
		s.p = pad_p + pad_n * d.ship.bounding_radius
		s.v = Vector3.ZERO
		s.rates = Vector3.ZERO
		s.fwd = pad_n
		s.up = (s.up - pad_n * s.up.dot(pad_n)).normalized() if absf(s.up.dot(pad_n)) < 0.9 else -f.y
		state = State.DOCKED
		_latched = false


func _die(why: String) -> void:
	var ev: SfEvent = SfEvent.make(SfEvent.Kind.CRASH, tick, s.p)
	ev.reason = why
	ev.near_pad = s.p.distance_to(pad_p) <= SfDefs.num(d.landing, "attempt_radius_m")
	events.append(ev)
	state = State.DEAD
	hp = 0.0
	_dead_t = SfDefs.num(d.arena, "respawn_delay_s")
	s.v = Vector3.ZERO


func _combat() -> void:
	# Cooldowns run down every tick and may go negative (carry), so rof 10 at 30 Hz is exactly one shot per 3 ticks.
	var h: float = dt()
	_gun_cd = maxf(_gun_cd - h, -h)
	_bomb_cd = maxf(_bomb_cd - h, -h)
	if (input.buttons & PilotInput.FIRE1) != 0:
		while _gun_cd < h * 0.5 and ammo > 0:
			arena.fire_gun(s, d.ship.bounding_radius)
			ammo -= 1
			_gun_cd += 1.0 / d.gun_rof
	if (input.buttons & PilotInput.FIRE2) != 0 and bombs > 0 and _bomb_cd < h * 0.5:
		arena.drop_bomb(s)
		bombs -= 1
		_bomb_cd = maxf(_bomb_cd, 0.0) + 1.0 / d.bomb_rof
		events.append(SfEvent.make(SfEvent.Kind.BOMB_DROP, tick, s.p))
	if s.over_dive_excess > 0.0:
		hp -= d.common.overspeed_dps * dt()
		if hp <= 0.0:
			_die("overspeed")


func _ceiling() -> void:
	if state == State.FLYING and s.ceiling_forced:
		state = State.FORCED
		events.append(SfEvent.make(SfEvent.Kind.CEILING_RELEASE, tick, s.p))
	elif state == State.FORCED and s.p.length() - Sphere.PLANET_RADIUS < d.rules.ceiling_soft_m:
		state = State.FLYING
		events.append(SfEvent.make(SfEvent.Kind.CEILING_RESTORED, tick, s.p))


# DOCKED: parallel service timers (02 s2.3: refuel, rearm, repair), "thrust to launch" (03 s6.4 LAUNCHED:
# velocity launch_speed_mps along the pad normal; landing evaluation suppressed for launch_guard_s).
func _step_docked() -> void:
	var h: float = dt()
	s.fuel = minf(s.fuel + d.ship.fuel_s / d.refuel_time_s * h, d.ship.fuel_s)
	hp = minf(hp + d.hp_max / d.repair_time_s * h, d.hp_max)
	_ammo_f = minf(maxf(_ammo_f, float(ammo)) + float(d.gun_ammo) / d.rearm_time_s * h, float(d.gun_ammo))
	_bomb_f = minf(maxf(_bomb_f, float(bombs)) + float(d.bomb_count) / d.rearm_time_s * h, float(d.bomb_count))
	ammo = int(_ammo_f)
	bombs = int(_bomb_f)
	s.v = Vector3.ZERO
	if input.thrust >= SfDefs.num(d.landing, "launch_thrust"):
		state = State.FLYING
		s.v = pad_n * d.common.launch_speed_mps
		_guard = SfDefs.num(d.landing, "launch_guard_s")
		_in_contact = false
		_in_vol = true
		assisted_final = false
		_latched = false
		_ammo_f = 0.0
		_bomb_f = 0.0
		ap.reset(SfAutopilot.Phase.TRANSIT)
		events.append(SfEvent.make(SfEvent.Kind.LAUNCHED, tick, s.p))


static func _copy(a: PilotInput, b: PilotInput) -> void:
	b.thrust = a.thrust
	b.pitch = a.pitch
	b.yaw = a.yaw
	b.roll = a.roll
	b.buttons = a.buttons
