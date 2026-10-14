class_name SnapRig extends RefCounted
## Test helper (NET-06): a deterministic scene of N entities for the snapshot codec. Movers fly circles
## (radius 300-700 m, 60-140 m/s, banked, gently climbing and sinking) around anchors 200-1,400 m up; bombs fall
## under gravity with a semi-implicit Euler step (the sim's integration shape), fixed attitude, and respawn; structures sit on
## the datum and take hp hits at a per-tier rate (04 s4.5: A 10 %, B 5 %, C 2 % per snapshot). Teams 0-2.
## Tier lists follow 04 s4.5 proportions; one shared SnapshotCodec, one BaselineStore + SnapshotDecoder per client.

enum Kind { STRUCTURE, MOVER, BOMB }
const DEF_STRUCTURE: int = 1
const DEF_SHIP: int = 2
const DEF_BOMB: int = 3
const G: float = 6.0                         # rules.json gravity
const HZ: int = 30
const REFRESH_PER_TICK: int = 3             # ceil(700 / 300) rolling-refresh FULLs per tick (04 s4.3)

var codec: SnapshotCodec = SnapshotCodec.new(G, HZ)
var frame: SnapshotFrame = SnapshotFrame.new()
var roster: Roster = Roster.new()
var tick: int = 0
var kind: PackedInt32Array = PackedInt32Array()
var tier: PackedInt32Array = PackedInt32Array()           # 0 A, 1 B, 2 C
var anchor: PackedVector3Array = PackedVector3Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var omega: PackedFloat32Array = PackedFloat32Array()
var phase: PackedFloat32Array = PackedFloat32Array()
var hp: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## n entities; `movers` = [A, B, C] mover counts; the rest of each tier [A, B, C] = `sizes` are structures.
## Bombs replace the first `bombs` A movers.
func build(sizes: Vector3i, movers: Vector3i, bombs: int, seed_value: int) -> void:
	_rng.seed = seed_value
	var n: int = sizes.x + sizes.y + sizes.z
	frame.resize(n)
	var _r1: int = kind.resize(n)
	var _r2: int = tier.resize(n)
	var _r3: int = anchor.resize(n)
	var _r4: int = radius.resize(n)
	var _r5: int = omega.resize(n)
	var _r6: int = phase.resize(n)
	var _r7: int = hp.resize(n)
	var centre: Vector3 = Sphere.from_lat_lon(0.31, 1.17, Sphere.PLANET_RADIUS)
	for i: int in n:
		var t: int = 0 if i < sizes.x else (1 if i < sizes.x + sizes.y else 2)
		var first: int = [0, sizes.x, sizes.x + sizes.y][t]
		var mv: int = [movers.x, movers.y, movers.z][t]
		tier[i] = t
		kind[i] = Kind.MOVER if i - first < mv else Kind.STRUCTURE
		if t == 0 and i < bombs:
			kind[i] = Kind.BOMB
		var spread: float = [400.0, 2500.0, 5000.0][t]
		var f: Basis = Sphere.tangent_frame(centre)
		var off: Vector3 = f.x * _rng.randf_range(-spread, spread) + f.y * _rng.randf_range(-spread, spread)
		var dir: Vector3 = (centre + off).normalized()
		var alt: float = _rng.randf_range(200.0, 1400.0) if kind[i] != Kind.STRUCTURE else _rng.randf_range(0.0, 300.0)
		anchor[i] = dir * (Sphere.PLANET_RADIUS + alt)
		radius[i] = _rng.randf_range(300.0, 700.0)
		omega[i] = _rng.randf_range(60.0, 140.0) / radius[i] * (1.0 if _rng.randf() < 0.5 else -1.0)
		phase[i] = _rng.randf_range(0.0, TAU)
		hp[i] = 1.0
		var team_id: int = i % 3
		var def_id: int = [DEF_STRUCTURE, DEF_SHIP, DEF_BOMB][kind[i]]
		var _ok: bool = roster.add(i, 1, def_id, team_id, team_id)
		frame.set_entity(i, i, anchor[i], Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, team_id, i & 0x0F,
				kind[i] == Kind.BOMB, 0x7)
		if kind[i] == Kind.BOMB:
			_respawn_bomb(i)


func _respawn_bomb(i: int) -> void:
	var up: Vector3 = anchor[i].normalized()
	var f: Basis = Sphere.tangent_frame(anchor[i])
	frame.pos[i] = up * (Sphere.PLANET_RADIUS + _rng.randf_range(900.0, 1400.0))
	frame.vel[i] = f.x * _rng.randf_range(-90.0, 90.0) + f.y * _rng.randf_range(-90.0, 90.0)


## Advances the scene one tick, refills the frame and runs the codec's prepare_tick.
func step() -> void:
	tick += 1
	frame.tick = tick
	step_motion()
	codec.prepare_tick(frame)


