extends GdUnitTestSuite
## REVIEW-01: every hub entry points at a scene that exists and loads.


func test_demo_scenes_exist_and_load() -> void:
	assert_int(ReviewHub.PATHS.size()).is_equal(3)
	for i: int in ReviewHub.PATHS.size():
		assert_bool(ResourceLoader.exists(ReviewHub.PATHS[i])).is_true()
		assert_bool(load(ReviewHub.PATHS[i]) is PackedScene).is_true()
		assert_str(ReviewHub.BLURBS[i]).is_not_empty()


func test_hub_builds_one_button_per_demo() -> void:
	var hub: ReviewHub = auto_free((load(ReviewHub.HUB_PATH) as PackedScene).instantiate()) as ReviewHub
	add_child(hub)
	var n: int = 0
	for c: Node in hub.find_children("*", "Button", true, false):
		n += 1
	assert_int(n).is_equal(ReviewHub.PATHS.size())
