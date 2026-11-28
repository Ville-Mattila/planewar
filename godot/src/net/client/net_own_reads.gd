class_name NetOwnReads extends RefCounted
## NetSimView's own-unit pilot-block reads and TEAM_STATE reads (04 s3.7), split out of net_sim_view.gd (NET-62). Static: each takes
## the view; a pilot field answers the SimView default unless `id` is the own possessed unit with a pilot block (view.own_index()).


static func _own_i(v: NetSimView, id: int) -> int:
	var i: int = v.index_of(id)
	return i if i >= 0 and i == v.own_index() else -1


static func fuel01(v: NetSimView, id: int) -> float:
	var i: int = _own_i(v, id)
	if i < 0 or not v.defs.valid(v.roster.def_of(i)):
		return 0.0
	var s: float = v.defs.fuel_s[v.roster.def_of(i)]
	return clampf(float(v.decoder.pilot.fuel_ds) * NetSimView.FUEL_DS / s, 0.0, 1.0) if s > 0.0 else 0.0


static func ammo(v: NetSimView, id: int) -> int:
	return v.decoder.pilot.ammo if _own_i(v, id) >= 0 else 0


static func bombs(v: NetSimView, id: int) -> int:
	return v.decoder.pilot.bombs if _own_i(v, id) >= 0 else 0


static func rockets(v: NetSimView, id: int) -> int:
	return v.decoder.pilot.rockets if _own_i(v, id) >= 0 else 0


static func incoming_rockets(v: NetSimView, id: int) -> int:
	return v.decoder.pilot.incoming_rockets if _own_i(v, id) >= 0 else 0


static func boost_state(v: NetSimView, id: int) -> int:
	return v.decoder.pilot.boost_state & NetSimView.BOOST_MASK if _own_i(v, id) >= 0 else 0


static func boost_cooldown01(v: NetSimView, id: int) -> float:
	return v.decoder.pilot.boost_cooldown01() if _own_i(v, id) >= 0 else 0.0


static func flip_cooldown01(v: NetSimView, id: int) -> float:
	return float(v.decoder.pilot.flip_cooldown) / NetSimView.BYTE_MAX if _own_i(v, id) >= 0 else 0.0


static func dock_state(v: NetSimView, id: int) -> int:
	var i: int = v.index_of(id)
	if i >= 0 and i == v.own_index():
		return v.decoder.pilot.dock_state
	return 0 if i < 0 else Protocol.DockState.DOCKED if (v.flags_byte(i) & Codec.FLAG_DOCKED) != 0 else Protocol.DockState.FLYING


static func service_progress(v: NetSimView, id: int) -> Vector3:
	return v.decoder.pilot.service01() if _own_i(v, id) >= 0 else Vector3.ZERO


## TEAM_STATE (own team): ore, ice and the power ratio; other teams ZERO (unknown).
static func stockpile(v: NetSimView, t: int) -> Vector3:
	if not v.team_flags_known(t):
		return Vector3.ZERO
	var s: float = float(v.team_wire.power_supply)
	var d: float = float(v.team_wire.power_demand)
	return Vector3(float(v.team_wire.ore), float(v.team_wire.ice), 1.0 if d <= 0.0 else minf(s / d, 1.0))


static func stockpile_cap(v: NetSimView, t: int) -> Vector2i:
	return Vector2i(v.team_wire.ore_cap, v.team_wire.ice_cap) if v.team_flags_known(t) else Vector2i.ZERO


static func power_balance(v: NetSimView, t: int) -> Vector2:
	return Vector2(float(v.team_wire.power_supply), float(v.team_wire.power_demand)) if v.team_flags_known(t) else Vector2.ZERO


static func unit_count(v: NetSimView, player: int) -> int:
	var k: int = v.team_wire.member_index(player) if v.team_wire.tick > 0 else -1
	return v.team_wire.member_units[k] if k >= 0 else 0
