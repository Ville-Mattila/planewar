class_name PauseItem extends RefCounted
## One row of the Pause menu (06 s8 Pause): an id, whether it can be used, and the locale key of the reason when not.

var id: StringName = &""
var enabled: bool = true
var reason_key: StringName = &""


static func make(p_id: StringName, p_enabled: bool = true, p_reason: StringName = &"") -> PauseItem:
	var i: PauseItem = PauseItem.new()
	i.id = p_id
	i.enabled = p_enabled
	i.reason_key = &"" if p_enabled else p_reason
	return i
