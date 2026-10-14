class_name EntityView
extends MeshInstance3D
## One pooled entity view (03 s10.1): the mesh node plus the bookkeeping `EntityViewPool` needs. Never freed;
## bound to an EntityId nearest-first, released on death or invisibility after a short linger.

var id: int = 0
var group: int = -1
var team: int = -1
var state: int = -1
var linger_until: float = -1.0   ## render_time at which a lingering view returns to the free list; < 0 = not lingering
var prev_pos: Vector3 = Vector3.ZERO
var cur_pos: Vector3 = Vector3.ZERO
var prev_q: Quaternion = Quaternion.IDENTITY
var cur_q: Quaternion = Quaternion.IDENTITY
var seen_tick: int = -1
var scale_m: float = 1.0
