class_name SimAiHook extends RefCounted
## Abstract AI hook (05 s1.3, R0 B.4/B.5). `sim_ai`'s `AiDriver` implements it; the sim never imports `sim_ai`.
## `SimWorld.step()` calls `on_event` for the previous tick's drained events, then `on_tick`, once per tick at tick-order step 3; `serialize` / `deserialize` carry the
## hook's opaque state inside `SimWorld.serialize()` (S4).


## Tick-order step 3: think slice + act for every AI-driven entity, writing input slots through `sink.drive`.
func on_tick(_tick: int, _view: SimView, _sink: CommandSinkBase) -> void:
	pass


## Tick-order step 3, before `on_tick`: once per event the caller drained after the previous tick, in `SimEvents`
## order (A-71, TA-57). Base: no-op. Runs inside `step()`; the hook must not emit events.
func on_event(_ev: SimEvent) -> void:
	pass


## Opaque hook state appended to `SimWorld.serialize()`; empty by default.
func serialize() -> PackedByteArray:
	return PackedByteArray()


## Receives the bytes `serialize` produced, from `SimWorld.deserialize`.
func deserialize(_bytes: PackedByteArray) -> void:
	pass
