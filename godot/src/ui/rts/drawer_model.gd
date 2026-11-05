class_name DrawerModel extends RefCounted
## Production drawer data from a SimView (docs/06 s7.5): tile states, badges, factory choice and cancel verdicts.
## Reads only the named public SimView accessors; the state order follows the sim's own checks (test-enforced
## against CommandValidator in test_drawer_sim_agreement.gd).

const FLAG_BUILDING: int = 16   ## EntityStore.F_BUILDING (sim/MODULE.md flags); test-pinned


## Empty when the player may use the drawer, else the locale key of the reason (06 s7.5, 01 s3.3).
static func disabled_reason(ctx: DrawerContext) -> StringName:
	if ctx.eliminated or not ctx.commander_rights:
		return &"ui.prod.disabled.eliminated"
	return &""


static func tiles(view: SimView, ctx: DrawerContext, units: bool) -> Array[TileInfo]:
	var out: Array[TileInfo] = []
	for id: StringName in (DrawerCatalog.unit_ids() if units else DrawerCatalog.structure_ids()):
		out.append(tile(view, ctx, id))
	return out


static func tile(view: SimView, ctx: DrawerContext, id: StringName) -> TileInfo:
	var t: TileInfo = TileInfo.new()
	t.id = id
	t.def = ContentDB.def_index(id)
	t.is_unit = DrawerCatalog.factory_of(id) != &""
	t.lock_left_ore = ctx.lock_left_ore
	var player: int = ctx.player
	var team: int = ctx.team
	var stock: Vector2i = ctx.stock()
	t.cost = DrawerCatalog.cost(id, ctx.doctrine)
	t.short = DrawerMath.short_of(t.cost, stock)
	var tech_ok: bool = view.tech_available(team, t.def)
	var capped: bool = false
	if t.is_unit:
		t.replenish = view.auto_replenish_target(player, t.def)
		var fs: PackedInt32Array = factories(view, team, id)
		tech_ok = tech_ok and not fs.is_empty()
		_fill_queue(view, fs, t)
		t.count = ctx.unit_count
		t.limit = ctx.unit_cap
		capped = (t.limit > 0 and t.count >= t.limit) or (not fs.is_empty() and best_factory(view, team, id, Vector3.ZERO) < 0)
	else:
		_fill_sites(view, player, team, t)
		t.limit = DrawerCatalog.max_per_player(id)
		var total: int = _owned_total(view, player)
		var cap: int = ctx.structure_cap
		capped = (t.limit > 0 and t.count >= t.limit) or (cap > 0 and total >= cap)
	if not tech_ok:
		t.need = _missing_need(view, team, id)
	t.state = DrawerMath.classify(tech_ok, capped, t.cost, stock, ctx.lock_left_ore)
	return t


## Finished own-team factories that make `unit` (the unit def's `produced_at`).
static func factories(view: SimView, team: int, unit: StringName) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var want: int = ContentDB.def_index(DrawerCatalog.factory_of(unit))
	if want < 0:
		return out
	for s: int in view.structures():
		if view.def_id(s) == want and view.team(s) == team and (view.flags(s) & FLAG_BUILDING) == 0:
			var _a: bool = out.append(s)
	return out


## The factory a tap queues at: shortest queue, tie nearest `focus`; -1 when none or all are full.
static func best_factory(view: SimView, team: int, unit: StringName, focus: Vector3) -> int:
	var ids: PackedInt32Array = factories(view, team, unit)
	var lens: PackedInt32Array = PackedInt32Array()
	var d2: PackedFloat32Array = PackedFloat32Array()
	for f: int in ids:
		var _a: bool = lens.append(view.production_queue(f).size())
		var _b: bool = d2.append(view.pos(f).distance_squared_to(focus))
	return DrawerMath.pick_factory(ids, lens, d2)


## Construction sites of `id` on `team` (the CANCEL_BUILD candidates).
static func sites(view: SimView, team: int, id: StringName) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var d: int = ContentDB.def_index(id)
	for s: int in view.structures():
		if view.def_id(s) == d and view.team(s) == team and (view.flags(s) & FLAG_BUILDING) != 0:
			var _a: bool = out.append(s)
	return out


## One Cancel verdict per queue item (or per entry of `queuers` when `factory` < 0). `queuers[i]` is the player who
## queued item i; empty = unknown (needs sim: SimView.production_queuer), every verdict UNKNOWN.
static func queue_verdicts(view: SimView, ctx: DrawerContext, factory: int, queuers: PackedInt32Array) -> PackedInt32Array:
	var n: int = queuers.size() if factory < 0 else maxi(view.production_queue(factory).size(), queuers.size())
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		var q: int = queuers[i] if i < queuers.size() else -1
		var v: int = DrawerMath.Cancel.UNKNOWN
		if q >= 0 and ctx.has_player(q):
			v = DrawerMath.cancel_verdict(ctx.player, ctx.team, q, ctx.player_team(q), ctx.player_kind(q),
					ctx.player_connected(q), ctx.player_eliminated(q))
		elif q >= 0:   # a slot the host did not describe: an open slot of the local team
			v = DrawerMath.cancel_verdict(ctx.player, ctx.team, q, ctx.team, DrawerMath.KIND_OPEN, false, false)
		var _a: bool = out.append(v)
	return out


static func _fill_queue(view: SimView, fs: PackedInt32Array, t: TileInfo) -> void:
	for f: int in fs:
		var q: PackedInt32Array = view.production_queue(f)
		for d: int in q:
			if d == t.def:
				t.queued += 1
		if q.size() > 0 and q[0] == t.def:
			t.progress01 = maxf(t.progress01, view.production_progress01(f))


static func _fill_sites(view: SimView, player: int, team: int, t: TileInfo) -> void:
	for s: int in view.structures():
		if view.def_id(s) != t.def or view.team(s) != team:
			continue
		if view.owner(s) == player:
			t.count += 1
		if (view.flags(s) & FLAG_BUILDING) != 0:
			t.queued += 1
			if view.owner(s) == player:
				t.progress01 = maxf(t.progress01, view.hp01(s))   # needs sim: a construction-progress read


static func _owned_total(view: SimView, player: int) -> int:
	var n: int = 0
	for s: int in view.structures():
		if view.owner(s) == player:
			n += 1
	return n


## First `requires` structure the team has no finished copy of; the factory for a unit whose tech is otherwise fine.
static func _missing_need(view: SimView, team: int, id: StringName) -> StringName:
	for r: String in DrawerCatalog.requires(id):
		var d: int = ContentDB.def_index(StringName(r))
		var have: bool = false
		for s: int in view.structures():
			if view.def_id(s) == d and view.team(s) == team and (view.flags(s) & FLAG_BUILDING) == 0:
				have = true
				break
		if not have:
			return StringName(r)
	var all: PackedStringArray = DrawerCatalog.requires(id)
	return StringName(all[0]) if not all.is_empty() and DrawerCatalog.factory_of(id) == &"" else DrawerCatalog.factory_of(id)
