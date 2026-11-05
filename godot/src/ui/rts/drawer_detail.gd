class_name DrawerDetail extends RefCounted
## The detail page of one tile (long-press / RMB / pad X, docs/06 s7.5): a list of tile-sized slots that reuse the
## 3 x 6 grid. Units get x5, cancel one, the replenish stepper (0-12) and one slot per queue item; a structure gets
## its construction sites as queue items (CANCEL_BUILD). `verdicts` is one DrawerMath.Cancel per item.


const FIXED_SLOTS: int = 6    ## back, batch, cancel one, replenish -, value, + (queue items follow)


## `has_factory`: false disables the batch and the replenish stepper (there is nowhere to queue).
static func slots(info: TileInfo, queue_len: int, verdicts: PackedInt32Array, has_factory: bool = true) -> Array[DetailSlot]:
	var out: Array[DetailSlot] = []
	out.append(_slot(DetailSlot.Kind.BACK, 0, true, &""))
	if info.is_unit:
		var room: bool = DrawerMath.batch(queue_len) > 0
		var ok: bool = info.state == DrawerMath.State.AVAILABLE and room and has_factory
		out.append(_slot(DetailSlot.Kind.BATCH, 0, ok, &"" if ok else (&"ui.prod.reason.queue_full" if not room else &"ui.prod.reason.unavailable")))
		var last: DrawerMath.Cancel = _verdict(verdicts, queue_len - 1)
		var can: bool = queue_len > 0 and DrawerMath.cancel_allowed(last)
		var why: StringName = &"ui.prod.reason.queue_empty" if queue_len == 0 else DrawerMath.cancel_reason(last)
		out.append(_slot(DetailSlot.Kind.CANCEL_LAST, 0, can, why))
		out.append(_slot(DetailSlot.Kind.REPL_DEC, 0, has_factory and info.replenish > 0, &"ui.prod.reason.unavailable"))
		out.append(_slot(DetailSlot.Kind.REPL_VALUE, 0, false, &""))
		out.append(_slot(DetailSlot.Kind.REPL_INC, 0, has_factory and DrawerMath.stepper(info.replenish, 1) > info.replenish, &"ui.prod.reason.unavailable"))
	for i: int in queue_len:
		var v: DrawerMath.Cancel = _verdict(verdicts, i)
		out.append(_slot(DetailSlot.Kind.QUEUE_ITEM, i, DrawerMath.cancel_allowed(v), DrawerMath.cancel_reason(v)))
	return out


static func _verdict(verdicts: PackedInt32Array, i: int) -> DrawerMath.Cancel:
	if i < 0 or i >= verdicts.size():
		return DrawerMath.Cancel.UNKNOWN
	return verdicts[i] as DrawerMath.Cancel


static func _slot(kind: DetailSlot.Kind, index: int, enabled: bool, reason: StringName) -> DetailSlot:
	var s: DetailSlot = DetailSlot.new()
	s.kind = kind
	s.index = index
	s.enabled = enabled
	s.reason = &"" if enabled else reason
	return s
