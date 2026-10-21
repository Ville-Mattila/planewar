class_name ThreatMap extends RefCounted
## One observer's threat map on the 384 interest cells (05 s7.4; AI-22), rebuilt from its `Perception` at each update
## (the AI driver's team intel at 1 Hz per team; a Commander bot on its perception slice). Channels, channel-major
## `ch[channel * CELLS + cell]`: AIR_DECK, AIR_LOW, AIR_HIGH, GROUND (enemy DPS reaching that band; ThreatParams
## profiles and rings), ENEMY_VALUE, OWN_VALUE (Ore value of the assets in the cell), OWN_DEFENCE (own AA + AG DPS,
## spread like the enemy's); `last_seen[cell]` = tick the cell was last inside the observer's sensors (own cell + the
## sensor class ring). Only usable contacts count (the reaction delay); a ghost's contribution decays with half-life
## `ghost_half_life_s` after its last sight. Per update: contacts and own assets are binned per (cell, profile), then
## each bin is spread once over its ring (cost O(known + bins x ring), independent of how many units share a bin).
## Not S4 state except `last_seen` and the update tick: `deserialize` + one `update` on the restored perception
## rebuilds identical channels.

const FORMAT: int = 1
const CELLS: int = ThreatParams.CELLS
const AIR_DECK: int = ThreatParams.AIR_DECK
const AIR_LOW: int = ThreatParams.AIR_LOW
const AIR_HIGH: int = ThreatParams.AIR_HIGH
const GROUND: int = ThreatParams.GROUND
const ENEMY_VALUE: int = 4
const OWN_VALUE: int = 5
const OWN_DEFENCE: int = 6
const CHANNELS: int = 7

var tables: ThreatParams = null
var ch: PackedFloat32Array = PackedFloat32Array()        ## [channel * CELLS + cell]
var last_seen: PackedInt32Array = PackedInt32Array()     ## [cell] tick, -1 = never
var updated: int = -1                                    ## tick of the last update
var stats_bins: int = 0                                  ## bins spread by the last update (work counter)
var stats_cells: int = 0                                 ## ring cells written by the last update (work counter)

var _bin_e: PackedFloat32Array = PackedFloat32Array()    ## [cell * NP + profile] enemy weight sum
var _bin_o: PackedFloat32Array = PackedFloat32Array()    ## own weight sum
var _touch_e: PackedInt32Array = PackedInt32Array()
var _touch_o: PackedInt32Array = PackedInt32Array()
var _sens: PackedInt32Array = PackedInt32Array()         ## [cell * NS + class] update stamp of the sensor ring
var _acc: PackedFloat32Array = PackedFloat32Array()      ## [(cell * NC + range class) * BANDS + band] folded DPS
var _acc_o: PackedFloat32Array = PackedFloat32Array()    ## [cell * NC + range class] folded own defence
var _touch_c: PackedInt32Array = PackedInt32Array()
var _touch_oc: PackedInt32Array = PackedInt32Array()
var _np: int = 1
var _nc: int = 1
var _ns: int = 1


func _init(t: ThreatParams) -> void:
	tables = t
	_np = t.profiles
	_nc = t.classes
	_ns = t.ring_count() - t.classes + 1
	var e: int = ch.resize(CHANNELS * CELLS) | last_seen.resize(CELLS) | _bin_e.resize(CELLS * _np)
	e |= _bin_o.resize(CELLS * _np) | _touch_e.resize(CELLS * _np) | _touch_o.resize(CELLS * _np) | _sens.resize(CELLS * _ns)
	e |= _acc.resize(CELLS * _nc * ThreatParams.BANDS) | _acc_o.resize(CELLS * _nc) | _touch_c.resize(CELLS * _nc)
	e |= _touch_oc.resize(CELLS * _nc)
	assert(e == OK)
	_acc.fill(0.0)
	_acc_o.fill(0.0)
	ch.fill(0.0)
	last_seen.fill(-1)
	_bin_e.fill(0.0)
	_bin_o.fill(0.0)
	_sens.fill(-1)


