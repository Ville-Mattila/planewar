class_name FlowScreen extends Control
## Base class of every screen ScreenFlow hosts (06 s8 Navigation, UX-24). Subclasses override.


## Called after the screen is in the tree, before focus is placed.
func enter(_args: Dictionary) -> void:
	pass


## Called before the screen leaves the tree.
func exit() -> void:
	pass


## Return true when the screen consumed "back" itself (closing a dialog); false lets ScreenFlow pop.
func handle_back() -> bool:
	return false


## The Control that takes focus on entry. Should be focusable; ScreenFlow falls back to the first
## focusable descendant when this is null or FOCUS_NONE.
func initial_focus() -> Control:
	return null
