class_name SfLanding
## Tail-down landing rule and ship-vs-terrain classification for the stub pad (03 s6.1, s6.4; R0 B.5, O-2).
## A ship lands on the pad when, in one tick: horizontal offset <= pad_radius_m, altitude above the pad
## <= bounding_radius + 0.5, sink <= landing_safe_v_vert, tangential speed <= landing_safe_v_hor and the thrust
## axis (body forward) within landing_safe_pitch_deg of the pad normal. Between the safe and the damage limits
## the ship still lands with hull damage; beyond any damage limit it is destroyed. No level-landing variant.


## Is the ship in the pad's landing volume this tick (03 s6.4 "over the pad" and "at the pad")?
static func in_pad_volume(p: Vector3, pad_p: Vector3, pad_n: Vector3, d: SfDefs) -> bool:
	var rel: Vector3 = p - pad_p
	var h: float = rel.dot(pad_n)
	var off: float = (rel - pad_n * h).length()
	return off <= d.pad_radius_m and h <= d.ship.bounding_radius + SfDefs.num(d.landing, "pad_contact_margin_m")


## Classify one contact. `sink` is the speed into the ground before the push-out (ShipState.hit_normal_speed
## when the probe fired, else -v.n). `manual` = no assist tick in the final approach (grade AUTO otherwise).
static func evaluate(p: Vector3, v: Vector3, fwd: Vector3, sink: float, pad_p: Vector3, pad_n: Vector3,
		on_pad_volume: bool, manual: bool, d: SfDefs, out: SfTouchdown) -> SfTouchdown:
	var rel: Vector3 = p - pad_p
	out.offset_m = (rel - pad_n * rel.dot(pad_n)).length()
	out.on_pad = on_pad_volume
	out.v_vert = sink
	out.v_hor = (v - pad_n * v.dot(pad_n)).length()
	out.tilt_deg = rad_to_deg(fwd.angle_to(pad_n))
	out.damage_hp = 0.0
	out.q = 0.0
	out.grade = -1
	if not on_pad_volume:
		return _terrain(out, d)
	var c: FlightCommonDef = d.common
	var tilt_dmg: float = SfDefs.num(d.landing, "tilt_damage_deg")
	if out.v_vert > c.landing_damage_v_vert or out.v_hor > c.landing_damage_v_hor or out.tilt_deg > tilt_dmg:
		out.outcome = SfTouchdown.Outcome.CRASH
		out.grade = SfTouchdown.GRADE_CRASH
		out.damage_hp = d.hp_max
		return out
	var r_vert: float = _ratio(out.v_vert, c.landing_safe_v_vert, c.landing_damage_v_vert)
	var r_hor: float = _ratio(out.v_hor, c.landing_safe_v_hor, c.landing_damage_v_hor)
	var r_tilt: float = _ratio(out.tilt_deg, c.landing_safe_pitch_deg, tilt_dmg)
	var ratio: float = maxf(r_vert, maxf(r_hor, r_tilt))
	out.q = quality(out, d)
	if ratio > 0.0:
		out.outcome = SfTouchdown.Outcome.HARD
		out.damage_hp = d.hp_max * ratio
		out.grade = SfTouchdown.GRADE_BENT
	else:
		out.outcome = SfTouchdown.Outcome.LANDED
		out.grade = grade_of(out.q, d) if manual else SfTouchdown.GRADE_AUTO
	return out


## q = 0.35 (1 - v_vert/8) + 0.25 (1 - v_hor/15) + 0.20 (1 - tilt/25) + 0.20 (1 - offset/pad_radius), terms
## clamped to [0, 1] (03 s6.4, weights from spike_flight.json landing).
static func quality(t: SfTouchdown, d: SfDefs) -> float:
	var c: FlightCommonDef = d.common
	var l: Dictionary = d.landing
	return (SfDefs.num(l, "q_w_vert") * clampf(1.0 - t.v_vert / c.landing_safe_v_vert, 0.0, 1.0)
		+ SfDefs.num(l, "q_w_hor") * clampf(1.0 - t.v_hor / c.landing_safe_v_hor, 0.0, 1.0)
		+ SfDefs.num(l, "q_w_tilt") * clampf(1.0 - t.tilt_deg / c.landing_safe_pitch_deg, 0.0, 1.0)
		+ SfDefs.num(l, "q_w_offset") * clampf(1.0 - t.offset_m / d.pad_radius_m, 0.0, 1.0))


static func grade_of(q: float, d: SfDefs) -> int:
	if q >= SfDefs.num(d.landing, "grade_ace"):
		return SfTouchdown.GRADE_ACE
	if q >= SfDefs.num(d.landing, "grade_clean"):
		return SfTouchdown.GRADE_CLEAN
	if q >= SfDefs.num(d.landing, "grade_fair"):
		return SfTouchdown.GRADE_FAIR
	return SfTouchdown.GRADE_HARD


# 03 s6.1 ship vs terrain off the pad: kill above terrain_kill_speed, damage band, else scrape.
static func _terrain(out: SfTouchdown, d: SfDefs) -> SfTouchdown:
	var c: FlightCommonDef = d.common
	if out.v_vert > c.terrain_kill_speed:
		out.outcome = SfTouchdown.Outcome.CRASH
		out.damage_hp = d.hp_max
	elif out.v_vert > c.terrain_damage_speed:
		out.outcome = SfTouchdown.Outcome.DAMAGED
		out.damage_hp = d.hp_max * (out.v_vert - c.terrain_damage_speed) / (c.terrain_kill_speed - c.terrain_damage_speed)
	else:
		out.outcome = SfTouchdown.Outcome.SCRAPE
		out.damage_hp = SfDefs.num(d.landing, "scrape_hp")
	return out


static func _ratio(x: float, safe: float, dmg: float) -> float:
	return clampf((x - safe) / (dmg - safe), 0.0, 1.0)
