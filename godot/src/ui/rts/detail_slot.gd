class_name DetailSlot extends RefCounted
## One tile-sized button of the production drawer's long-press detail page (docs/06 s7.5): x5, cancel one,
## auto-replenish stepper and the queue items. `reason` is a locale key shown when the slot is disabled.

enum Kind { BACK, BATCH, CANCEL_LAST, REPL_DEC, REPL_VALUE, REPL_INC, QUEUE_ITEM }

var kind: Kind = Kind.BACK
var index: int = 0           ## queue item index (QUEUE_ITEM)
var enabled: bool = true
var reason: StringName = &""
