class_name DrawerCommands extends RefCounted
## Commands the production drawer issues (docs/06 s7.5); the host submits them through ClientSession. PRODUCE and the
## replenish roster use the public Command builders, the two cancels fill the same payload layout the sim reads
## (CANCEL_PRODUCE: u8 queue index, target = factory; CANCEL_BUILD: no payload, target = site; test-pinned).


## PRODUCE `count` of `unit` at the best team factory (shortest queue, tie nearest `focus`), clipped to its free queue
## slots. Null when there is no factory with room or `count` < 1.
static func produce_at_best(view: SimView, ctx: DrawerContext, unit: StringName, count: int, focus: Vector3) -> Command:
	if count < 1:
		return null
	var f: int = DrawerModel.best_factory(view, ctx.team, unit, focus)
	if f < 0:
		return null
	var n: int = mini(count, DrawerMath.queue_max() - view.production_queue(f).size())
	if n < 1:
		return null
	return Command.produce(ctx.player, f, ContentDB.def_index(unit), n)


static func cancel_produce(player: int, factory: int, index: int) -> Command:
	return _make(player, Command.Kind.CANCEL_PRODUCE, factory, PackedByteArray([index & 0xFF]))


static func cancel_build(player: int, site: int) -> Command:
	return _make(player, Command.Kind.CANCEL_BUILD, site, PackedByteArray())


## TOGGLE_AUTO_REPLENISH at `factory` with the player's targets, `unit` replaced by `target`. Disabled (empty roster)
## when every target is 0. The roster replaces the player's targets in the sim (GD-17), so all of them are sent.
static func replenish(view: SimView, ctx: DrawerContext, factory: int, unit: StringName, target: int) -> Command:
	var roster: PackedInt32Array = PackedInt32Array()
	for id: StringName in DrawerCatalog.unit_ids():
		var d: int = ContentDB.def_index(id)
		var t: int = target if id == unit else view.auto_replenish_target(ctx.player, d)
		if t > 0 and roster.size() < 2 * int(RtsParams.param("replenish_pairs_max")):
			var _a: bool = roster.append(d)
			var _b: bool = roster.append(t)
	return Command.toggle_auto_replenish(ctx.player, factory, not roster.is_empty(), roster)


static func _make(player: int, kind: Command.Kind, target: int, payload: PackedByteArray) -> Command:
	var c: Command = Command.new()
	c.player = player
	c.kind = kind
	c.target = target
	c.payload = payload
	return c
