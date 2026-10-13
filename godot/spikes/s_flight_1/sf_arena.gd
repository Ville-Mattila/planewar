class_name SfArena extends RefCounted
## Targets, slugs and bombs of the spike (03 s5.4, s6.1; R0 B.5). Slugs fly straight in the world frame and carry
## the shooter's velocity; bombs fall under -g n and are transported; both through `Kinematics.step_projectile`.
## Hits are swept segment-vs-sphere tests; bombs resolve blast radius on ground contact.

var d: SfDefs
var t_pos: PackedVector3Array = PackedVector3Array()     # target centres
var t_hp: PackedFloat32Array = PackedFloat32Array()
var t_respawn: PackedFloat32Array = PackedFloat32Array() # > 0: destroyed, seconds to respawn
var t_ground: PackedByteArray = PackedByteArray()        # 1 = ground target (bunker), 0 = air target
var t_radius: PackedFloat32Array = PackedFloat32Array()
var slug_p: PackedVector3Array = PackedVector3Array()
var slug_v: PackedVector3Array = PackedVector3Array()
var slug_ttl: PackedFloat32Array = PackedFloat32Array()
var bomb_p: PackedVector3Array = PackedVector3Array()
var bomb_v: PackedVector3Array = PackedVector3Array()
var bomb_age: PackedFloat32Array = PackedFloat32Array()
var pred_valid: bool
var pred_p: Vector3
var pred_t: float
var pred_on_target: bool
var shots: int
var slug_hits: int
var _rng: Rng
var _air_hp: float
var _ground_hp: float
var _respawn_s: float


func _init(defs: SfDefs, pad_p: Vector3, seed_value: int) -> void:
	d = defs
	_rng = Rng.new(seed_value)
	var tb: Dictionary = d.targets
	_air_hp = SfDefs.num(tb, "air_hp")
	_ground_hp = SfDefs.num(tb, "ground_hp")
	_respawn_s = SfDefs.num(tb, "respawn_s")
	for e: Variant in SfDefs.arr(tb, "air"):
		var a: Dictionary = e
		_add(place(pad_p, SfDefs.num(a, "bearing_deg"), SfDefs.num(a, "dist_m"), SfDefs.num(a, "alt_m")), false)
	for e: Variant in SfDefs.arr(tb, "ground"):
		var g: Dictionary = e
		_add(place(pad_p, SfDefs.num(g, "bearing_deg"), SfDefs.num(g, "dist_m"), 0.0), true)


## Point at great-circle distance `dist_m` from `from` along bearing (deg clockwise from north), `alt_m` above datum.
static func place(from: Vector3, bearing_deg: float, dist_m: float, alt_m: float) -> Vector3:
	var f: Basis = Sphere.tangent_frame(from)
	var b: float = deg_to_rad(bearing_deg)
	var t: Vector3 = f.y * cos(b) + f.x * sin(b)
	var th: float = dist_m / Sphere.PLANET_RADIUS
	return (f.z * cos(th) + t * sin(th)) * (Sphere.PLANET_RADIUS + alt_m)


## Straight-line intercept (06 s6.3): the slug carries the shooter's velocity, so a static target moves by -v_s
## relative to the muzzle. Returns the aim point.
static func lead(p_s: Vector3, v_s: Vector3, p_t: Vector3, speed: float) -> Vector3:
	var t: float = p_s.distance_to(p_t) / speed
	var l: Vector3 = p_t
	for i: int in 3:
		l = p_t - v_s * t
		t = p_s.distance_to(l) / speed
	return l


## Place a test target (harness: co-altitude gun runs). Returns its index.
func add_target(p: Vector3, ground: bool) -> int:
	_add(p, ground)
	return t_pos.size() - 1


func clear_targets() -> void:
	t_pos.clear()
	t_hp.clear()
	t_respawn.clear()
	t_ground.clear()
	t_radius.clear()


func alive(i: int) -> bool:
	return t_respawn[i] <= 0.0


func fire_gun(s: ShipState, bounding: float) -> void:
	var spread: float = deg_to_rad(d.gun_spread_deg) * sqrt(_rng.next_float())
	var ang: float = TAU * _rng.next_float()
	var right: Vector3 = s.fwd.cross(s.up)
	var dir: Vector3 = (s.fwd + (right * cos(ang) + s.up * sin(ang)) * tan(spread)).normalized()
	var _a: bool = slug_p.push_back(s.p + s.fwd * bounding)
	var _b: bool = slug_v.push_back(s.v + dir * d.slug.speed_mps)
	var _c: bool = slug_ttl.push_back(d.slug.lifetime_s)
	shots += 1


func drop_bomb(s: ShipState) -> void:
	var _a: bool = bomb_p.push_back(s.p - s.up * d.ship.bounding_radius * 0.5)
	var _b: bool = bomb_v.push_back(s.v - s.p.normalized() * d.bomb.eject_down_mps)
	var _c: bool = bomb_age.push_back(0.0)


func step(dt: float, tick: int, events: Array[SfEvent]) -> void:
	for i: int in t_pos.size():
		if t_respawn[i] > 0.0:
			t_respawn[i] = t_respawn[i] - dt
			if t_respawn[i] <= 0.0:
				t_hp[i] = _ground_hp if t_ground[i] == 1 else _air_hp
	_step_slugs(dt, tick, events)
	_step_bombs(dt, tick, events)


