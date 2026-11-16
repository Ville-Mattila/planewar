class_name HarvestPicker extends RefCounted
## The Harvester's PICK_FIELD choice point (GD-12; 05 s6.6, 02 s8.2): which Ore Field a Harvester drives to next, in
## particular where it re-targets when its field is depleted or full of miners. A pure function over a team picture the
## brain builds from `SimView.field_remaining` and the map's field table: no world access, no state, no allocation.
## The utility is 05's `remaining01 / (1 + path_len_km) / (1 + w * harvesters_assigned) * (1 - risk01)`, with the
## great-circle distance standing in for the path length (the brain replaces it with its A* length when it has one).


## 05 s6.6 U. `assigned_weight` is the autopilot's `0.5` (a parameter, not a literal here).
static func utility(remaining01: float, path_len_m: float, assigned: int, risk01: float, assigned_weight: float) -> float:
	return remaining01 / (1.0 + path_len_m / 1000.0) / (1.0 + assigned_weight * float(assigned)) * (1.0 - risk01)


## Index of the field with the highest utility among those with Ore left (`remaining01` > 0) and a free miner slot
## (`free_slots` > 0), skipping `avoid` (the field just left; -1 for none). Ties take the lowest index; -1 when none.
static func pick(from_dir: Vector3, dirs: PackedVector3Array, remaining01: PackedFloat32Array, free_slots: PackedInt32Array,
		assigned: PackedInt32Array, assigned_weight: float, avoid: int) -> int:
	var best: int = -1
	var best_u: float = 0.0
	for i: int in dirs.size():
		if i == avoid or remaining01[i] <= 0.0 or free_slots[i] <= 0:
			continue
		var arc: float = acos(clampf(from_dir.dot(dirs[i]), -1.0, 1.0)) * Sphere.PLANET_RADIUS
		var u: float = utility(remaining01[i], arc, assigned[i], 0.0, assigned_weight)
		if best < 0 or u > best_u:
			best = i
			best_u = u
	return best
