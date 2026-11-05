class_name DrawerMath extends RefCounted
## Production drawer rules as pure functions (docs/06 s7.5, R0 C3-08): tile state priority, the early share lock,
## factory choice, steppers and who may cancel. Numbers from economy.json and content/ui/rts.json.

enum State { AVAILABLE, UNAFFORDABLE, SPEND_LOCKED, LOCKED, CAP_REACHED }
## UNKNOWN: the queuer is not readable (needs sim: SimView.production_queuer); the sim answers a cancel itself.
enum Cancel { UNKNOWN, OWNER, DELEGATED, DENIED_NOT_OWNER, DENIED_TEAM }

const KIND_BOT: int = 1    ## PlayerStateView.kind ordinals (R0 B.3 PlayerKind); test-pinned to PlayerTable
const KIND_OPEN: int = 2


## The sim's PRODUCE check order (tech, cap, cost, early share lock) with the drawer's single state per tile.
static func classify(tech_ok: bool, capped: bool, cost: Vector2i, stock: Vector2i, lock_left_ore: int) -> State:
	if not tech_ok:
		return State.LOCKED
	if capped:
		return State.CAP_REACHED
	if cost.x > stock.x or cost.y > stock.y:
		return State.UNAFFORDABLE
	if lock_blocks(lock_left_ore, cost.x):
		return State.SPEND_LOCKED
	return State.AVAILABLE


## Ore and Ice still missing, both >= 0.
static func short_of(cost: Vector2i, stock: Vector2i) -> Vector2i:
	return Vector2i(maxi(cost.x - stock.x, 0), maxi(cost.y - stock.y, 0))


## `lock_left_ore` = PlayerStateView.early_spend_left_ore: < 0 when the lock is over or does not apply.
static func lock_blocks(lock_left_ore: int, cost_ore: int) -> bool:
	return lock_left_ore >= 0 and cost_ore > lock_left_ore


static func lock_end_s() -> float:
	return ContentDB.economy.early_share_lock_s if ContentDB.economy != null else 0.0


static func share_ore() -> int:
	return ContentDB.economy.early_share_ore if ContentDB.economy != null else 0


static func queue_max() -> int:
	return ContentDB.economy.queue_max if ContentDB.economy != null else 0


static func stepper(value: int, delta: int) -> int:
	return clampi(value + delta, 0, int(RtsParams.param("replenish_max")))


## Items a long-press batch may add: `batch_count`, clipped to the free queue slots.
static func batch(queue_len: int) -> int:
	return maxi(mini(int(RtsParams.param("batch_count")), queue_max() - queue_len), 0)


## Team factory with the shortest queue; ties go to the nearest (`dist2` from the focus), then the lowest id.
## Full queues are skipped; -1 when none is left.
static func pick_factory(ids: PackedInt32Array, queue_lens: PackedInt32Array, dist2: PackedFloat32Array) -> int:
	var best: int = -1
	for i: int in ids.size():
		if queue_lens[i] >= queue_max():
			continue
		if best < 0:
			best = i
		elif queue_lens[i] < queue_lens[best]:
			best = i
		elif queue_lens[i] == queue_lens[best]:
			if dist2[i] < dist2[best] or (dist2[i] == dist2[best] and ids[i] < ids[best]):
				best = i
	return ids[best] if best >= 0 else -1


## Owner-only cancel (R0 C3-08, mirrors PlayerTable.cancel_delegable): the queuer, or a teammate when the queuer is
## disconnected, eliminated, a bot or an open slot. Never across teams.
static func cancel_verdict(local: int, local_team: int, queuer: int, queuer_team: int, queuer_kind: int,
		queuer_connected: bool, queuer_eliminated: bool) -> Cancel:
	if queuer < 0:
		return Cancel.UNKNOWN
	if queuer == local:
		return Cancel.OWNER
	if queuer_team != local_team:
		return Cancel.DENIED_TEAM
	var delegable: bool = queuer_kind == KIND_BOT or queuer_kind == KIND_OPEN or not queuer_connected or queuer_eliminated
	return Cancel.DELEGATED if delegable else Cancel.DENIED_NOT_OWNER


static func cancel_allowed(c: Cancel) -> bool:
	return c != Cancel.DENIED_NOT_OWNER and c != Cancel.DENIED_TEAM


## Locale key of the disabled-cancel reason; empty when the cancel is allowed.
static func cancel_reason(c: Cancel) -> StringName:
	match c:
		Cancel.DENIED_NOT_OWNER:
			return &"ui.prod.cancel.not_owner"
		Cancel.DENIED_TEAM:
			return &"ui.prod.cancel.other_team"
	return &""
