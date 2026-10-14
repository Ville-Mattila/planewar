class_name FireTestKit extends RefCounted
## GD-36 fixtures: a hook that holds trigger buttons on chosen entities every tick (step 3, through the sink like
## any autopilot), shot logs read from the store (a shot = a drop of the ammo field), and the projectiles a shooter owns.

const R: float = Sphere.PLANET_RADIUS


static func at(alt: float, east: float = 0.0, north: float = 0.0) -> Vector3:
	return Vector3(R + alt, east, north)


## Holds `buttons[k]` on `ids[k]` every tick from now on (0 releases).
class TriggerHook extends SimAiHook:
	var ids: PackedInt32Array = PackedInt32Array()
	var buttons: PackedInt32Array = PackedInt32Array()
	var _in: PilotInput = PilotInput.new()

	func hold(id: int, b: int) -> void:
		var k: int = ids.find(id)
		if k < 0:
			ids.push_back(id)
			buttons.push_back(b)
		else:
			buttons[k] = b

	func on_tick(_t: int, _v: SimView, sink: CommandSinkBase) -> void:
		for k: int in ids.size():
			_in.buttons = buttons[k]
			var _ok: bool = sink.drive(ids[k], _in)

	func serialize() -> PackedByteArray:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.put_var(ids)
		b.put_var(buttons)
		return b.data_array

	func deserialize(bytes: PackedByteArray) -> void:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.data_array = bytes
		if bytes.size() > 0:
			ids = b.get_var()
			buttons = b.get_var()


static func hook(w: SimWorld) -> TriggerHook:
	var h: TriggerHook = TriggerHook.new()
	w.set_ai_hook(h)
	return h


## Steps `ticks` times; returns the tick of every step on which `id`'s `field` ("ammo", "bombs", "rockets") dropped,
## once per round spent (a two-round salvo appears twice).
static func shot_ticks(w: SimWorld, id: int, ticks: int, field: StringName = &"ammo") -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var s: int = EntityId.slot(id)
	var last: int = count(w, s, field)
	for _k: int in ticks:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		var now: int = count(w, s, field)
		for _r: int in last - now:
			out.push_back(w.tick())
		last = now
	return out


static func count(w: SimWorld, s: int, field: StringName) -> int:
	match field:
		&"bombs":
			return w.store().bombs[s]
		&"rockets":
			return w.store().rockets[s]
	return w.store().ammo[s]


## Live projectiles fired by `shooter` (EntityId), ascending local index.
static func fired_by(w: SimWorld, shooter: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var ps: ProjectileStore = w.projectiles()
	for i: int in ps.live:
		if ps.shooter[i] == shooter:
			out.push_back(i)
	return out


## Gaps between consecutive ticks of `ticks`.
static func gaps(ticks: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: int in range(1, ticks.size()):
		out.push_back(ticks[k] - ticks[k - 1])
	return out


## The world's Combat (lane-internal; GD-18 reaches `fire.unsupplied` the same way from inside SimWorld).
static func combat(w: SimWorld) -> Combat:
	return w._combat