## Index of a live target the sphere (p, r) overlaps, else -1 (ship vs target ram).
func ram_test(p: Vector3, r: float) -> int:
	for i: int in t_pos.size():
		if alive(i) and p.distance_to(t_pos[i]) < r + t_radius[i]:
			return i
	return -1


## Predicted bomb impact (06 s6.3 predictor with the sim's own step, 03 s14.6 horizon 6 s at 15 Hz).
func predict_bomb(s: ShipState, horizon_s: float, hz: float) -> void:
	var q: Vector3 = s.p - s.up * d.ship.bounding_radius * 0.5
	var w: Vector3 = s.v - s.p.normalized() * d.bomb.eject_down_mps
	var h: float = 1.0 / hz
	pred_valid = false
	pred_on_target = false
	for i: int in int(horizon_s * hz):
		var st: ProjectileState = Kinematics.step_projectile(q, w, d.bomb, d.rules, h)
		q = st.p
		w = st.v
		if q.length() <= Sphere.PLANET_RADIUS:
			pred_valid = true
			pred_p = q.normalized() * Sphere.PLANET_RADIUS
			pred_t = float(i + 1) * h
			for k: int in t_pos.size():
				if t_ground[k] == 1 and alive(k) and pred_p.distance_to(t_pos[k]) <= d.blast_radius_structure_m:
					pred_on_target = true
			return


func _add(p: Vector3, ground: bool) -> void:
	var _a: bool = t_pos.push_back(p)
	var _b: bool = t_hp.push_back(_ground_hp if ground else _air_hp)
	var _c: bool = t_respawn.push_back(0.0)
	var _d: bool = t_ground.push_back(1 if ground else 0)
	var r: float = SfDefs.num(d.targets, "ground_radius_m" if ground else "air_radius_m")
	var _e: bool = t_radius.push_back(r)


func _step_slugs(dt: float, tick: int, events: Array[SfEvent]) -> void:
	var i: int = slug_p.size() - 1
	while i >= 0:
		var p0: Vector3 = slug_p[i]
		var st: ProjectileState = Kinematics.step_projectile(p0, slug_v[i], d.slug, d.rules, dt)
		slug_p[i] = st.p
		slug_v[i] = st.v
		slug_ttl[i] = slug_ttl[i] - dt
		var hit: int = _sweep(p0, st.p, d.slug.radius_m)
		if hit >= 0:
			var dmg: float = d.gun_damage_min + (d.gun_damage_max - d.gun_damage_min) * _rng.next_float()
			if t_ground[hit] == 1:
				dmg *= d.gun_structure_mult
			slug_hits += 1
			_damage(hit, dmg, tick, events)
		if hit >= 0 or slug_ttl[i] <= 0.0 or st.p.length() <= Sphere.PLANET_RADIUS:
			slug_p.remove_at(i)
			slug_v.remove_at(i)
			slug_ttl.remove_at(i)
		i -= 1


func _step_bombs(dt: float, tick: int, events: Array[SfEvent]) -> void:
	var i: int = bomb_p.size() - 1
	while i >= 0:
		var st: ProjectileState = Kinematics.step_projectile(bomb_p[i], bomb_v[i], d.bomb, d.rules, dt)
		bomb_p[i] = st.p
		bomb_v[i] = st.v
		bomb_age[i] = bomb_age[i] + dt
		if st.p.length() <= Sphere.PLANET_RADIUS + d.bomb.radius_m or bomb_age[i] > d.bomb.lifetime_s:
			var ground: Vector3 = st.p.normalized() * Sphere.PLANET_RADIUS
			var armed: bool = bomb_age[i] >= d.bomb.arm_s
			var ev: SfEvent = SfEvent.make(SfEvent.Kind.BOMB_IMPACT, tick, ground)
			ev.value = 1.0 if armed else 0.0
			events.append(ev)
			if armed:
				_blast(ground, tick, events)
			bomb_p.remove_at(i)
			bomb_v.remove_at(i)
			bomb_age.remove_at(i)
		i -= 1


func _blast(at: Vector3, tick: int, events: Array[SfEvent]) -> void:
	for k: int in t_pos.size():
		if not alive(k):
			continue
		var r: float = d.blast_radius_structure_m if t_ground[k] == 1 else d.blast_radius_m
		if at.distance_to(t_pos[k]) <= r + t_radius[k] * float(1 - t_ground[k]):
			_damage(k, d.bomb_damage, tick, events)


func _sweep(a: Vector3, b: Vector3, pr: float) -> int:
	var ab: Vector3 = b - a
	var len2: float = ab.length_squared()
	for k: int in t_pos.size():
		if not alive(k):
			continue
		var t: float = clampf((t_pos[k] - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
		var rr: float = t_radius[k] + pr
		if (a + ab * t).distance_squared_to(t_pos[k]) <= rr * rr:
			return k
	return -1


func _damage(k: int, dmg: float, tick: int, events: Array[SfEvent]) -> void:
	t_hp[k] = t_hp[k] - dmg
	var ev: SfEvent = SfEvent.make(SfEvent.Kind.TARGET_HIT, tick, t_pos[k])
	ev.a = k
	ev.value = dmg
	events.append(ev)
	if t_hp[k] <= 0.0:
		t_respawn[k] = _respawn_s
		var de: SfEvent = SfEvent.make(SfEvent.Kind.TARGET_DESTROYED, tick, t_pos[k])
		de.a = k
		de.value = float(t_ground[k])
		events.append(de)
