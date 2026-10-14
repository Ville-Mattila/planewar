class_name ReplayRig extends RefCounted
## Test helper (NET-25): records a SnapRig scene into a ReplayWriter (memory mode) and remembers the live quantised
## positions at chosen ticks so the tests can compare what the reader reconstructs.

var snap: SnapRig = SnapRig.new()
var writer: ReplayWriter = ReplayWriter.new()
var header: ReplayHeader = ReplayHeader.new()
var slots: PackedInt32Array = PackedInt32Array()
var saved_ticks: PackedInt32Array = PackedInt32Array()
var saved_pos: Array[PackedVector3Array] = []
var saved_hp: Array[PackedFloat32Array] = []
var file: PackedByteArray = PackedByteArray()
var written_bytes: int = 0
var last_tick: int = 0
var _events_at: Dictionary = {}


## n entities in the 04 s4.5 tier proportions scaled to `sizes` / `movers`.
func build(sizes: Vector3i, movers: Vector3i, bombs: int, seed_value: int) -> void:
	snap.build(sizes, movers, bombs, seed_value)
	for i: int in snap.frame.count:
		var _p: bool = slots.push_back(i)
	header.map_id = "test-map"
	header.seed_value = seed_value
	header.started_unix = 1760000000
	header.content_hash = PackedByteArray([1, 2, 3])
	header.match_id = PackedByteArray([9, 8, 7])
	header.add_player(0, 0, 0, 1, 0, PackedByteArray([0xAA, 0xBB]), "Alice")
	header.add_player(1, 1, 1, 2, 1, PackedByteArray([0xCC]), "Bobby Tables")


## Events to feed at `tick` (SimEvent list).
func add_events(tick: int, list: Array[SimEvent]) -> void:
	_events_at[tick] = list


## Runs `ticks` sim ticks; every tick whose number % save_every == 1 is remembered (written ticks are 1, 4, 7 ...).
func run(ticks: int, save_every: int = 30, chat_at: int = -1, inputs_at: int = -1) -> void:
	var _e: int = writer.open_memory(header)
	var none: Array[SimEvent] = []
	for _t: int in ticks:
		snap.step()
		var ev: Array[SimEvent] = _events_at.get(snap.tick, none)
		writer.record_tick(snap.codec, snap.tick, slots, snap.roster, ev)
		if snap.tick % save_every == 1:
			var _a: bool = saved_ticks.push_back(snap.tick)
			saved_pos.append(snap.frame.pos.duplicate())
			saved_hp.append(snap.frame.hp01.duplicate())
		if snap.tick == inputs_at:
			var inputs: PackedByteArray = PackedByteArray()
			var _r: int = inputs.resize(ReplayFormat.INPUT_ENTRY_BYTES - 5)
			for i: int in inputs.size():
				inputs[i] = (i * 7) & 0xFF
			writer.record_input_summary(snap.tick, PackedInt32Array([1]), PackedInt32Array([EntityId.make(7, 1)]), inputs)
		if snap.tick == chat_at:
			writer.record_chat(snap.tick, 77, 1, 0, "hello secret")
	last_tick = snap.tick
	file = writer.finish(PackedByteArray([0xEE, 0xEE]), snap.tick)
	written_bytes = file.size()


func new_reader() -> ReplayReader:
	var r: ReplayReader = ReplayReader.new(SnapRig.G, SnapRig.HZ)
	var _x: int = r.decoder.gravity_def.resize(4)
	r.decoder.gravity_def[SnapRig.DEF_BOMB] = 1
	return r


## Largest distance between the reader's current frame and the saved live positions of save index `k`.
func max_error(r: ReplayReader, k: int) -> float:
	var f: BaselineFrame = r.current()
	var worst: float = 0.0
	for i: int in snap.frame.count:
		if f.present[i] == 0:
			return INF
		worst = maxf(worst, r.position_of(i).distance_to(saved_pos[k][i]))
	return worst
