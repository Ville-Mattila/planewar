class_name VfxPool
extends Node3D
## Pooled one-shot effects (03 s10.1, 07 s6): a fixed set of hidden nodes created at setup, recycled oldest-first
## when the pool is full, never freed. Each effect id has one shared additive material (colour and intensity from
## `VfxCatalog`); an effect swells over its life and shrinks away over the last third. Placeholder shapes until the
## real effect scenes land. Counters let tests and the pre-warm see what happened.

const DEFAULT_CAPACITY: int = 64
const SHRINK_FRACTION: float = 0.33
const RING_TUBE: float = 0.08

var spawned_total: int = 0
var last_id: StringName = &""
var counts: Dictionary = {}   ## effect id -> spawns since setup (tests, pre-warm)

var _nodes: Array[MeshInstance3D] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _size: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _materials: Dictionary = {}   ## id -> ShaderMaterial
var _meshes: Array[Mesh] = []


func setup(max_effects: int = DEFAULT_CAPACITY) -> void:
	var _r1: int = _meshes.resize(4)
	var sph: SphereMesh = SphereMesh.new()
	sph.radial_segments = 8
	sph.rings = 4
	_meshes[VfxCatalog.Shape.SPHERE] = sph
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 1.0 - RING_TUBE
	ring.outer_radius = 1.0
	ring.rings = 12
	ring.ring_segments = 4
	_meshes[VfxCatalog.Shape.RING] = ring
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.radial_segments = 8
	cone.rings = 1
	_meshes[VfxCatalog.Shape.CONE] = cone
	_meshes[VfxCatalog.Shape.QUAD] = PlaceholderMeshes.crossed_quads()
	for i: int in max_effects:
		var n: MeshInstance3D = MeshInstance3D.new()
		n.visible = false
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		_nodes.append(n)
	var _r2: int = _age.resize(max_effects)
	var _r3: int = _life.resize(max_effects)
	var _r4: int = _size.resize(max_effects)
	_life.fill(0.0)


func capacity() -> int:
	return _nodes.size()


func active_count() -> int:
	var c: int = 0
	for i: int in _nodes.size():
		if _nodes[i].visible:
			c += 1
	return c


## The shared material of an effect id (also what the pre-warm touches).
func material_for(id: StringName) -> ShaderMaterial:
	if _materials.has(id):
		return _materials[id]
	var m: ShaderMaterial = PoolMaterials.make_additive()
	m.set_shader_parameter(&"tint", VfxCatalog.color(id))
	m.set_shader_parameter(&"intensity", VfxCatalog.intensity(id))
	_materials[id] = m
	return m


## Spawns effect `id` at `pos` (world), `scale` multiplies its catalog size; false for an unknown id.
func spawn(id: StringName, pos: Vector3, scale_mult: float = 1.0, up: Vector3 = Vector3.ZERO) -> bool:
	if not VfxCatalog.has(id) or _nodes.is_empty():
		return false
	var i: int = _next
	_next = (_next + 1) % _nodes.size()
	var n: MeshInstance3D = _nodes[i]
	n.mesh = _meshes[VfxCatalog.shape(id)]
	n.material_override = material_for(id)
	_age[i] = 0.0
	_life[i] = VfxCatalog.life_s(id)
	_size[i] = VfxCatalog.size_m(id) * scale_mult
	var u: Vector3 = up if up != Vector3.ZERO else pos.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(u.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = u.cross(ref).normalized()
	n.transform = Transform3D(Basis(x, u, x.cross(u)).scaled(Vector3.ONE * _size[i] * 0.1), pos)
	n.visible = true
	spawned_total += 1
	last_id = id
	var prior: int = counts.get(id, 0)
	counts[id] = prior + 1
	return true


## Hides every live effect (after the pre-warm).
func clear() -> void:
	for n: MeshInstance3D in _nodes:
		n.visible = false


## Advances every live effect by `delta` seconds.
func update(delta: float) -> void:
	for i: int in _nodes.size():
		var n: MeshInstance3D = _nodes[i]
		if not n.visible:
			continue
		_age[i] += delta
		var t: float = _age[i] / maxf(_life[i], 0.001)
		if t >= 1.0:
			n.visible = false
			continue
		var grow: float = 0.1 + 0.9 * sqrt(t)
		var fade: float = 1.0 if t < 1.0 - SHRINK_FRACTION else (1.0 - t) / SHRINK_FRACTION
		n.scale = Vector3.ONE * (_size[i] * grow * fade)
