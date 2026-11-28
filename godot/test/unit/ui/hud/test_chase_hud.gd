extends GdUnitTestSuite
## UX-51: the Chase HUD scene hosts the status cluster and barrel readout at their anchors and feeds them from a
## LocalSimView for the possessed entity (06 s3.2). Possess a Siege Crawler and a Dart: the barrel readout shows only
## for the Crawler; nothing possessed hides both.

var _w: SimWorld
var _dart: int = 0
var _crawler: int = 0
var _hud: ChaseHud
var _host: ChaseHudHost


func before_test() -> void:
	if not ContentDB.is_loaded():
		var _l: Result = ContentDB.load_all()
	_w = WorldTestKit.world()
	_dart = WorldTestKit.spawn(_w, &"dart", 0, 0, WorldTestKit.at(500.0), Vector3(0, 40, 0))
	_crawler = WorldTestKit.spawn(_w, &"siege_crawler", 0, 0, WorldTestKit.at(7.0, -2500.0))
	_hud = auto_free(load("res://scenes/ui/chase_hud.tscn").instantiate()) as ChaseHud
	add_child(_hud)
	_host = auto_free(ChaseHudHost.new()) as ChaseHudHost
	_host.hud = _hud
	_host.view = _w.view()
	_host.local_player = 0


func _possess(id: int) -> void:
	var r: CommandResult = _w.apply_command(Command.possess(0, id))
	assert_int(r.code).is_equal(CommandResult.Code.ACCEPTED)
	_w.step()
	_host.possessed_id = id
	_host.refresh()


func test_hidden_when_nothing_possessed() -> void:
	_host.refresh()
	assert_bool(_hud.status.visible).is_false()
	assert_bool(_hud.barrel.visible).is_false()


func test_barrel_readout_only_for_the_crawler() -> void:
	_possess(_crawler)
	assert_bool(_hud.status.visible).is_true()
	assert_bool(_hud.barrel.visible).is_true()
	assert_int(_hud.barrel.lines().size()).is_equal(3)
	var _r: CommandResult = _w.apply_command(Command.release(0))
	_w.step()
	_possess(_dart)
	assert_bool(_hud.status.visible).is_true()
	assert_bool(_hud.barrel.visible).is_false()
	assert_int(_hud.barrel.lines().size()).is_equal(0)


func test_hides_again_after_release() -> void:
	_possess(_crawler)
	var _r: CommandResult = _w.apply_command(Command.release(0))
	_w.step()
	_host.refresh()
	assert_bool(_hud.status.visible).is_false()
	assert_bool(_hud.barrel.visible).is_false()


func test_another_players_unit_is_not_shown() -> void:
	_host.possessed_id = _crawler        # never possessed by player 0
	_host.refresh()
	assert_int(_host.active_id()).is_equal(0)
	assert_bool(_hud.barrel.visible).is_false()


func test_layout_anchors_bottom_centre_and_barrel_above_status() -> void:
	var canvas: Vector2 = Vector2(800.0, 450.0)
	_hud.layout(canvas)
	var s: Rect2 = Rect2(_hud.status.position, _hud.status.size)
	var b: Rect2 = Rect2(_hud.barrel.position, _hud.barrel.size)
	assert_float(s.get_center().x).is_equal_approx(400.0, 0.01)
	assert_float(s.end.y).is_equal_approx(canvas.y - HudMath.param("chase_margin_du"), 0.01)
	assert_float(b.get_center().x).is_equal_approx(400.0, 0.01)
	assert_float(b.end.y).is_less_equal(s.position.y)
	assert_bool(Rect2(Vector2.ZERO, canvas).encloses(s)).is_true()
	assert_bool(Rect2(Vector2.ZERO, canvas).encloses(b)).is_true()
