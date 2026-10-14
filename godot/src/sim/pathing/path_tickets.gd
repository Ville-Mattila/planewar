class_name PathTickets extends RefCounted
## Ticket pool and FIFO queue of Pathing (TA-20; split out by TA-50): MAX_TICKETS slots of request, state and result
## cells in flat packed arrays, generation-stamped handles, a ring of queued slots. Pathing extends it so the job
## code reads the slots as own members (P8: no cross-object packed access). S4 bytes: write_state / read_state.

const NO_TICKET: int = -1
const ST_UNKNOWN: int = 0                  ## stale or never issued ticket
const ST_PENDING: int = 1
const ST_DONE: int = 2
const ST_NO_PATH: int = 3
const MAX_TICKETS: int = 160               ## 03 s3.2 path_tickets row
const MAX_CELLS: int = PathGrid.N * 4      ## longest result in cells
const _GEN_SHIFT: int = 8
const _TICKET_STATE: PackedStringArray = ["_t_gen", "_t_state", "_t_start", "_t_goal", "_t_mask", "_t_len", "_t_seq",
	"_t_req_tick", "_t_done_tick", "_t_splice", "_t_queued", "_q", "_qh", "_qn", "_seq"]

var _t_gen: PackedInt32Array = _ints(MAX_TICKETS)
var _t_state: PackedInt32Array = _ints(MAX_TICKETS)
var _t_start: PackedInt32Array = _ints(MAX_TICKETS)
var _t_goal: PackedInt32Array = _ints(MAX_TICKETS)
var _t_mask: PackedInt32Array = _ints(MAX_TICKETS)
var _t_len: PackedInt32Array = _ints(MAX_TICKETS)
var _t_seq: PackedInt32Array = _ints(MAX_TICKETS)
var _t_req_tick: PackedInt32Array = _ints(MAX_TICKETS)
var _t_done_tick: PackedInt32Array = _ints(MAX_TICKETS)
var _t_splice: PackedByteArray = _bytes(MAX_TICKETS)
var _t_queued: PackedByteArray = _bytes(MAX_TICKETS)   ## 1 while the slot sits in the FIFO (never re-allocated then)
var _t_cells: PackedInt32Array = _ints(MAX_TICKETS * MAX_CELLS)
var _q: PackedInt32Array = _ints(MAX_TICKETS)
var _qh: int = 0
var _qn: int = 0
var _seq: int = 0


func status(ticket: int) -> int:
	var sl: int = _slot(ticket)
	return _t_state[sl] if sl >= 0 else ST_UNKNOWN


## advance() count at which the ticket completed (-1 while pending or unknown); request tick via request_tick.
func done_tick(ticket: int) -> int:
	var sl: int = _slot(ticket)
	return _t_done_tick[sl] if sl >= 0 and _t_state[sl] >= ST_DONE else -1


func request_tick(ticket: int) -> int:
	var sl: int = _slot(ticket)
	return _t_req_tick[sl] if sl >= 0 else -1


## Frees the ticket (a pending query is dropped); the handle turns ST_UNKNOWN.
func release(ticket: int) -> void:
	var sl: int = _slot(ticket)
	if sl >= 0:
		_t_state[sl] = ST_UNKNOWN
		_t_gen[sl] = (_t_gen[sl] + 1) & 0xFFFFF


func pending() -> int:  # queued tickets
	return _qn


func _slot(ticket: int) -> int:
	if ticket < 0:
		return -1
	var sl: int = ticket & ((1 << _GEN_SHIFT) - 1)
	if sl >= MAX_TICKETS or (ticket >> _GEN_SHIFT) != _t_gen[sl] or _t_state[sl] == ST_UNKNOWN:
		return -1
	return sl


# A free slot, else the oldest finished one (its handle turns stale), else -1.
func _alloc() -> int:
	var best: int = -1
	for sl: int in MAX_TICKETS:
		var st: int = _t_state[sl]
		if _t_queued[sl] != 0:
			continue
		if st == ST_UNKNOWN:
			best = sl
			break
		if st != ST_PENDING and (best < 0 or _t_seq[sl] < _t_seq[best]):
			best = sl
	if best < 0:
		return -1
	if _t_state[best] != ST_UNKNOWN:
		_t_gen[best] = (_t_gen[best] + 1) & 0xFFFFF
	_seq += 1
	_t_seq[best] = _seq
	_t_state[best] = ST_PENDING
	_t_done_tick[best] = -1
	return best


static func _ints(n: int) -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	var _r: int = a.resize(n)
	return a


static func _bytes(n: int) -> PackedByteArray:
	var a: PackedByteArray = PackedByteArray()
	var _r: int = a.resize(n)
	return a


## S4 (TA-50): the slot arrays, the queue ring, then each slot's result cells (_t_len of them) back to back.
func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _TICKET_STATE)
	var cells: PackedInt32Array = PackedInt32Array()
	for sl: int in MAX_TICKETS:
		cells.append_array(_t_cells.slice(sl * MAX_CELLS, sl * MAX_CELLS + _t_len[sl]))
	buf.put_var(cells)


## Inverse of write_state; false on malformed bytes.
func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _TICKET_STATE):
		return false
	for a: PackedInt32Array in [_t_gen, _t_state, _t_start, _t_goal, _t_mask, _t_len, _t_seq, _t_req_tick, _t_done_tick, _q]:
		if a.size() != MAX_TICKETS:
			return false
	if _t_splice.size() != MAX_TICKETS or _t_queued.size() != MAX_TICKETS:
		return false
	var cv: Variant = buf.get_var()
	if typeof(cv) != TYPE_PACKED_INT32_ARRAY:
		return false
	var cells: PackedInt32Array = cv
	var at: int = 0
	for sl: int in MAX_TICKETS:
		var n: int = _t_len[sl]
		if n < 0 or n > MAX_CELLS or at + n > cells.size():
			return false
		for k: int in n:
			_t_cells[sl * MAX_CELLS + k] = cells[at + k]
		at += n
	return at == cells.size()
