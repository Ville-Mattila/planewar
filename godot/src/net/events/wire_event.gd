class_name WireEvent extends RefCounted
## One decoded EVENTS entry (04 s3.6): the kind, the tick of its packet, the payload fields in table order
## (`pos_q` / `pos` hold the vec3q field of BOMB_IMPACT and ALERT) and the field count.

var kind: int = 0
var tick: int = 0
var v: PackedInt32Array = PackedInt32Array()
var count: int = 0
var pos_q: int = Codec.POS_INVALID
var pos: Vector3 = Vector3.ZERO
