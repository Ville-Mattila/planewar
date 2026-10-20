class_name SimViewFactory extends RefCounted
## Plug-in point of the shared SimView contract test (TEST-02). One subclass per SimView implementation, saved as
## `res://test/unit/sim/contract/factories/*.gd` (LocalSimView now; NET-17 adds NetSimView, NET-39 widens it): the test
## body discovers every file there through SimViewFactories and never changes.


## Name shown in failure messages.
func label() -> String:
	return "SimView"


## The view under test for `scene.world` (already stepped and scripted). A networked implementation encodes the world
## the way the server does, decodes it on a client and returns its view; the contract compares it to the scene's
## values, which do not depend on any view.
func make(_scene: SimViewScene) -> SimView:
	return null


## Accessors this implementation legitimately does not replicate (04 s5.6: they return the default with `unknown`).
## Each entry needs a reason in the factory file; an exempt accessor is skipped by the contract, nothing else is.
func exempt() -> PackedStringArray:
	return PackedStringArray()
