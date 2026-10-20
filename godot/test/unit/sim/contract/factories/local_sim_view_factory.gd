class_name LocalSimViewFactory extends SimViewFactory
## LocalSimView reads the world's arrays directly (03 s15.4): nothing is exempt.


func label() -> String:
	return "LocalSimView"


func make(scene: SimViewScene) -> SimView:
	return scene.world.view()
