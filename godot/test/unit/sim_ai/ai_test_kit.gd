class_name AiTestKit extends RefCounted
## AI-04 fixtures: a view that reports every id alive and AUTO (ids in `possessed` are POSSESSED, ids in `dead` are
## gone), and a brain that counts thinks per slot and records the tick of each think of a watched slot.

class StubView extends SimView:
	var possessed: Dictionary = {}
	var dead: Dictionary = {}

	func alive(id: int) -> bool:
		return not dead.has(id)

	func control_state(id: int) -> int:
		return 2 if possessed.has(id) else 0


class CountBrain extends AiBrain:
	var thinks: PackedInt32Array = PackedInt32Array()
	var acts: int = 0
	var bot_ticks: PackedInt32Array = PackedInt32Array()
	var per_tick_max: int = 0

	func _init() -> void:
		var _e: int = thinks.resize(EntityStore.SLOT_COUNT)

	func think_batch(ids: PackedInt32Array, n: int, _v: SimView, _st: AiState, _sink: CommandSink, _tick: int) -> void:
		per_tick_max = maxi(per_tick_max, n)
		for i: int in n:
			thinks[EntityId.slot(ids[i])] += 1

	func act_batch(ids: PackedInt32Array, _v: SimView, _st: AiState, _sink: CommandSink) -> void:
		acts += ids.size()

	func think_bot(slot: int, _tier: int, tick: int, _v: SimView, _sink: CommandSink) -> void:
		var _a: bool = bot_ticks.append(tick * 100 + slot)


## A driver with `n` entities (ids 1..n, generation 1) in class 0 and a CountBrain.
static func driver(n: int, p: int = 10, cut: int = 15) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(5), p, cut)
	d.set_brain(0, CountBrain.new(), true)
	for s: int in range(1, n + 1):
		var _ok: bool = d.register(EntityId.make(s, 1), 0)
	return d


static func run(d: AiDriver, v: SimView, from_tick: int, ticks: int) -> void:
	var sink: CommandSinkBase = CommandSinkBase.new()
	for t: int in ticks:
		d.on_tick(from_tick + t, v, sink)
