class_name ProjectileRig extends InterestRig
## Test / bench helper (NET-58, R0 B.22 A-112): InterestRig's canonical scene plus a population of projectile rows in
## ProjectileStore slots 4,096-6,143. Replicated kinds (rocket, bomb, siege shell, canister) spawn at `rate_per_s`
## (default ~12/s, life 100-200 ticks: ~60 live, ~5 s mean, the 04 s4.6 / A-112 figures) from A / B movers at their
## position, each with the mover's team and owner and a target entity; bombs and siege shells fall under gravity
## (semi-implicit Euler, the sim's shape), rockets and canisters fly straight. Slugs (`slugs_per_tick`, 20-tick life)
## churn the same slots: freed slots go on a LIFO free stack (lowest on top) with a generation bump, the
## ProjectileStore scheme (0-tick quarantine, A-20). Every projectile row is written after the entity rows each tick.

const DEFS: PackedInt32Array = [10, 11, 12, 13]             # rig def ids of rocket, bomb, siege shell, canister
const KINDS: PackedInt32Array = [SnapshotFrame.ROCKET, SnapshotFrame.BOMB, SnapshotFrame.SIEGE_SHELL, SnapshotFrame.CANISTER]
const SLOT_COUNT: int = EntityId.PROJECTILE_SLOT_END - EntityId.PROJECTILE_SLOT_MIN

var rate_per_s: float = 12.0
var slugs_per_tick: int = 1
var spawning: bool = true
## Share of replicated projectiles whose shooter and target are dropped for their last BLIND_TICKS: other teams' clients
## lose them from V just before they die, so a recycled slot follows a non-DEATH failure (review round 2 path).
var blind_share: float = 0.0
const BLIND_TICKS: int = 2
var n_entities: int = 0
var p_kind: PackedInt32Array = PackedInt32Array()           # by local index; -1 = free
var p_pos: PackedVector3Array = PackedVector3Array()
var p_vel: PackedVector3Array = PackedVector3Array()
var p_ttl: PackedInt32Array = PackedInt32Array()
var p_gen: PackedInt32Array = PackedInt32Array()
var p_shooter: PackedInt32Array = PackedInt32Array()
var p_target: PackedInt32Array = PackedInt32Array()
var p_blind: PackedByteArray = PackedByteArray()
var live: PackedInt32Array = PackedInt32Array()             # live local indices (any kind)
var died: PackedInt32Array = PackedInt32Array()             # roster indices of replicated projectiles freed this tick
var spawned: int = 0
var _free: PackedInt32Array = PackedInt32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func build(n_clients: int, sizes: Vector3i, movers: Vector3i, bombs: int, seed_value: int) -> void:
	super.build(n_clients, sizes, movers, bombs, seed_value)
	n_entities = snap.frame.count
	_rng.seed = seed_value * 7919 + 1
	var e: int = p_kind.resize(SLOT_COUNT) | p_pos.resize(SLOT_COUNT) | p_vel.resize(SLOT_COUNT) | p_ttl.resize(SLOT_COUNT)
	e |= p_gen.resize(SLOT_COUNT) | p_shooter.resize(SLOT_COUNT) | p_target.resize(SLOT_COUNT) | p_blind.resize(SLOT_COUNT)
	assert(e == OK)
	p_kind.fill(-1)
	p_gen.fill(1)
	for i: int in SLOT_COUNT:
		var _p: bool = _free.push_back(SLOT_COUNT - 1 - i)


## Moves the scene and the projectiles one tick, writes the frame (entity rows, then projectile rows), prepare_tick.
func step_scene() -> void:
	snap.frame.count = n_entities                           # SnapRig moves its own rows only
	snap.tick += 1
	snap.frame.tick = snap.tick
	snap.step_motion()
	step_projectiles()
	snap.codec.prepare_tick(snap.frame)


