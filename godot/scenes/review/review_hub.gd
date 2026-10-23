class_name ReviewHub
extends Control
## REVIEW-01: launcher for the web review build. One button per playable demo; scene changes go through
## get_tree().change_scene_to_file. A persistent ReviewBackLayer on the root viewport (no autoload) brings
## the player back here.

const HUB_PATH: String = "res://scenes/review/review_hub.tscn"

const TITLES: PackedStringArray = ["Flight spike", "Planet demo", "Entity demo"]
const PATHS: PackedStringArray = [
	"res://spikes/s_flight_1/flight_spike.tscn",
	PLANET_SCENE,
	"res://scenes/presentation/entities/entity_demo.tscn",
]
const BLURBS: PackedStringArray = [
	"Fly a ship around the moon: flight model, chase camera, tail-down landing.",
	"The 6 km moon renderer: terrain, craters and level of detail.",
	"Ships and structures drawn from sim state, with a chase camera.",
]


func _ready() -> void:
	var back: ReviewBackLayer = ReviewBackLayer.ensure(get_tree().root)
	back.set_hub_visible(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title: Label = Label.new()
	title.text = "PLANEWAR review build"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for i: int in TITLES.size():
		var b: Button = Button.new()
		b.text = TITLES[i]
		b.custom_minimum_size = Vector2(360.0, 44.0)
		var _c: Error = b.pressed.connect(_launch.bind(PATHS[i]))
		box.add_child(b)
		var l: Label = Label.new()
		l.text = BLURBS[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(360.0, 0.0)
		l.modulate = Color(1.0, 1.0, 1.0, 0.7)
		box.add_child(l)


## Planet demo start (cradle, lat 30 / lon 22.5, 1800 m up, pitched down): the 1200 m crater crater_0_w0 rim and
## floor plus small craters are in frame; set here because the web build has no command-line args.
const PLANET_REVIEW: Dictionary = {"map": "cradle", "lat": 30.0, "lon": 22.5, "alt": 1800.0, "pitch": -50.0, "yaw": 0.0}
const PLANET_SCENE: String = "res://scenes/presentation/planet/planet_demo.tscn"


func _launch(path: String) -> void:
	if path == PLANET_SCENE:
		ProjectSettings.set_setting(PlanetDemo.REVIEW_KEY, PLANET_REVIEW)
	ReviewBackLayer.ensure(get_tree().root).set_hub_visible(false)
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("review hub: cannot open %s (%d)" % [path, err])
		ReviewBackLayer.ensure(get_tree().root).set_hub_visible(true)
