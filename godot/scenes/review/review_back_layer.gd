class_name ReviewBackLayer
extends CanvasLayer
## REVIEW-01: "Back to hub" button + Esc, added to the root viewport once so it survives scene changes.

const NODE_NAME: String = "ReviewBackLayer"

var _button: Button


static func ensure(root: Node) -> ReviewBackLayer:
	var existing: Node = root.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing as ReviewBackLayer
	var layer: ReviewBackLayer = ReviewBackLayer.new()
	layer.name = NODE_NAME
	root.add_child.call_deferred(layer)
	return layer


func _init() -> void:
	layer = 100


func _ready() -> void:
	_button = Button.new()
	_button.text = "Back to hub (Esc)"
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_button.offset_top = 8.0
	_button.offset_right = -8.0
	_button.focus_mode = Control.FOCUS_NONE
	var _c: Error = _button.pressed.connect(go_back)
	add_child(_button)
	_button.visible = visible_for_demo


var visible_for_demo: bool = false


func set_hub_visible(on_hub: bool) -> void:
	visible_for_demo = not on_hub
	if _button != null:
		_button.visible = visible_for_demo


func go_back() -> void:
	set_hub_visible(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var _e: Error = get_tree().change_scene_to_file(ReviewHub.HUB_PATH)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible_for_demo and event.is_action_pressed("ui_cancel"):
		go_back()
