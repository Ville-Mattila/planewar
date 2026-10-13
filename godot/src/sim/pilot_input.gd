class_name PilotInput extends RefCounted
## One tick of control for one entity (01 s9.4, sim/MODULE.md). Every device and every autopilot produces
## exactly this; the sim never knows which. Axes: thrust 0..1, pitch/yaw/roll -1..1 (Kinematics clamps).
## Ships: pitch + nose up, yaw + nose left (rotation about body up), roll + right wing down.
## The 8-byte wire form (`to_bytes` / `from_bytes`, 04 s2.4) is added by NET-03.

const BOOST: int = 1
const BRAKE: int = 2
const FLIP: int = 4
const FIRE1: int = 8
const FIRE2: int = 16
const DOCK: int = 32
const RELEASE: int = 64

var thrust: float
var pitch: float
var yaw: float
var roll: float
var buttons: int
