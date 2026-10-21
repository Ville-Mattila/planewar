class_name AiBrain extends RefCounted
## Class brain contract (05 s4.3): one instance per unit class, driven in batches by `AiDriver`. The base does nothing,
## which is also what scheduling-overhead perf tests use. Overrides keep all per-entity data in `AiState` arrays.


## Think slice for the `n` entity ids in `ids[0..n)` that are due this tick (scratch array: do not keep it).
func think_batch(_ids: PackedInt32Array, _n: int, _view: SimView, _st: AiState, _sink: CommandSink, _tick: int) -> void:
	pass


## Act every tick for all `ids` of the class (POSSESSED / dead ones are refused by `sink.drive`, S11).
func act_batch(_ids: PackedInt32Array, _view: SimView, _st: AiState, _sink: CommandSink) -> void:
	pass


## One Commander / Adjutant think for bot `slot` of difficulty `tier` (0 easy .. 3 brutal), on its staggered tick.
func think_bot(_slot: int, _tier: int, _tick: int, _view: SimView, _sink: CommandSink) -> void:
	pass


## AI-13: the driver's `Rng.fork(&"ai")` stream, bound on `set_brain` and again after `deserialize` (which replaces the
## stream object); a brain that draws (aim error, 05 s6.2) keeps this reference and never another source.
func bind_rng(_rng: Rng) -> void:
	pass
