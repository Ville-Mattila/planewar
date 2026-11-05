class_name TileInfo extends RefCounted
## Plain data for one production drawer tile (UX-22), filled by DrawerModel from a SimView.

var id: StringName = &""
var def: int = -1
var is_unit: bool = false
var state: DrawerMath.State = DrawerMath.State.AVAILABLE
var cost: Vector2i = Vector2i.ZERO          ## (ore, ice), doctrine-resolved
var short: Vector2i = Vector2i.ZERO         ## Ore / Ice still missing (UNAFFORDABLE highlight)
var queued: int = 0                         ## units in the team queues, or construction sites of the team
var progress01: float = 0.0                 ## head progress of a queue, or the own site's hp01
var replenish: int = 0                      ## auto-replenish target of the local player
var lock_left_ore: int = -1                 ## Ore left of the early share; < 0 = no lock
var need: StringName = &""                  ## first missing prerequisite structure (LOCKED)
var count: int = 0                          ## owned units / structures of the cap that was hit
var limit: int = 0                          ## that cap
