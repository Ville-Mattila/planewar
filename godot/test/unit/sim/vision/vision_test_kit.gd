class_name VisionTestKit extends RefCounted
## Fixtures for the TA-37 Vision tests: a WorldTestKit world (flat datum; slots 0 and 2 on team 0, slot 1 on team 1)
## with entities written straight into the store (Vision reads pos, team, owner, def_id, kind and hash_cell), a
## sense() that runs Spatial (hash_cell) and every team's pass, and a brute-force reference over all pairs.

const R: float = Sphere.PLANET_RADIUS


static func world() -> SimWorld:
	return WorldTestKit.world()


## Writes a live entity of `def` (ships.json / ground_units.json / structures.json / towers.json id) at `p`; owner is
## the team's first player slot (team 0 -> 0, team 1 -> 1), else neutral (255). `kind_override` K_WRECK for wrecks.
static func put(w: SimWorld, def: StringName, team: int, p: Vector3, kind_override: int = -1) -> int:
	var d: int = WorldTestKit.def_id(def)
	assert(d >= 0, "unknown def %s" % def)
	var kind: int = kind_override
	if kind < 0:
		match DefRanges.kind_of(d):
			DefRanges.K_SHIP:
				kind = EntityStore.K_SHIP
			DefRanges.K_GROUND:
				kind = EntityStore.K_GROUND
			_:
				kind = EntityStore.K_STRUCTURE
	var st: EntityStore = w.store()
	var id: int = st.alloc(kind, w.tick())
	assert(id != EntityId.NULL_ID)
	var s: int = EntityId.slot(id)
	st.pos[s] = p
	st.def_id[s] = d
	st.team[s] = team if team >= 0 else EntityStore.NONE_U8
	st.owner[s] = team if team == 0 or team == 1 else EntityStore.NONE_U8
	st.radius[s] = 6.0
	st.hp[s] = 100.0
	st.up[s] = p.normalized()
	st.fwd[s] = Sphere.tangent_frame(p).y
	return id


## A point `alt` metres above the datum, `east_m` metres of datum arc east of +X along the equator.
static func at(alt: float, east_m: float = 0.0) -> Vector3:
	return Sphere.from_lat_lon(0.0, east_m / R, R + alt)


## Spatial rebuild (hash_cell) then every team's pass at the current tick.
static func sense(w: SimWorld) -> void:
	w.spatial.rebuild()
	w.vision.refresh(w.tick())


static func visible(w: SimWorld, team: int, id: int) -> bool:
	return (w.store().visible_mask[EntityId.slot(id)] & (1 << team)) != 0


## Brute force of 03 s3.7 for `team`: per slot 1 if own team or seen by some live non-wreck, non-site (A-76) sensor of `team`.
static func brute(w: SimWorld, team: int) -> PackedByteArray:
	var st: EntityStore = w.store()
	var v: Vision = w.vision
	var out: PackedByteArray = PackedByteArray()
	var _r: int = out.resize(EntityStore.SLOT_COUNT)
	out.fill(0)
	var lists: Array[PackedInt32Array] = [st.structures, st.ships, st.ground, st.wrecks]
	for lx: PackedInt32Array in lists:
		for x: int in lx:
			if st.team[x] == team:
				out[x] = 1
				continue
			for le: PackedInt32Array in lists:
				for e: int in le:
					if st.team[e] != team or st.kind[e] == EntityStore.K_WRECK or (st.flags[e] & EntityStore.F_BUILDING) != 0:
						continue
					var row: int = mini(st.owner[e], Vision.OWNERS - 1) * Vision.DEF_N + st.def_id[e]
					if Vision.sees(st.pos[e], st.pos[x], v.sensor_r[row], v.reveal_r[row]):
						out[x] = 1
	return out


static func random_dir(rng: Rng) -> Vector3:
	var v: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0))
	return v.normalized() if v.length_squared() > 1e-6 else Vector3(1, 0, 0)


## Random scene of `n` entities around a cube corner, a cube edge and two face points (5 km): ships -300..1,800 m,
## ground and structures -400..300 m, teams -1 (neutral)..3, 10 % wrecks.
static func scatter(w: SimWorld, rng: Rng, n: int) -> void:
	var centres: PackedVector3Array = PackedVector3Array([Vector3(1, 1, 1).normalized(), Vector3(1, 1, 0.2).normalized(),
		Vector3(1, 0.1, -0.2).normalized(), Vector3(-0.3, 0.2, 1).normalized()])
	var ships: Array[StringName] = [&"dart", &"scout", &"bomber", &"hauler", &"lancer"]
	var others: Array[StringName] = [&"harvester", &"siege_crawler", &"sensor_mast", &"solar_array", &"core",
		&"autocannon_turret", &"relay_station", &"refinery"]
	for k: int in n:
		var c: Vector3 = centres[k % 4]
		var d: Vector3 = (c + random_dir(rng) * rng.range_f(0.0, 5000.0 / R)).normalized()
		var team: int = rng.range_i(-1, 3)
		var ship: bool = rng.next_float() < 0.45
		var def: StringName = ships[rng.range_i(0, ships.size() - 1)] if ship else others[rng.range_i(0, others.size() - 1)]
		var alt: float = rng.range_f(-300.0, 1800.0) if ship else rng.range_f(-400.0, 300.0)
		var kind: int = EntityStore.K_WRECK if rng.next_float() < 0.1 else -1
		var _id: int = put(w, def, team, d * (R + alt), kind)