## Rebuilds the channels from `perception` (its last refresh's digest and its ghosts aged to `tick`; call it on the
## refresh tick). `_v` is unused: the map reads the perception only.
func update(_v: SimView, perception: Perception, tick: int) -> void:
	var c: PackedFloat32Array = ch          # sole owner while writing (no copy-on-write), restored below
	ch = PackedFloat32Array()
	c.fill(0.0)
	updated = tick
	stats_bins = 0
	stats_cells = 0
	var ne: int = _bin_contacts(perception, tick, c)
	var no: int = _bin_own(perception, tick, c)
	var nec: int = _fold_enemy(ne)
	var noc: int = _fold_own(no)
	for k: int in nec:
		_spread_enemy(_touch_c[k], c)
	for k: int in noc:
		_spread_own(_touch_oc[k], c)
	ch = c


## Threat on `band` (AIR_DECK, AIR_LOW, AIR_HIGH, GROUND) in `cell`.
func threat_at(cell: int, band: int) -> float:
	return ch[band * CELLS + cell]


## Sum of `band` threat over the cells the great-circle arc from `from` to `to` crosses, sampled every
## `route_sample_m` (each run of samples in one cell counts that cell once).
func route_risk(from: Vector3, to: Vector3, band: int) -> float:
	var a: Vector3 = from.normalized()
	var b: Vector3 = to.normalized()
	var n: int = maxi(1, ceili(a.angle_to(b) * Sphere.PLANET_RADIUS / tables.route_step_m))
	var sum: float = 0.0
	var prev: int = -1
	for i: int in n + 1:
		var c: int = tables.cell_of(Sphere.slerp_dir(a, b, float(i) / float(n)), prev)
		if c != prev:
			sum += ch[band * CELLS + c]
			prev = c
	return sum


## The own-value cell with the highest enemy pressure / own defence (pressure = the strongest air band + GROUND;
## defence floored at `defence_floor_dps`); -1 when no own-value cell is under any pressure. Ties: lower cell.
func hottest_own_cell() -> int:
	var best: int = -1
	var best_r: float = 0.0
	for c: int in CELLS:
		if ch[OWN_VALUE * CELLS + c] <= 0.0:
			continue
		var r: float = pressure(c) / maxf(ch[OWN_DEFENCE * CELLS + c], tables.defence_floor)
		if r > best_r:
			best_r = r
			best = c
	return best


## Enemy pressure in `cell`: the strongest air band + GROUND.
func pressure(cell: int) -> float:
	return maxf(ch[cell], maxf(ch[CELLS + cell], ch[2 * CELLS + cell])) + ch[GROUND * CELLS + cell]


## S4 bytes: FORMAT, the update tick, `last_seen`.
func serialize() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(FORMAT)
	b.put_32(updated)
	for c: int in CELLS:
		b.put_32(last_seen[c])
	return b.data_array


## Restores `serialize` bytes and clears the channels (the owner re-runs `update`); false on a wrong FORMAT / size.
func deserialize(bytes: PackedByteArray) -> bool:
	ch.fill(0.0)
	last_seen.fill(-1)
	updated = -1
	if bytes.size() != 5 + 4 * CELLS or bytes[0] != FORMAT:
		return false
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	b.seek(1)
	updated = b.get_32()
	for c: int in CELLS:
		last_seen[c] = b.get_32()
	return true


