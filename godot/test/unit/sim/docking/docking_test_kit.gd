class_name DockingTestKit extends RefCounted
## Shared fixtures for the GD-15 tests: a WorldTestKit world (players 0 and 2 on team 0, 1 on team 1), service pads and
## ships spawned through DEBUG_SPAWN and then posed tail-down over a pad, crafted PAD contacts handed straight to
## `Docking.land` (exact speeds for the band / grade boundaries), and docked ships for the service timers. Values come
## from the shipped defs (WorldTestKit.content), never literals.

const HIGH: float = 1000.0          ## spawn altitude (below the 1,950 m uplink): clear of everything until posed


static func content() -> ContentSet:
	return WorldTestKit.content()


static func common() -> FlightCommonDef:
	return content().flight_common


## economy.pad_queue_radius_m (R0 B.24 A-125): the horizontal queue zone around a busy pad.
static func queue_radius() -> float:
	return Def.num(content().economy.raw.get("pad_queue_radius_m", 0.0))


## flight_common.crash_pad_damage (R0 B.24 A-120): what a pad takes when a ship crashes on it.
static func crash_pad_damage() -> float:
	return Def.num(common().raw.get("crash_pad_damage", 0.0))


static func ship_def(id: StringName) -> ShipDef:
	return content().ships[WorldTestKit.def_id(id) - DefRanges.SHIP_BASE]


static func pad_radius(w: SimWorld, pad: int) -> float:
	return content().structures[w.store().def_id[EntityId.slot(pad)] - DefRanges.STRUCTURE_BASE].pad_radius_m


## A finished structure `def` of `owner` / `team` on the datum at `east` metres along +Y of the +X axis.
static func pad(w: SimWorld, def: StringName = &"pad", owner: int = 0, team: int = 0, east: float = 0.0) -> int:
	return WorldTestKit.spawn(w, def, owner, team, WorldTestKit.at(0.0, east))


static var _far_n: int = 0


## A parking point on the far side of the moon (the -X axis), `HIGH` above the datum, 60 m apart per call.
static func far(_w: SimWorld) -> Vector3:
	_far_n = (_far_n + 1) % 400
	return Vector3(-(WorldTestKit.R + HIGH), float(_far_n - 200) * 60.0, 0.0)


## A ship `def` posed tail-down (nose along the pad normal) `alt` metres above `pad`'s plane, `off` metres east of its
## centre, velocity `v`. Spawned high first (the spawn step must not touch the pad).
static func ship_over(w: SimWorld, def: StringName, owner: int, team: int, pad_id: int, alt: float, off: float = 0.0,
		v: Vector3 = Vector3.ZERO) -> int:
	var id: int = WorldTestKit.spawn(w, def, owner, team, far(w))
	pose(w, id, pad_id, alt, off, v)
	return id


static func pose(w: SimWorld, id: int, pad_id: int, alt: float, off: float, v: Vector3) -> void:
	var st: EntityStore = w.store()
	var s: int = EntityId.slot(id)
	var p: int = EntityId.slot(pad_id)
	var up: Vector3 = st.up[p]
	var east: Vector3 = st.fwd[p]
	st.fwd[s] = up
	st.up[s] = east
	st.pos[s] = st.pos[p] + up * alt + east * off
	st.vel[s] = v
	st.rates[s] = Vector3.ZERO


## Writes one PAD contact (exact v_vert, v_horiz, tilt, offset; band from Collision.landing_band) as the only contact of
## the world's Collision and runs `Docking.land` for the current tick. Returns the band.
static func contact(w: SimWorld, id: int, pad_id: int, v_vert: float, v_hor: float, tilt_deg: float, offset: float) -> int:
	var c: Collision = w.collision
	var band: int = Collision.landing_band(v_vert, v_hor, tilt_deg, common())
	c.contact_count = 1
	c.c_kind[0] = Collision.C_PAD
	c.c_class[0] = band
	c.c_a[0] = id
	c.c_b[0] = pad_id
	c.c_value[0] = offset
	c.c_point[0] = w.store().pos[EntityId.slot(id)]
	c.c_vec[0] = Vector3(v_vert, v_hor, tilt_deg)
	w.economy().docking.land(w.tick(), c)
	return band


## Spawns now through `CommandApplier.spawn` (no command, so no rate bucket: bulk scenes); returns the EntityId, 0 on failure.
static func direct(w: SimWorld, def: StringName, owner: int, team: int, p: Vector3) -> int:
	var s: int = w._applier.spawn(WorldTestKit.def_id(def), owner, team, p, Vector3.ZERO, Vector3(0.0, 1.0, 0.0), w.tick())
	return w.store().id_of(s) if s >= 0 else 0


## Takes ship `id` off any pad and parks it far away, hovering (frees the pad for the next case of a test).
static func clear(w: SimWorld, id: int) -> void:
	var s: int = EntityId.slot(id)
	w.store().flags[s] &= ~(EntityStore.F_DOCKED | EntityStore.F_LANDED)
	w.store().link[s] = 0
	w.store().pos[s] = far(w)
	w.store().vel[s] = Vector3.ZERO


## Docks ship `id` on `pad_id` the way a landing does, without a grade (the SimViewScene / stand-in path: flags + link).
static func dock(w: SimWorld, id: int, pad_id: int) -> void:
	pose(w, id, pad_id, w.store().radius[EntityId.slot(id)], 0.0, Vector3.ZERO)
	var s: int = EntityId.slot(id)
	w.store().flags[s] |= EntityStore.F_DOCKED | EntityStore.F_LANDED
	w.store().link[s] = pad_id


## Possesses `id` for player 0 (one step) and returns whether it took.
static func possess(w: SimWorld, id: int, player: int = 0) -> bool:
	var r: CommandResult = w.apply_command(Command.possess(player, id))
	w.step()
	var _e: Array[SimEvent] = w.drain_events()
	return r.code == CommandResult.Code.ACCEPTED and w.view().possessor(id) == player


## One step with a fresh neutral PILOT_INPUT for `player` (keeps a possessed ship from going silent, 05 C13).
static func step_piloted(w: SimWorld, player: int = 0, buttons: int = 0) -> void:
	var inp: PilotInput = PilotInput.new()
	inp.buttons = buttons
	var _r: CommandResult = w.apply_command(Command.pilot(player, w.tick() + 1, inp))
	w.step()


## Events of kind `k` among `events`.
static func of_kind(events: Array[SimEvent], k: SimEvent.Kind) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.kind == k:
			out.append(e)
	return out


## Team pool (ore, ice) of `team`.
static func pool(w: SimWorld, team: int) -> Vector2i:
	return w.economy().economy.stockpile(team)
