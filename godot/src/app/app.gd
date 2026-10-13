extends Node
## Autoload `App` (stub, TA-01). No class_name: it would hide the autoload singleton.
## Full implementation (boot flow, mode selection): docs/03 and the app lane.


func _ready() -> void:
	# UX-29: register PO translations and pick the locale before any UI exists.
	var _locale: String = LocaleSelect.setup()