# Enemy value per cell and the enemy bins: the perception's digest of its last refresh (seen, usable contacts at
# weight 1), then its ghosts usable at `tick` at weight exp(-age ln 2 / half-life). Returns the bins touched, in
# digest order then ghost order (both follow `known`, so a restore spreads in the same order).
func _bin_contacts(perc: Perception, tick: int, c: PackedFloat32Array) -> int:
	var t: ThreatParams = tables
	var be: PackedFloat32Array = _bin_e
	var te: PackedInt32Array = _touch_e
	_bin_e = PackedFloat32Array()
	_touch_e = PackedInt32Array()
	var ev: int = ENEMY_VALUE * CELLS
	var n: int = _copy_digest(perc, c, be, te)
	var gh: PackedInt32Array = perc.ghosts
	var kf: PackedInt32Array = perc.k_first
	var kd: PackedInt32Array = perc.k_def
	var kc: PackedInt32Array = perc.k_cell
	var ks: PackedInt32Array = perc.k_seen
	var val: PackedFloat32Array = t.value_by_def
	var prof: PackedByteArray = t.profile_by_def
	var last_first: int = tick - perc.prm.delay_ticks
	var rate: float = t.decay_per_tick
	for i: int in perc.n_ghosts:
		var s: int = gh[i]
		if kf[s] > last_first:
			continue
		var d: int = kd[s]
		var cell: int = kc[s]
		var w: float = exp(-float(tick - ks[s]) * rate)
		c[ev + cell] += val[d] * w
		var p: int = prof[d]
		if p != 0:
			var key: int = cell * _np + p
			if be[key] == 0.0:
				te[n] = key
				n += 1
			be[key] += w
	_bin_e = be
	_touch_e = te
	return n


# The digest's values and bins into the channel / bin arrays; returns the bins touched.
func _copy_digest(perc: Perception, c: PackedFloat32Array, be: PackedFloat32Array, te: PackedInt32Array) -> int:
	var ev: int = ENEMY_VALUE * CELLS
	var fc: PackedInt32Array = perc.fresh_cells
	var fv: PackedFloat32Array = perc.fresh_val
	for k: int in perc.n_fresh_cells:
		c[ev + fc[k]] = fv[fc[k]]
	var fk: PackedInt32Array = perc.fresh_keys
	var fb: PackedFloat32Array = perc.fresh_bin
	for k: int in perc.n_fresh_keys:
		be[fk[k]] = fb[fk[k]]
		te[k] = fk[k]
	return perc.n_fresh_keys


# Own value per cell, the own bins and `last_seen` (each (cell, sensor class) ring once per update).
func _bin_own(perc: Perception, tick: int, c: PackedFloat32Array) -> int:
	var t: ThreatParams = tables
	var od: PackedInt32Array = perc.own_def
	var oc: PackedInt32Array = perc.own_cell
	var val: PackedFloat32Array = t.value_by_def
	var prof: PackedByteArray = t.profile_by_def
	var scl: PackedByteArray = t.sclass_by_def
	var bo: PackedFloat32Array = _bin_o
	var to: PackedInt32Array = _touch_o
	_bin_o = PackedFloat32Array()
	_touch_o = PackedInt32Array()
	var n: int = 0
	var ov: int = OWN_VALUE * CELLS
	for i: int in perc.n_own:
		var d: int = od[i]
		var cell: int = oc[i]
		c[ov + cell] += val[d]
		var k: int = scl[d]
		if k > 0 and _sens[cell * _ns + k] != tick:
			_sens[cell * _ns + k] = tick
			_mark_seen(cell, k, tick)
		var p: int = prof[d]
		if p != 0:
			var key: int = cell * _np + p
			if bo[key] == 0.0:
				to[n] = key
				n += 1
			bo[key] += 1.0
	_bin_o = bo
	_touch_o = to
	return n


# `last_seen` = tick on sensor class k's ring around `cell`.
func _mark_seen(cell: int, k: int, tick: int) -> void:
	var t: ThreatParams = tables
	var base: int = (t.classes - 1 + k) * (CELLS + 1) + cell
	for j: int in range(t.ring_start[base], t.ring_start[base + 1]):
		last_seen[t.ring_cell[j]] = tick


