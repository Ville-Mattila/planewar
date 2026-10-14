class_name CommandResult extends RefCounted
## Verdict of `SimWorld.apply_command` / `CommandSinkBase.submit` (01 s9.4, R0 B.3). `reject` carries the
## `Build.Reject` ordinal when `code == REJECTED_PLACEMENT`, else 0.

enum Code { ACCEPTED, REJECTED_DEAD, REJECTED_NOT_OWNER, REJECTED_NOT_POSSESSABLE, REJECTED_ALREADY_POSSESSED, REJECTED_NO_RIGHTS,
		REJECTED_CAP, REJECTED_COST, REJECTED_PLACEMENT, REJECTED_RATE, REJECTED_MALFORMED, REJECTED_INVALID_ORDER,
		REJECTED_UPLINK, REJECTED_PHASE, REJECTED_LOCKED }

var code: Code = Code.ACCEPTED
var reject: int = 0
