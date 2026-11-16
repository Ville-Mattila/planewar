class_name PlacementRing extends RefCounted
## One ground ring of the build placement overlay (docs/06 s7.3); plain data, drawn by presentation / app.

enum Kind { BUILD, ENEMY_BUILD, PRESENCE, SPACING_FRIENDLY, SPACING_ENEMY }

var kind: Kind = Kind.BUILD
var center: Vector3 = Vector3.ZERO
var radius_m: float = 0.0
var follows_ghost: bool = false   ## the presence ring is centred on the ghost, not on a structure
var source: int = -1              ## EntityId of the structure it surrounds; -1 for the ghost ring


func color() -> Color:
	match kind:
		Kind.BUILD:
			return UiTokens.UI_OK
		Kind.PRESENCE:
			return UiTokens.UI_ACCENT
		Kind.SPACING_FRIENDLY:
			return UiTokens.UI_WARN
	return UiTokens.UI_DANGER
