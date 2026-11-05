class_name HarvestTestKit extends RefCounted
## Fixtures for the GD-12 tests: the EconomyTestKit world (flat datum, no start kit) with a Refinery at arc 0 along +Y
## from +X, Ore Fields and Harvesters placed by metres of arc, and a straight-line driver standing in for the AI-16 brain
## (it turns toward its next stop while mining / unloading, so the trip time carries no turn penalty).

const R: float = Sphere.PLANET_RADIUS
const DT: float = 1.0 / 30.0


static func world(exposure_s: float = -1.0) -> SimWorld:
	return EconomyTestKit.solo_world(false, 7, WorldTestKit.rules(exposure_s))


static func dir_at(east: float) -> Vector3:
	return Vector3(cos(east / R), sin(east / R), 0.0)


static func refinery(w: SimWorld, east: float = 0.0) -> int:
	return SalvageTestKit.put(w, &"refinery", 0, 0, 0.0, east)


static func harvester(w: SimWorld, east: float, owner: int = 0) -> int:
	return SalvageTestKit.put(w, &"harvester", owner, w._players.team[owner], 0.0, east)


static func field(w: SimWorld, east: float, capacity: int = 6000, regen: float = 2.0, radius: float = 150.0,
		max_miners: int = 4) -> int:
	return w.economy().harvest.fields.add(dir_at(east), capacity, regen, radius, max_miners)


static func step(w: SimWorld, n: int) -> void:
	for _i: int in n:
		w.step()


static func state(w: SimWorld, h: int) -> int:
	return w.store().cargo_kind[h]


static func delivered(w: SimWorld, player: int = 0) -> int:
	return w.economy().build.delivered_ore[player]


## Aim `h` at `target` (a unit direction): yaw toward it, full thrust when `go`, the heading is within 0.2 rad and the
## target is further than `stop_m`. Returns the arc distance in metres.
static func steer(w: SimWorld, h: int, target: Vector3, go: bool, stop_m: float = 0.45) -> float:
	var st: EntityStore = w.store()
	var n: Vector3 = st.pos[h].normalized()
	var arc: float = acos(clampf(n.dot(target), -1.0, 1.0)) * R
	var t: Vector3 = target - n * target.dot(n)
	t = t.normalized() if t.length_squared() > 0.0 else st.fwd[h]
	var f: Vector3 = st.fwd[h]
	var err: float = atan2(f.cross(t).dot(n), f.dot(t))
	var rate: float = deg_to_rad(w._defs.ground_common.ground_turn_rate_dps) * DT
	w._inputs.e_yaw[h] = clampf(err / rate, -1.0, 1.0)
	w._inputs.e_thrust[h] = 1.0 if (go and arc > stop_m and absf(err) < 0.2) else 0.0
	return arc


## One tick of the stand-in brain between `field_dir` and `dock_dir`, then steps the world. At a stop it aims at the
## next one without moving; it leaves the field when the cargo is full and the dock when it is empty.
static func drive_cycle(w: SimWorld, h: int, field_dir: Vector3, dock_dir: Vector3, cap: float) -> void:
	var c: float = w.store().cargo[h]
	var n: Vector3 = w.store().pos[h].normalized()
	var at_field: bool = acos(clampf(n.dot(field_dir), -1.0, 1.0)) * R <= 0.5
	var at_dock: bool = acos(clampf(n.dot(dock_dir), -1.0, 1.0)) * R <= 0.5
	var loaded: bool = c >= cap - 0.01
	if (at_field and not loaded) or (at_dock and c > 0.0):
		var _a: float = steer(w, h, dock_dir if at_field else field_dir, false)
	else:
		var _b: float = steer(w, h, dock_dir if c > 0.0 else field_dir, true)
	w.step()
