class_name StubSimView
extends SimView
## Scripted SimView for the presentation tests: entities by id with position, basis, def, team, hp and radius.
## `advance()` bumps the tick the way `SimWorld.step()` does.

var tick_no: int = 1
var ids: PackedInt32Array = PackedInt32Array()
var positions: Dictionary = {}   ## id -> Vector3
var defs: Dictionary = {}        ## id -> def_id
var teams: Dictionary = {}       ## id -> team
var hps: Dictionary = {}         ## id -> hp01
var radii: Dictionary = {}       ## id -> metres
var velocities: Dictionary = {}  ## id -> Vector3


func put(slot: int, p: Vector3, def: int, team: int = 0, r: float = 6.0, hp: float = 1.0, wreck: bool = false) -> int:
	var id: int = EntityId.make(EntityId.WRECK_SLOT_MIN + slot if wreck else slot + 1, 1)
	var _a: bool = ids.push_back(id)
	positions[id] = p
	defs[id] = def
	teams[id] = team
	hps[id] = hp
	radii[id] = r
	return id


func advance() -> void:
	tick_no += 1


func alive(id: int) -> bool:
	return positions.has(id)


func tick() -> int:
	return tick_no


func visible_ids(_team: int) -> PackedInt32Array:
	return ids


func pos(id: int) -> Vector3:
	return positions.get(id, Vector3.ZERO)


func vel(id: int) -> Vector3:
	return velocities.get(id, Vector3.ZERO)


func basis(id: int) -> Basis:
	return Basis.IDENTITY if positions.has(id) else Basis.IDENTITY


func def_id(id: int) -> int:
	return defs.get(id, -1)


func team(id: int) -> int:
	return teams.get(id, -1)


func hp01(id: int) -> float:
	return hps.get(id, 0.0)


func radius(id: int) -> float:
	return radii.get(id, 0.0)
