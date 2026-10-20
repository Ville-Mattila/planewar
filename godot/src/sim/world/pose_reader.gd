class_name PoseReader extends RefCounted
## `SimView.read_poses` for a local world (extracted from `LocalSimView`, A-73): position and rotation quaternion per
## id; entities from the store, projectiles from the projectile store, dead ids zeroed. Returns the live count.


static func read(store: EntityStore, proj: ProjectileStore, ids: PackedInt32Array, pos: PackedVector3Array,
		rot: PackedVector4Array) -> int:
	var n_alive: int = 0
	for i: int in ids.size():
		var id: int = ids[i]
		if store.alive(id):
			var s: int = EntityId.slot(id)
			var f: Vector3 = store.fwd[s]
			var u: Vector3 = store.up[s]
			var q: Quaternion = Basis(f.cross(u), u, -f).get_rotation_quaternion()
			pos[i] = store.pos[s]
			rot[i] = Vector4(q.x, q.y, q.z, q.w)
			n_alive += 1
		elif EntityId.is_projectile(id) and proj.alive(id):
			pos[i] = proj.pos[proj.index_of(id)]
			rot[i] = Vector4(0.0, 0.0, 0.0, 1.0)
			n_alive += 1
		else:
			pos[i] = Vector3.ZERO
			rot[i] = Vector4(0.0, 0.0, 0.0, 1.0)
	return n_alive