## Moves every entity to `tick` (no prepare_tick; benchmarks time that separately).
func step_motion() -> void:
	var dt: float = 1.0 / HZ
	for i: int in frame.count:
		if kind[i] == Kind.MOVER:
			_step_mover(i, float(tick) * dt)
		elif kind[i] == Kind.BOMB:
			var p: Vector3 = frame.pos[i]
			var v: Vector3 = frame.vel[i] - p.normalized() * (G * dt)
			frame.vel[i] = v
			frame.pos[i] = p + v * dt
			if frame.pos[i].length() < Sphere.PLANET_RADIUS:
				_respawn_bomb(i)
		else:
			var rate: float = [0.10, 0.05, 0.02][tier[i]] * (1.0 if tier[i] == 0 else (0.5 if tier[i] == 1 else 1.0 / 15.0))
			if _rng.randf() < rate:
				hp[i] = maxf(0.05, hp[i] - 0.03)
				frame.hp01[i] = hp[i]


func _step_mover(i: int, t: float) -> void:
	var f: Basis = Sphere.tangent_frame(anchor[i])
	var a: float = phase[i] + omega[i] * t
	var r: float = radius[i]
	var climb: float = 40.0 * sin(t * 0.3 + phase[i])
	frame.pos[i] = anchor[i] + f.x * (r * cos(a)) + f.y * (r * sin(a)) + f.z * climb
	var v: Vector3 = (f.x * (-sin(a)) + f.y * cos(a)) * (r * omega[i]) + f.z * (12.0 * cos(t * 0.3 + phase[i]))
	frame.vel[i] = v
	var up: Vector3 = frame.pos[i].normalized()
	var bank: Basis = Basis.looking_at(v, up).rotated(v.normalized(), 0.4 * signf(omega[i]))
	frame.rot[i] = _quat_v4(bank.get_rotation_quaternion())


static func _quat_v4(q: Quaternion) -> Vector4:
	return Vector4(q.x, q.y, q.z, q.w)


## Tier lists for the client with key k on this tick (04 s4.1 schedule: A every tick, B every 2, C every 15).
func lists(k: int, out_a: PackedInt32Array, out_b: PackedInt32Array, out_c: PackedInt32Array) -> void:
	out_a.clear()
	out_b.clear()
	out_c.clear()
	var b_on: bool = (tick + k) % 2 == 0
	var c_on: bool = (tick + k) % 15 == 0
	for i: int in frame.count:
		if tier[i] == 0:
			var _a: bool = out_a.push_back(i)
		elif tier[i] == 1 and b_on:
			var _b: bool = out_b.push_back(i)
		elif tier[i] == 2 and c_on:
			var _c: bool = out_c.push_back(i)


## Canonical schedule (04 s4.1, R0 B.10 A-40) for client `k` on this tick: A every tick, B on (tick + k) % 2 == 0,
## C on (tick + k) % 15 == 0, and `r` = REFRESH_PER_TICK rolling-refresh indices round-robin over the C set.
func canonical_lists(k: int, out_a: PackedInt32Array, out_b: PackedInt32Array, out_c: PackedInt32Array,
		r: PackedInt32Array) -> void:
	lists(k, out_a, out_b, out_c)
	r.clear()
	var c0: int = -1
	var cn: int = 0
	for i: int in frame.count:
		if tier[i] == 2:
			c0 = i if c0 < 0 else c0
			cn += 1
	for j: int in REFRESH_PER_TICK:
		if cn > 0:
			var _r: bool = r.push_back(c0 + (tick * REFRESH_PER_TICK + j + k * 37) % cn)


## A client decoder that shares the rig's roster and gravity table.
func new_decoder(team_id: int) -> SnapshotDecoder:
	var d: SnapshotDecoder = SnapshotDecoder.new(G, HZ, team_id, roster)
	var _r: int = d.gravity_def.resize(4)
	d.gravity_def[DEF_BOMB] = 1
	return d


## Moves every entity `angle` radians around the moon's x axis (new cells: FULL records on the next tick).
func teleport(angle: float) -> void:
	var b: Basis = Basis(Vector3.RIGHT, angle)
	for i: int in frame.count:
		anchor[i] = b * anchor[i]
		frame.pos[i] = b * frame.pos[i]
		frame.vel[i] = b * frame.vel[i]


## A copy of the roster without `skip` (a client whose ENTITY_META for it has not arrived).
func roster_without(skip: int) -> Roster:
	var r: Roster = Roster.new()
	for i: int in frame.count:
		if i != skip:
			var _ok: bool = r.add(i, 1, roster.def_of(i), roster.owner_of(i), roster.team_of(i))
	return r
