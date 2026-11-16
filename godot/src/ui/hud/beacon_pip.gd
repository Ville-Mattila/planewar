class_name BeaconPip extends RefCounted
## Compass pip of a Supply Canister beacon: plain data. `x` is the offset from the tape centre in du.

var canister: int = 0
var pos: Vector3 = Vector3.ZERO
var dist: float = 0.0
var x: float = 0.0
var on_tape: bool = true