func step_projectiles() -> void:
	died.clear()
	var dt: float = 1.0 / float(SnapRig.HZ)
	var keep: PackedInt32Array = PackedInt32Array()
	for i: int in live:
		var p: Vector3 = p_pos[i]
		var k: int = p_kind[i]
		if k == SnapshotFrame.BOMB or k == SnapshotFrame.SIEGE_SHELL:
			p_vel[i] = p_vel[i] - p.normalized() * (SnapRig.G * dt)
		p_pos[i] = p + p_vel[i] * dt
		p_ttl[i] -= 1
		if p_ttl[i] <= 0 or p_pos[i].length() < Sphere.PLANET_RADIUS:
			_kill(i)
		else:
			var _a: bool = keep.push_back(i)
	live = keep
	if spawning:
		for _s: int in slugs_per_tick:
			_spawn(SnapshotFrame.SLUG, 20)
		var budget: float = rate_per_s / float(SnapRig.HZ)
		while budget > 0.0:
			if _rng.randf() < budget:
				_spawn(KINDS[_rng.randi() % KINDS.size()], _rng.randi_range(100, 200))
			budget -= 1.0
	_write_rows()


func _kill(i: int) -> void:
	if SnapshotFrame.replicated_kind(p_kind[i]):
		var _d: bool = died.push_back(Roster.PROJECTILE_INDEX_MIN + i)
	p_kind[i] = -1
	p_gen[i] = EntityId.bump_gen(p_gen[i])
	var _p: bool = _free.push_back(i)


func _spawn(kind: int, ttl: int) -> void:
	if _free.is_empty():
		return
	var i: int = _free[_free.size() - 1]
	_free.remove_at(_free.size() - 1)
	var shooter: int = _rng.randi_range(0, mini(n_entities, 260) - 1)          # A / B tier entities fire
	var target: int = _rng.randi_range(0, n_entities - 1)
	var up: Vector3 = snap.frame.pos[shooter].normalized()
	var f: Basis = Sphere.tangent_frame(snap.frame.pos[shooter])
	var dir: Vector3 = (f.x * _rng.randf_range(-1.0, 1.0) + f.y * _rng.randf_range(-1.0, 1.0)).normalized()
	p_kind[i] = kind
	p_pos[i] = snap.frame.pos[shooter] + up * 5.0
	p_vel[i] = dir * (150.0 if kind == SnapshotFrame.ROCKET else 80.0)
	p_ttl[i] = ttl
	p_shooter[i] = EntityId.make(shooter, 1)
	p_target[i] = EntityId.make(target, 1)
	var _a: bool = live.push_back(i)
	p_blind[i] = 1 if blind_share > 0.0 and _rng.randf() < blind_share else 0
	if SnapshotFrame.replicated_kind(kind):
		spawned += 1
		var def: int = DEFS[KINDS.find(kind)]
		var _r: bool = snap.roster.add(Roster.PROJECTILE_INDEX_MIN + i, p_gen[i], def, snap.roster.owner_of(shooter),
				snap.roster.team_of(shooter))


func _write_rows() -> void:
	snap.frame.resize(n_entities + live.size())
	for k: int in live.size():
		var i: int = live[k]
		var kind: int = p_kind[i]
		var grav: bool = kind == SnapshotFrame.BOMB or kind == SnapshotFrame.SIEGE_SHELL
		var team: int = snap.roster.team_of(EntityId.slot(p_shooter[i]))
		var blind: bool = p_blind[i] != 0 and p_ttl[i] <= BLIND_TICKS
		snap.frame.set_projectile(n_entities + k, EntityId.PROJECTILE_SLOT_MIN + i, kind, p_pos[i], p_vel[i], team, grav,
				0 if blind else p_shooter[i], 0 if blind else p_target[i], p_gen[i])


## Live replicated projectiles (roster indices), ascending.
func live_replicated() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in live:
		if SnapshotFrame.replicated_kind(p_kind[i]):
			var _a: bool = out.push_back(Roster.PROJECTILE_INDEX_MIN + i)
	out.sort()
	return out


## A decoder sharing the rig's gravity table (the projectile gravity defs included).
func new_projectile_decoder(team_id: int, roster: Roster) -> SnapshotDecoder:
	var d: SnapshotDecoder = SnapshotDecoder.new(SnapRig.G, SnapRig.HZ, team_id, roster)
	var _r: int = d.gravity_def.resize(16)
	d.gravity_def[SnapRig.DEF_BOMB] = 1
	d.gravity_def[DEFS[1]] = 1
	d.gravity_def[DEFS[2]] = 1
	return d
