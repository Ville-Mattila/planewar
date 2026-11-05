class_name ProductionDrawer extends Control
## Production drawer (docs/06 s7.5, UX-22): BUILD / UNITS tabs, 18 tile buttons in a 3 x 6 grid, a long-press detail page
## on the same grid and a reason line. Reads a SimView through DrawerModel; emits Commands (`command_ready`) for the host
## to submit through ClientSession and `build_armed` when a structure tile arms placement (UX-21). Refreshed at 4 Hz.

signal command_ready(cmd: Command)
signal build_armed(def_id: StringName)

var profile: UiScale.Profile = UiScale.Profile.REGULAR
var units_tab: bool = false   ## false = BUILD, true = UNITS

var _view: SimView = null
var _ctx: DrawerContext = DrawerContext.new()
var _focus: Vector3 = Vector3.ZERO
var _tiles: Array[DrawerTile] = []
var _tabs: Array[Button] = []
var _reason: Label = null
var _infos: Array[TileInfo] = []
var _detail: StringName = &""
var _detail_factory: int = -1
var _detail_sites: PackedInt32Array = PackedInt32Array()
var _slots: Array[DetailSlot] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for i: int in 2:
		var b: Button = Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_ALL
		b.text = tr(&"ui.prod.tab.units" if i == 1 else &"ui.prod.tab.build")
		b.clip_text = true
		var _c: int = b.pressed.connect(_on_tab.bind(i == 1))
		add_child(b)
		_tabs.append(b)
	for i: int in DrawerLayout.capacity():
		var t: DrawerTile = DrawerTile.new()
		var _c: int = t.pressed.connect(_on_tile.bind(i))
		var _d: int = t.secondary.connect(_on_secondary.bind(i))
		add_child(t)
		_tiles.append(t)
	_reason = Label.new()
	_reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_reason)
	set_profile(profile)
	_sync_tabs()


func set_profile(p: UiScale.Profile) -> void:
	profile = p
	custom_minimum_size = Vector2.ZERO          # shrinking past the old minimum needs it cleared first
	size = DrawerLayout.size_du(p)
	custom_minimum_size = size
	var fs: int = DrawerLayout.font_du(p)
	for i: int in _tabs.size():
		var r: Rect2 = DrawerLayout.tab_rect(p, i)
		_tabs[i].position = r.position
		_tabs[i].size = r.size
		_tabs[i].add_theme_font_size_override(&"font_size", fs)
	var origin: Vector2 = DrawerLayout.grid_origin(p)
	for i: int in _tiles.size():
		var tr_: Rect2 = DrawerLayout.tile_rect(p, i)
		_tiles[i].position = origin + tr_.position
		_tiles[i].size = tr_.size
		_tiles[i].profile = p
		_tiles[i].queue_redraw()
	var strip: Rect2 = DrawerLayout.strip_rect(p)
	_reason.add_theme_font_size_override(&"font_size", fs)
	if strip.size.y > 0.0:
		_reason.position = strip.position
		_reason.size = strip.size
		_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		_reason.size = Vector2(DrawerLayout.grid_size(p).x + origin.x, float(fs) * 3.0)   # COMPACT: over the grid's top edge
		_reason.position = Vector2(-_reason.size.x - DrawerLayout.gap_du(), 0.0)
		_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func tile_nodes() -> Array[DrawerTile]:
	return _tiles


func focus_first() -> void:
	for t: DrawerTile in _tiles:
		if t.visible and not t.disabled:
			t.grab_focus()
			return
	_tabs[0].grab_focus()


## 4 Hz: re-reads the SimView and redraws the tiles (or the open detail page).
func refresh(view: SimView, ctx: DrawerContext, focus: Vector3) -> void:
	_view = view
	_ctx = ctx
	_focus = focus
	_sync_tabs()
	var off: StringName = DrawerModel.disabled_reason(ctx)
	_infos = DrawerModel.tiles(view, ctx, units_tab)
	if _detail != &"":
		_fill_detail()
	else:
		_fill_tiles()
	if off != &"":
		for t: DrawerTile in _tiles:
			t.disabled = true
		_reason.text = tr(off)
	elif _detail == &"":
		_reason.text = ""


func open_detail(id: StringName) -> void:
	_detail = id
	var team: int = _ctx.team
	_detail_factory = DrawerModel.best_factory(_view, team, id, _focus) if DrawerCatalog.factory_of(id) != &"" else -1
	if DrawerCatalog.factory_of(id) != &"":
		var fs: PackedInt32Array = DrawerModel.factories(_view, team, id)
		if _detail_factory < 0 and not fs.is_empty():
			_detail_factory = fs[0]                                    # all full: still show the queue
	_detail_sites = DrawerModel.sites(_view, team, id)
	_fill_detail()


