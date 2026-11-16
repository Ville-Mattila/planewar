class_name ThreatData extends RefCounted
## Threat ring data of one ship, read only through SimView (docs/06 s6.1, UX-19; refresh 10 Hz by the host).

var arrows: Array[ThreatArrow] = []
var rocket_lock: bool = false
var rockets: int = 0


## Hostile (other team), visible entities within hud.json `threat_range_m`, nearest first, at most `threat_max_arrows`.
static func from_view(v: SimView, ship: int, team: int) -> ThreatData:
	var d: ThreatData = ThreatData.new()
	d.rockets = v.incoming_rockets(ship)
	d.rocket_lock = d.rockets > 0
	if not v.alive(ship):
		return d
	var p: Vector3 = v.pos(ship)
	var b: Basis = v.basis(ship)
	var range_m: float = HudMath.param("threat_range_m")
	var ids: PackedInt32Array = v.ids_near(p, range_m, int(HudMath.param("threat_mask")))
	for id: int in ids:
		if id == ship or v.team(id) == team or not v.visible_to(team, id):
			continue
		var rel: Vector3 = v.pos(id) - p
		var a: ThreatArrow = ThreatArrow.new()
		a.id = id
		a.dist = rel.length()
		a.angle = ThreatMath.angle(rel, b)
		a.intensity = ThreatMath.intensity(a.dist, range_m)
		a.ahead = ThreatMath.ahead(rel, b)
		d.arrows.append(a)
	d.arrows.sort_custom(func(x: ThreatArrow, y: ThreatArrow) -> bool: return x.dist < y.dist)
	var cap: int = int(HudMath.param("threat_max_arrows"))
	if d.arrows.size() > cap:
		var _r: int = d.arrows.resize(cap)
	return d
