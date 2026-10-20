class_name CollisionTestKit extends RefCounted
## Shared world for the Spatial / Collision tests and the collision benchmark (TA-14): one EntityStore,
## ProjectileStore, Spatial, Terrain and Collision wired as SimWorld steps 6-8 will wire them. Def values come from
## the canonical fixture (never literals). Pad def id PAD_DEF has the fixture pad radius. Self-contained (no
## FlightTestKit / ContentLoader reference) so `-s` benchmarks without autoloads can use it.

const DEFS_DIR: String = "../tools/tests/fixtures/content/canonical/godot/content/defs/"
const PAD_DEF: int = 1
const PLAIN_DEF: int = 2
const LAUNCH_DEF: int = 3     ## a `launch_pad: true` structure (A-19, A-87)

var store: EntityStore
var proj: ProjectileStore
var spatial: Spatial
var terrain: Terrain
var collision: Collision
var common: FlightCommonDef
var rules: RulesDef
var dt: float
var pad_radius: float
var p_ids: PackedStringArray = PackedStringArray()


func _init(map_dir: String = "") -> void:
	store = EntityStore.new()
	proj = ProjectileStore.new(ProjectileStore.SLOT_COUNT)
	spatial = Spatial.new(store, proj)
	terrain = Terrain.new()
	if not map_dir.is_empty():
		var err: Error = terrain.load_map(map_dir)
		assert(err == OK)
	collision = Collision.new(store, proj, spatial, terrain)
	common = FlightCommonDef.from_dict(load_json("ships.json")["flight_common"] as Dictionary)
	rules = RulesDef.from_dict(load_json("rules.json"))
	dt = 1.0 / float(rules.tick_hz)
	var radii: PackedFloat32Array = PackedFloat32Array()
	for e: Variant in load_json("projectiles.json")["projectiles"] as Array:
		var d: Dictionary = e as Dictionary
		var _a: bool = p_ids.push_back(str(d["id"]))
		var _b: bool = radii.push_back(float(d.get("radius_m", 0.0)))
	pad_radius = _fixture_pad_radius()
	var pads: PackedFloat32Array = PackedFloat32Array([0.0, pad_radius, 0.0])
	collision.configure(radii, pads, common, rules.tick_hz)
	collision.launch_pad = PackedByteArray([0, 0, 0, 1])


static func load_json(file: String) -> Dictionary:
	var path: String = ProjectSettings.globalize_path("res://").path_join(DEFS_DIR + file)
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary


## The fixture ProjectileDef with `id`.
func projectile_def(id: String) -> ProjectileDef:
	for e: Variant in load_json("projectiles.json")["projectiles"] as Array:
		var d: Dictionary = e as Dictionary
		if str(d["id"]) == id:
			return ProjectileDef.from_dict(d)
	assert(false, "no projectile " + id)
	return null


func def_index(id: String) -> int:
	return p_ids.find(id)


## A live entity of `kind` at `p`; up = radial, fwd = local east. Returns the slot.
func entity(kind: int, p: Vector3, radius: float, team: int, def_id: int = PLAIN_DEF) -> int:
	var s: int = EntityId.slot(store.alloc(kind, 0))
	assert(s > 0)
	store.pos[s] = p
	store.radius[s] = radius
	store.team[s] = team
	store.owner[s] = team
	store.def_id[s] = def_id
	store.up[s] = p.normalized()
	store.fwd[s] = Sphere.tangent_frame(p).x
	return s


## A live projectile of fixture def `id` at `p` with velocity `v` (prev_pos = p). Returns the local index.
func projectile(id: String, p: Vector3, v: Vector3, team: int, shooter: int = EntityId.NULL_ID) -> int:
	var i: int = proj.index_of(proj.alloc(ProjectileStore.SLUG, 0))
	assert(i >= 0)
	proj.pos[i] = p
	proj.prev_pos[i] = p
	proj.vel[i] = v
	proj.team[i] = team
	proj.projectile_def[i] = def_index(id)
	proj.shooter[i] = shooter
	return i


## Step 6 for straight projectiles (prev_pos, then p += v dt), step 7, step 8.
func tick(t: int, def: ProjectileDef) -> void:
	for i: int in proj.live:
		var ps: ProjectileState = Kinematics.step_projectile(proj.pos[i], proj.vel[i], def, rules, dt)
		proj.prev_pos[i] = proj.pos[i]
		proj.pos[i] = ps.p
		proj.vel[i] = ps.v
	spatial.rebuild()
	collision.step(t)


## Steps 7-8 only.
func detect(t: int) -> void:
	spatial.rebuild()
	collision.step(t)


func count(kind: int) -> int:
	var n: int = 0
	for k: int in collision.contact_count:
		if collision.c_kind[k] == kind:
			n += 1
	return n


## Index of the first contact of `kind`, or -1.
func first(kind: int) -> int:
	for k: int in collision.contact_count:
		if collision.c_kind[k] == kind:
			return k
	return -1


func _fixture_pad_radius() -> float:
	for e: Variant in load_json("structures.json")["structures"] as Array:
		var d: Dictionary = e as Dictionary
		if str(d["id"]) == "pad":
			return float(d["pad_radius_m"])
	assert(false, "fixture has no pad")
	return 0.0
