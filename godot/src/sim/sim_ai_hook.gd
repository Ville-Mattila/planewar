class_name SimAiHook extends RefCounted
## Abstract AI hook (05 s1.3, R0 B.4/B.5). `sim_ai`'s `AiDriver` implements it; the sim never imports `sim_ai`.
## `SimWorld.step()` calls `on_tick` once per tick at tick-order step 3; `serialize` / `deserialize` carry the
## hook's opaque state inside `SimWorld.serialize()` (S4).


## Tick-order step 3: think slice + act for every AI-driven entity, writing input slots through `sink.drive`.
func on_tick(_tick: int, _view: SimView, _sink: CommandSinkBase) -> void:
	pass


## Opaque hook state appended to `SimWorld.serialize()`; empty by default.
func serialize() -> PackedByteArray:
	return PackedByteArray()


## Receives the bytes `serialize` produced, from `SimWorld.deserialize`.
func deserialize(_bytes: PackedByteArray) -> void:
	pass
