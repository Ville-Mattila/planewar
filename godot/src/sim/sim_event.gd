class_name SimEvent extends RefCounted
## One sim event (R0 B.3; append-only ordinals). Emitted only inside `SimWorld.step()`, stamped with the tick of
## that step (S5), drained once by the caller (tick-order step 12). Field use per kind: sim/MODULE.md Enumerations;
## enumerated sub-reasons (`ReleaseReason`, death cause) travel in `extra[0]`.

enum Kind { SPAWN, DEATH, HIT, BOMB_IMPACT, DOCKED, SERVICED, LAUNCHED, ORDER_DONE, ORDER_FAILED, POSSESSED, RELEASED,
		BUILD_STARTED, BUILD_DONE, STRUCTURE_LOST, LOW_POWER, ALERT, CORE_EXPOSURE, MATCH_END, CAP_REACHED, WRECK_SPAWNED,
		WRECK_SALVAGED, CEILING_RELEASE, HANDOVER, PLAYER_ELIMINATED, LOCK_ACQUIRED, LOCK_BROKEN, CAPTURE_PROGRESS, CAPTURED,
		SALVAGE_DELIVERED, LANDING, SHIELD_COLLAPSE, POSSESS_REQUESTED, CANISTER_DEPLOYED, CANISTER_COLLECTED }

## DEATH `extra[0]` (R0 B.3 / B.20 A-106; append-only, GD-20 appends from 2).
enum DeathCause { DEBUG, EXPIRED }

var kind: Kind = Kind.SPAWN
var tick: int = 0
var a: int = 0
var b: int = 0
var pos: Vector3 = Vector3.ZERO
var value: float = 0.0
var team: int = -1
var extra: PackedByteArray = PackedByteArray()
