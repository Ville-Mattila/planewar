class_name PadQueue extends RefCounted
## 03 s3.2 `pad_queues` (GD-15): the ships waiting for a service pad, in arrival order, at most `PER_PAD` per pad. A
## ship waits for pad P on a tick when it is a live, not-docked ship of P's team that wants a pad (its head order is
## RETURN, or it is possessed with DOCK held), P is busy (occupied) or already has a queue, and P is the nearest such
## pad within `economy.pad_queue_radius_m` of the ship, horizontally in the pad frame (A-125). Entries are kept while
## that holds, new ones are appended in ascending ship slot; a ship that docks, dies, loses the wish or leaves the radius drops out. While P has a queue
## only its head may land on P (03 s6.4 "pad free"). One flat list (pairs in arrival order) so no packed array lives in a
## container (03 s12.2 rule 11); saved with the economy section (S4).

const PER_PAD: int = 8                         ## 03 s3.2 structural bound "<= 8 waiting per pad" (R0 B.24 A-127)

var q_pad: PackedInt32Array = PackedInt32Array()    ## pad EntityId per entry, arrival order
var q_ship: PackedInt32Array = PackedInt32Array()   ## ship EntityId per entry

const _STATE: PackedStringArray = ["q_pad", "q_ship"]

var _keep_pad: PackedInt32Array = PackedInt32Array()
var _keep_ship: PackedInt32Array = PackedInt32Array()
var _pass: int = 0                                   ## update serial: the per-slot marks below are valid when equal
var _want: PackedInt32Array = PackedInt32Array()     ## per ship slot: the pad wished this update
var _want_mark: PackedInt32Array = PackedInt32Array()
var _kept_mark: PackedInt32Array = PackedInt32Array()   ## per ship slot: already in the new list
var _cnt: PackedInt32Array = PackedInt32Array()      ## per pad slot: entries in the new list
var _cnt_mark: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var n: int = InputSlots.ENTITY_SLOTS
	var e: int = _want.resize(n) | _want_mark.resize(n) | _kept_mark.resize(n) | _cnt.resize(n) | _cnt_mark.resize(n)
	assert(e == OK)
	_want_mark.fill(0)
	_kept_mark.fill(0)
	_cnt_mark.fill(0)


## Ships waiting for `pad`, in arrival order (allocates: a list getter, S3).
func of(pad: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: int in q_pad.size():
		if q_pad[k] == pad:
			var _a: bool = out.push_back(q_ship[k])
	return out


## The first waiting ship of `pad`, 0 when none.
func head(pad: int) -> int:
	for k: int in q_pad.size():
		if q_pad[k] == pad:
			return q_ship[k]
	return 0


func count(pad: int) -> int:
	var n: int = 0
	for k: int in q_pad.size():
		n += 1 if q_pad[k] == pad else 0
	return n


## The pad `ship` is queued for, 0 when none.
func pad_of(ship: int) -> int:
	for k: int in q_ship.size():
		if q_ship[k] == ship:
			return q_pad[k]
	return 0


## Rebuilds the list for this tick: `wish_pad[i]` is the pad ship `wish_ship[i]` waits for this tick (0 = none), for
## the first `n` entries in ascending ship slot. Existing entries that still wait for the same pad keep their place;
## the others drop; new waiters are appended while their pad has room.
func update(wish_ship: PackedInt32Array, wish_pad: PackedInt32Array, n: int) -> void:
	_pass += 1
	var _a: int = _keep_pad.resize(0)
	var _b: int = _keep_ship.resize(0)
	for i: int in n:                                     # O(n + queue) with per-slot marks, no searches
		var ws: int = wish_ship[i] & EntityId.SLOT_MASK
		_want[ws] = wish_pad[i]
		_want_mark[ws] = _pass
	for k: int in q_ship.size():                         # still waiting for the same pad: keeps its place
		var qs: int = q_ship[k] & EntityId.SLOT_MASK
		if _want_mark[qs] == _pass and _want[qs] == q_pad[k]:
			_keep(qs, q_ship[k], q_pad[k])
	for i: int in n:                                     # new waiters, while their pad has room
		var p: int = wish_pad[i]
		var ps: int = p & EntityId.SLOT_MASK
		if p != 0 and _kept_mark[wish_ship[i] & EntityId.SLOT_MASK] != _pass and (_cnt_mark[ps] != _pass or _cnt[ps] < PER_PAD):
			_keep(wish_ship[i] & EntityId.SLOT_MASK, wish_ship[i], p)
	var tp: PackedInt32Array = q_pad                     # swap the buffers: no copy, no allocation once both have grown
	var ts: PackedInt32Array = q_ship
	q_pad = _keep_pad
	q_ship = _keep_ship
	_keep_pad = tp
	_keep_ship = ts


func _keep(ship_slot: int, ship: int, pad: int) -> void:
	_kept_mark[ship_slot] = _pass
	var ps: int = pad & EntityId.SLOT_MASK
	_cnt[ps] = _cnt[ps] + 1 if _cnt_mark[ps] == _pass else 1
	_cnt_mark[ps] = _pass
	var _c: bool = _keep_pad.push_back(pad)
	var _d: bool = _keep_ship.push_back(ship)


## Drops `ship` (it docked or died).
func remove(ship: int) -> void:
	var k: int = q_ship.find(ship)
	if k >= 0:
		q_ship.remove_at(k)
		q_pad.remove_at(k)


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE) or q_pad.size() != q_ship.size():
		return false
	for k: int in q_pad.size():
		var main: bool = EntityId.slot(q_pad[k]) < InputSlots.ENTITY_SLOTS and EntityId.slot(q_ship[k]) < InputSlots.ENTITY_SLOTS
		if q_pad[k] == 0 or q_ship[k] == 0 or not main or count(q_pad[k]) > PER_PAD or q_ship.count(q_ship[k]) != 1:
			return false
	return true
