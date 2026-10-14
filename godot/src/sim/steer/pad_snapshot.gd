class_name PadSnapshot extends RefCounted
## Input struct of LandingController (05 s5.5): the chosen pad. One reused scratch per caller.

var p: Vector3 = Vector3.ZERO          ## pad centre on its landing plane (the structure position, R0 B.5)
var n: Vector3 = Vector3.UP            ## pad normal (structure up)
var radius_m: float = 0.0              ## StructureDef.pad_radius_m
var valid: bool = false                ## alive, friendly and accepting this ship
var busy: bool = false                 ## occupied by, queued for or claimed by another ship
var threat: bool = false               ## an enemy bomb or rocket inbound within the threat radius (05 s5.5)
