class_name DrawerTile extends Button
## One production drawer tile (docs/06 s7.5): name, cost under it, state look, count badge, progress ring and the
## auto-replenish target badge. Press = primary; RMB, pad X or a long press emit `secondary`. The same button also
## serves as a plain slot of the detail page. Drawing only; the rules are in DrawerMath / DrawerModel.

signal secondary(tile: DrawerTile)

var info: TileInfo = TileInfo.new()
var profile: UiScale.Profile = UiScale.Profile.REGULAR
var plain_text: String = ""
var plain_on: bool = false
var long_fired: bool = false     ## the long press already opened the detail page: swallow the release

var _hold: Timer = null


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	clip_text = true
	_hold = Timer.new()
	_hold.one_shot = true
	add_child(_hold)
	var _c: int = _hold.timeout.connect(_on_long_press)
	var _d: int = button_down.connect(_on_down)
	var _e: int = button_up.connect(_hold.stop)


func set_info(i: TileInfo) -> void:
	info = i
	plain_on = false
	queue_redraw()


## Detail-page mode: a caption instead of a def.
func set_plain(text_value: String, enabled: bool) -> void:
	plain_on = true
	plain_text = text_value
	disabled = not enabled
	queue_redraw()


func _on_down() -> void:
	long_fired = false
	if not plain_on:
		_hold.start(RtsParams.param("long_press_s"))


func _on_long_press() -> void:
	long_fired = true
	secondary.emit(self)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return                                       # a disabled drawer takes no secondary input either (06 s7.5)
	var mb: InputEventMouseButton = event as InputEventMouseButton
	var jb: InputEventJoypadButton = event as InputEventJoypadButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		if not plain_on:
			secondary.emit(self)
	elif jb != null and jb.pressed and jb.button_index == JOY_BUTTON_X and has_focus():
		accept_event()
		if not plain_on:
			secondary.emit(self)


func _draw() -> void:
	var fs: int = DrawerLayout.font_du(profile)
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	var dim: bool = plain_on and disabled or (not plain_on and info.state != DrawerMath.State.AVAILABLE)
	draw_rect(r, UiTokens.UI_BG_2 if has_focus() or button_pressed else UiTokens.UI_BG_1)
	draw_rect(r, UiTokens.UI_FOCUS if has_focus() else UiTokens.UI_LINE, false, 2.0 if has_focus() else 1.0)
	var ink: Color = UiTokens.UI_TEXT_DIM if dim else UiTokens.UI_TEXT
	if plain_on:
		HudText.text(self, Vector2(0.0, size.y * 0.5 + float(fs) * 0.35), plain_text, ink, fs, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		return
	HudText.text(self, Vector2(0.0, float(fs) + 2.0), tr(DrawerCatalog.name_key(info.id)), ink, fs, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_draw_cost(fs)
	var cap: StringName = DrawerText.caption_key(info)
	if cap != &"":
		HudText.text(self, Vector2(0.0, float(fs) * 2.4), tr(cap), UiTokens.UI_WARN, fs, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_draw_badges(fs)


## Cost under the icon: Ore, then Ice. The missing resource is highlighted, a spend-locked amount is greyed.
func _draw_cost(fs: int) -> void:
	var y: float = size.y - 3.0
	var ore_col: Color = UiTokens.RES_ORE
	var ice_col: Color = UiTokens.RES_ICE
	if info.state == DrawerMath.State.SPEND_LOCKED or info.state == DrawerMath.State.LOCKED or info.state == DrawerMath.State.CAP_REACHED:
		ore_col = UiTokens.UI_TEXT_DIM
		ice_col = UiTokens.UI_TEXT_DIM
	if info.short.x > 0:
		ore_col = UiTokens.UI_DANGER
	if info.short.y > 0:
		ice_col = UiTokens.UI_DANGER
	var half: float = size.x * 0.5
	if info.cost.y > 0:
		HudText.text(self, Vector2(2.0, y), str(info.cost.x), ore_col, fs, HORIZONTAL_ALIGNMENT_LEFT, half)
		HudText.text(self, Vector2(half, y), str(info.cost.y), ice_col, fs, HORIZONTAL_ALIGNMENT_RIGHT, half - 2.0)
	else:
		HudText.text(self, Vector2(0.0, y), str(info.cost.x), ore_col, fs, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if info.state == DrawerMath.State.SPEND_LOCKED:
		draw_line(Vector2(3.0, y - float(fs) * 0.35), Vector2(size.x - 3.0, y - float(fs) * 0.35), UiTokens.UI_TEXT_DIM, 1.0)


func _draw_badges(fs: int) -> void:
	if info.queued > 0:
		HudText.text(self, Vector2(0.0, float(fs) * 3.6), "x%d" % info.queued, UiTokens.UI_ACCENT, fs, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 2.0)
		if info.progress01 > 0.0:
			var c: Vector2 = Vector2(size.x * 0.5, size.y * 0.5 + float(fs) * 0.2)
			HudText.ring(self, c, float(fs) * 0.7, info.progress01, UiTokens.UI_OK)
	if info.replenish > 0:
		HudText.text(self, Vector2(2.0, float(fs) * 3.6), tr(&"ui.prod.badge.auto").format({"n": info.replenish}), UiTokens.UI_OK, fs)
