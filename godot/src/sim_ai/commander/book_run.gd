class_name BookRun extends RefCounted
## One bot's progress through its `OpeningBook`: the cursor, one outcome per step and the live counters of the step at the
## cursor. All of it is S4 state (`serialize`); the book itself is session configuration (content), identified by id and
## step count so bytes of another book are refused.

const PENDING: int = 0
const DONE: int = 1
const SKIPPED_HAVE: int = 2
const SKIPPED_REJECTS: int = 3
const SKIPPED_STALL: int = 4
const SKIPPED_FAIL: int = 5
const FORMAT: int = 1

var book: OpeningBook
var cursor: int = 0
var done: bool = false              ## handed over to the reactive planner (last step passed, or `book_end_s`)
var outcome: PackedByteArray = PackedByteArray()
var rejects: int = 0                ## REJECTED_PLACEMENT of the cursor step
var cand_k: int = 0                 ## candidate index of the next attempt
var issued: int = 0                 ## units / structures of the cursor step already issued
var due_tick: int = -1              ## tick the cursor step first became due (stall clock); -1 not yet
var wait_tick: int = -1             ## tick the cursor step first waited for presence (retry clock)


func _init(b: OpeningBook) -> void:
	book = b
	var _r: int = outcome.resize(b.n_steps)
	outcome.fill(PENDING)


## Closes the cursor step with `code` and moves on; the counters of the next step start fresh.
func finish(code: int) -> void:
	outcome[cursor] = code
	cursor += 1
	rejects = 0
	cand_k = 0
	issued = 0
	due_tick = -1
	wait_tick = -1
	if cursor >= book.n_steps:
		done = true


func serialize() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(FORMAT)
	b.put_utf8_string(String(book.id))
	b.put_32(book.n_steps)
	b.put_32(cursor)
	b.put_u8(1 if done else 0)
	b.put_32(rejects)
	b.put_32(cand_k)
	b.put_32(issued)
	b.put_32(due_tick)
	b.put_32(wait_tick)
	var _e: Error = b.put_data(outcome)
	return b.data_array


## False (and the run untouched) for bytes of another book or malformed bytes.
func deserialize(bytes: PackedByteArray) -> bool:
	if bytes.size() < 8:
		return false
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	if b.get_u8() != FORMAT or b.get_utf8_string() != String(book.id) or b.get_32() != book.n_steps:
		return false
	if b.get_available_bytes() != 4 + 1 + 20 + book.n_steps:
		return false
	var cur: int = b.get_32()
	var dn: bool = b.get_u8() != 0
	var rj: int = b.get_32()
	var ck: int = b.get_32()
	var iss: int = b.get_32()
	var dt: int = b.get_32()
	var wt: int = b.get_32()
	var data: Array = b.get_data(book.n_steps)
	if cur < 0 or cur > book.n_steps or data[0] != OK:
		return false
	cursor = cur
	done = dn
	rejects = rj
	cand_k = ck
	issued = iss
	due_tick = dt
	wait_tick = wt
	outcome = data[1]
	return true
