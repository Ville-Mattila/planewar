class_name SwarmWorld extends SimView
## AI-11 swarm rig: N free-flying ships stepped by Kinematics.step_ship over a flat datum, each flown by
## FlightController on a guidance velocity = waypoint heading + Separation (the think / act split of 05 s4.3, think every
## `think_period` ticks; the separation term is refreshed every second think, as EscortPilot does). A SimView with the accessors Separation reads (brute-force `ids_near` in index order, so this rig does not exercise the hash order or the ring path); collisions are
## centre distances below the sum of the bounding radii (what Collision.ram tests). Not a contract.

var common: FlightCommonDef
var rules: RulesDef
var terrain: Terrain
var prm: FormationParams
var think_period: int = 10
var now: int = 0
var ids: PackedInt32Array = PackedInt32Array()
var ss: Array[ShipState] = []
var defs: Array[ShipDef] = []
var gains: Array[FlightGains] = []
var teams: PackedInt32Array = PackedInt32Array()
var goal: PackedVector3Array = PackedVector3Array()      ## guidance velocity per ship (think output)
var integ: PackedVector2Array = PackedVector2Array()
var sep_term: PackedVector3Array = PackedVector3Array()  ## cached Separation.push, refreshed every second think like EscortPilot
var thinks: int = 0
var waypoint: PackedVector3Array = PackedVector3Array()  ## current waypoint (a point at the flight level)
var leg: PackedInt32Array = PackedInt32Array()           ## waypoint index per ship
var min_gap: float = INF                                 ## smallest surface gap between two same-team ships so far
var collisions: int = 0
var first_collision_tick: int = -1
var first_info: String = ""
var first_pair: Vector2i = Vector2i(-1, -1)
var _inp: PilotInput = PilotInput.new()


func _init(flight_common: FlightCommonDef, rules_def: RulesDef, params: FormationParams) -> void:
	common = flight_common
	rules = rules_def
	prm = params
	terrain = Terrain.new()


func add_ship(def: ShipDef, g: FlightGains, s: ShipState, team_id: int = 0) -> int:
	var id: int = EntityId.make(1 + ids.size(), 1)
	var _r: Array[bool] = [ids.push_back(id), teams.push_back(team_id), goal.push_back(Vector3.ZERO),
		integ.push_back(Vector2.ZERO), sep_term.push_back(Vector3.ZERO), waypoint.push_back(s.p), leg.push_back(0)]
	ss.append(s)
	defs.append(def)
	gains.append(g)
	return id


## Think for ship `i`: fly to `waypoint[i]` (tangent heading at `speed`, level) plus separation.
func think(i: int, speed: float) -> void:
	var s: ShipState = ss[i]
	var up: Vector3 = s.p.normalized()
	var to: Vector3 = waypoint[i] - s.p
	var tang: Vector3 = (to - up * to.dot(up)).normalized()
	var vz: float = clampf(0.5 * (waypoint[i].length() - s.p.length()), -10.0, 10.0)
	if (thinks + i) % 2 == 0:   # the neighbour query runs every second think (05 s10 think row)
		sep_term[i] = Separation.push(ids[i], s.p, s.v, teams[i], self, prm)
	goal[i] = tang * speed + up * vz + sep_term[i]


func act_and_step(i: int) -> void:
	var s: ShipState = ss[i]
	integ[i] = FlightController.track_velocity(basis(ids[i]), s.v, goal[i], s.p.normalized(), gains[i], integ[i], _inp)
	var _r: ShipState = Kinematics.step_ship(s, _inp, defs[i], common, rules, terrain, 1.0 / float(rules.tick_hz))


## Records the closest approach and counts overlapping same-team pairs (once per tick per pair).
func check_collisions() -> void:
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			if teams[i] != teams[j]:
				continue
			var gap: float = ss[i].p.distance_to(ss[j].p) - defs[i].bounding_radius - defs[j].bounding_radius
			min_gap = minf(min_gap, gap)
			if gap < 0.0:
				collisions += 1
				if first_collision_tick < 0:
					first_collision_tick = now
					first_pair = Vector2i(i, j)
					first_info = "%s/%s rel v %.0f m/s, speeds %.0f %.0f, gap %.1f" % [defs[i].id, defs[j].id, (ss[i].v - ss[j].v).length(), ss[i].v.length(), ss[j].v.length(), gap]


func alive(id: int) -> bool:
	return id > 0 and EntityId.slot(id) - 1 < ids.size() and ids[EntityId.slot(id) - 1] == id


func pos(id: int) -> Vector3:
	return ss[EntityId.slot(id) - 1].p


func vel(id: int) -> Vector3:
	return ss[EntityId.slot(id) - 1].v


func basis(id: int) -> Basis:
	var s: ShipState = ss[EntityId.slot(id) - 1]
	return Basis(s.fwd.cross(s.up), s.up, -s.fwd)


func team(id: int) -> int:
	return teams[EntityId.slot(id) - 1]


func radius(id: int) -> float:
	return defs[EntityId.slot(id) - 1].bounding_radius


func tick() -> int:
	return now


func ids_near(p: Vector3, radius_m: float, _mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in ids.size():
		if ss[i].p.distance_squared_to(p) <= radius_m * radius_m:
			var _b: bool = out.push_back(ids[i])
	return out