func close_detail() -> void:
	_detail = &""
	_reason.text = ""
	_fill_tiles()


func _fill_tiles() -> void:
	for i: int in _tiles.size():
		_tiles[i].visible = i < _infos.size()
		if i < _infos.size():
			_tiles[i].disabled = false
			_tiles[i].set_info(_infos[i])
			_tiles[i].tooltip_text = DrawerText.reason(_infos[i])


func _info_of(id: StringName) -> TileInfo:
	for i: TileInfo in _infos:
		if i.id == id:
			return i
	return TileInfo.new()


func _queue_len() -> int:
	if DrawerCatalog.factory_of(_detail) != &"":
		return _view.production_queue(_detail_factory).size() if _detail_factory >= 0 else 0
	return _detail_sites.size()


func _fill_detail() -> void:
	var info: TileInfo = _info_of(_detail)
	var verdicts: PackedInt32Array = PackedInt32Array()
	if info.is_unit:
		verdicts = DrawerModel.queue_verdicts(_view, _ctx, _detail_factory, PackedInt32Array())
	else:
		var owners: PackedInt32Array = PackedInt32Array()
		for s: int in _detail_sites:
			var _a: bool = owners.append(_view.owner(s))
		verdicts = DrawerModel.queue_verdicts(_view, _ctx, -1, owners)
	_slots = DrawerDetail.slots(info, mini(_queue_len(), DrawerLayout.capacity() - 6), verdicts)
	for i: int in _tiles.size():
		_tiles[i].visible = i < _slots.size()
		if i < _slots.size():
			_tiles[i].set_plain(DrawerText.slot_label(_slots[i], info), _slots[i].enabled)
			_tiles[i].tooltip_text = tr(_slots[i].reason) if _slots[i].reason != &"" else ""
	_reason.text = tr(DrawerCatalog.name_key(_detail))


func _on_tab(units: bool) -> void:
	units_tab = units
	_detail = &""
	_sync_tabs()
	if _view != null:
		refresh(_view, _ctx, _focus)


func _sync_tabs() -> void:
	if _tabs.size() == 2:
		_tabs[0].button_pressed = not units_tab
		_tabs[1].button_pressed = units_tab


func _on_secondary(_t: DrawerTile, i: int) -> void:
	if _detail == &"" and i < _infos.size():
		open_detail(_infos[i].id)


func _on_tile(i: int) -> void:
	if _view == null or _tiles[i].long_fired:
		return
	if _detail != &"":
		if i < _slots.size() and _slots[i].enabled:
			_run_slot(_slots[i])
		return
	var info: TileInfo = _infos[i] if i < _infos.size() else null
	if info == null:
		return
	if info.state != DrawerMath.State.AVAILABLE:
		_reason.text = DrawerText.reason(info)                        # a tap on a blocked tile explains why
		return
	if info.is_unit:
		_emit(DrawerCommands.produce_at_best(_view, _ctx, info.id, 1, _focus))
	else:
		build_armed.emit(info.id)


func _run_slot(s: DetailSlot) -> void:
	var info: TileInfo = _info_of(_detail)
	var len_q: int = _queue_len()
	match s.kind:
		DetailSlot.Kind.BACK:
			close_detail()
		DetailSlot.Kind.BATCH:
			_emit(DrawerCommands.produce_at_best(_view, _ctx, _detail, DrawerMath.batch(len_q), _focus))
		DetailSlot.Kind.CANCEL_LAST:
			_emit(DrawerCommands.cancel_produce(_ctx.player, _detail_factory, len_q - 1))
		DetailSlot.Kind.REPL_DEC:
			_emit(DrawerCommands.replenish(_view, _ctx, _detail_factory, _detail, DrawerMath.stepper(info.replenish, -1)))
		DetailSlot.Kind.REPL_INC:
			_emit(DrawerCommands.replenish(_view, _ctx, _detail_factory, _detail, DrawerMath.stepper(info.replenish, 1)))
		DetailSlot.Kind.QUEUE_ITEM:
			if info.is_unit:
				_emit(DrawerCommands.cancel_produce(_ctx.player, _detail_factory, s.index))
			elif s.index < _detail_sites.size():
				_emit(DrawerCommands.cancel_build(_ctx.player, _detail_sites[s.index]))


func _emit(c: Command) -> void:
	if c != null:
		command_ready.emit(c)
