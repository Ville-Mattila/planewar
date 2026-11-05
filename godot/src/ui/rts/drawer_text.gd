class_name DrawerText extends RefCounted
## Locale keys and arguments for the production drawer (docs/06 s7.5). The key/args pairs are pure and testable;
## `reason` and `slot_label` translate them. No literal user-facing text here.


## Locale key of the reason a tile cannot be used; empty for AVAILABLE.
static func reason_key(info: TileInfo) -> StringName:
	match info.state:
		DrawerMath.State.UNAFFORDABLE:
			return &"ui.prod.reason.ice" if info.short.y > 0 and info.short.x == 0 else &"ui.prod.reason.ore"
		DrawerMath.State.SPEND_LOCKED:
			return &"ui.prod.reason.lock"
		DrawerMath.State.LOCKED:
			return &"ui.prod.reason.locked"
		DrawerMath.State.CAP_REACHED:
			return &"ui.prod.reason.cap"
	return &""


static func reason_args(info: TileInfo) -> Dictionary:
	return {
		"time": Fmt.duration(int(DrawerMath.lock_end_s())),
		"left": info.lock_left_ore,
		"need": DrawerCatalog.name_key(info.need),
		"ore": info.short.x,
		"ice": info.short.y,
	}


## "Share locked until 2:00" etc.; empty for an AVAILABLE tile.
static func reason(info: TileInfo) -> String:
	var k: StringName = reason_key(info)
	if k == &"":
		return ""
	var args: Dictionary = reason_args(info)
	args["need"] = TranslationServer.translate(StringName(DrawerCatalog.name_key(info.need)))
	return TranslationServer.translate(k).format(args)


## Short tile caption under the name: the prerequisite, a lock or a cap mark; empty otherwise.
static func caption_key(info: TileInfo) -> StringName:
	match info.state:
		DrawerMath.State.LOCKED:
			return StringName(DrawerCatalog.name_key(info.need))
		DrawerMath.State.SPEND_LOCKED:
			return &"ui.prod.tile.lock"
		DrawerMath.State.CAP_REACHED:
			return &"ui.prod.tile.cap"
	return &""


static func slot_key(slot: DetailSlot) -> StringName:
	match slot.kind:
		DetailSlot.Kind.BACK:
			return &"ui.prod.back"
		DetailSlot.Kind.BATCH:
			return &"ui.prod.batch"
		DetailSlot.Kind.CANCEL_LAST:
			return &"ui.prod.cancel_last"
		DetailSlot.Kind.REPL_DEC:
			return &"ui.prod.minus"
		DetailSlot.Kind.REPL_VALUE:
			return &"ui.prod.auto"
		DetailSlot.Kind.REPL_INC:
			return &"ui.prod.plus"
	return &"ui.prod.cancel_item"


## The slot caption with `{n}` filled: the batch size, the replenish target or the 1-based queue position.
static func slot_label(slot: DetailSlot, info: TileInfo) -> String:
	var n: int = 0
	match slot.kind:
		DetailSlot.Kind.BATCH:
			n = int(RtsParams.param("batch_count"))
		DetailSlot.Kind.REPL_VALUE:
			n = info.replenish
		DetailSlot.Kind.QUEUE_ITEM:
			n = slot.index + 1
	return TranslationServer.translate(slot_key(slot)).format({"n": n})
