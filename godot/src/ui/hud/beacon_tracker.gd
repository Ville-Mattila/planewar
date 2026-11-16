class_name BeaconTracker extends RefCounted
## Deployed team Supply Canisters (SL-5): a marker and a compass pip each (docs/06 s6.1, s7.4, UX-19). Event driven:
## CANISTER_DEPLOYED (a = canister, pos) adds, CANISTER_COLLECTED (a = canister) removes.

var _ids: PackedInt32Array = PackedInt32Array()
var _pos: PackedVector3Array = PackedVector3Array()


func on_event(e: SimEvent, local_team: int) -> void:
	if e.kind == SimEvent.Kind.CANISTER_DEPLOYED:
		if e.team != local_team or _ids.has(e.a):
			return
		var _i: bool = _ids.append(e.a)
		var _p: bool = _pos.append(e.pos)
	elif e.kind == SimEvent.Kind.CANISTER_COLLECTED:
		var i: int = _ids.find(e.a)
		if i >= 0:
			_ids.remove_at(i)
			_pos.remove_at(i)


func count() -> int:
	return _ids.size()


func clear() -> void:
	_ids.clear()
	_pos.clear()


## World positions for the presentation marker.
func positions() -> PackedVector3Array:
	return _pos


## Compass pips for a ship at `ship_pos` heading `heading_deg`; one is pinned to the tape edge when its bearing is
## outside the `span_deg` window. Nearest first.
func pips(ship_pos: Vector3, heading_deg: float, width_du: float, span_deg: float) -> Array[BeaconPip]:
	var out: Array[BeaconPip] = []
	var n: Vector3 = ship_pos.normalized()
	for i: int in _ids.size():
		var rel: Vector3 = _pos[i] - ship_pos
		var bearing: float = HudMath.heading_deg(rel, n)
		if is_nan(bearing) or is_nan(heading_deg):
			continue
		var p: BeaconPip = BeaconPip.new()
		p.canister = _ids[i]
		p.pos = _pos[i]
		p.dist = rel.length()
		p.x = HudMath.tape_x(bearing, heading_deg, width_du, span_deg)
		var edge: float = width_du * 0.5
		p.on_tape = absf(p.x) <= edge
		p.x = clampf(p.x, -edge, edge)
		out.append(p)
	out.sort_custom(func(a: BeaconPip, b: BeaconPip) -> bool: return a.dist < b.dist)
	return out