# Folds the touched enemy profile bins into (cell, range class) DPS vectors (bins zeroed); returns the class keys
# touched, in bin order.
func _fold_enemy(ne: int) -> int:
	var t: ThreatParams = tables
	var acc: PackedFloat32Array = _acc
	_acc = PackedFloat32Array()
	var n: int = 0
	for k: int in ne:
		var key: int = _touch_e[k]
		var cell: int = MathX.floori_div(key, _np)
		var p: int = key - cell * _np
		var a: float = _bin_e[key]
		_bin_e[key] = 0.0
		var ck: int = cell * _nc + t.prof_class[p]
		var q: int = ck * ThreatParams.BANDS
		var pq: int = p * ThreatParams.BANDS
		if acc[q] == 0.0 and acc[q + 1] == 0.0 and acc[q + 2] == 0.0 and acc[q + 3] == 0.0:
			_touch_c[n] = ck
			n += 1
		acc[q] += t.prof_dps[pq] * a
		acc[q + 1] += t.prof_dps[pq + 1] * a
		acc[q + 2] += t.prof_dps[pq + 2] * a
		acc[q + 3] += t.prof_dps[pq + 3] * a
	_acc = acc
	return n


# Folds the touched own profile bins into (cell, range class) defence sums (bins zeroed); returns the keys touched.
func _fold_own(no: int) -> int:
	var t: ThreatParams = tables
	var n: int = 0
	for k: int in no:
		var key: int = _touch_o[k]
		var cell: int = MathX.floori_div(key, _np)
		var p: int = key - cell * _np
		var ck: int = cell * _nc + t.prof_class[p]
		if _acc_o[ck] == 0.0:
			_touch_oc[n] = ck
			n += 1
		_acc_o[ck] += t.prof_defence[p] * _bin_o[key]
		_bin_o[key] = 0.0
	return n


# One (cell, range class) DPS vector over the class ring onto the four bands; the vector is zeroed.
func _spread_enemy(ck: int, c: PackedFloat32Array) -> void:
	var t: ThreatParams = tables
	var cell: int = MathX.floori_div(ck, _nc)
	var base: int = (ck - cell * _nc) * (CELLS + 1) + cell
	var q: int = ck * ThreatParams.BANDS
	var d0: float = _acc[q]
	var d1: float = _acc[q + 1]
	var d2: float = _acc[q + 2]
	var d3: float = _acc[q + 3]
	_acc[q] = 0.0
	_acc[q + 1] = 0.0
	_acc[q + 2] = 0.0
	_acc[q + 3] = 0.0
	var rc: PackedInt32Array = t.ring_cell
	var rw: PackedFloat32Array = t.ring_w
	var j0: int = t.ring_start[base]
	var j1: int = t.ring_start[base + 1]
	stats_bins += 1
	stats_cells += j1 - j0
	for j: int in range(j0, j1):
		var h: int = rc[j]
		var w: float = rw[j]
		c[h] += d0 * w
		c[CELLS + h] += d1 * w
		c[2 * CELLS + h] += d2 * w
		c[3 * CELLS + h] += d3 * w


# One (cell, range class) own-defence sum over the class ring onto OWN_DEFENCE; the sum is zeroed.
func _spread_own(ck: int, c: PackedFloat32Array) -> void:
	var t: ThreatParams = tables
	var cell: int = MathX.floori_div(ck, _nc)
	var base: int = (ck - cell * _nc) * (CELLS + 1) + cell
	var dv: float = _acc_o[ck]
	_acc_o[ck] = 0.0
	var rc: PackedInt32Array = t.ring_cell
	var rw: PackedFloat32Array = t.ring_w
	var j0: int = t.ring_start[base]
	var j1: int = t.ring_start[base + 1]
	stats_bins += 1
	stats_cells += j1 - j0
	for j: int in range(j0, j1):
		c[OWN_DEFENCE * CELLS + rc[j]] += dv * rw[j]
