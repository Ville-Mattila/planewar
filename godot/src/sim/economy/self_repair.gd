class_name SelfRepair extends RefCounted
## Structure self-repair (02 s6.3, GD-16): a finished, supplied structure that has taken no damage for
## `economy.self_repair_delay_s` repairs `max(self_repair_min_hp_s, self_repair_frac_per_s * hp)` HP per second and pays `repair_ore_per_hp` Ore per HP
## (the ship-repair idiom of 02 s2.3: each second charges `ceil(missing * k) - ceil(missing_after * k)`, so a whole repair totals one ceil); it pauses while the team cannot pay. Whole sim seconds
## only (tick % tick_hz == 0), so there is no accumulator and nothing to save (S4): the result is a function of the store.
## Runs in step 10 after `Economy.step`. Healing writes `hp` directly; damage still goes only through `DamageSink`.

## Per entity slot, 1 = outside the Pylon supply network. Derived and rewritten by GD-18 each tick (not state); empty or
## 0 = supplied, so until GD-18 every finished structure counts as supplied.
var unsupplied: PackedByteArray = PackedByteArray()

var _store: EntityStore
var _defs: WorldDefs
var _economy: Economy
var _hz: int
var _delay_ticks: int = 0
var _ore_per_hp: float = 0.0
var _min_rate: float = 0.0
var _frac: float = 0.0


func _init(store: EntityStore, defs: WorldDefs, economy: Economy, hz: int) -> void:
	_store = store
	_defs = defs
	_economy = economy
	_hz = hz
	var ec: EconomyDef = defs.economy if defs.economy != null else EconomyDef.new()
	_delay_ticks = ceili(ec.self_repair_delay_s * float(hz))
	_ore_per_hp = ec.repair_ore_per_hp
	_min_rate = ec.self_repair_min_hp_s
	_frac = ec.self_repair_frac_per_s


## HP per second a structure of `max_hp` repairs.
func rate_hp_s(max_hp: float) -> float:
	return maxf(_min_rate, _frac * max_hp)


## Step 10: on whole sim seconds, repair every eligible structure in slot order (deterministic).
func step(tick: int) -> void:
	if _hz <= 0 or tick % _hz != 0:
		return
	for s: int in _store.structures:
		if (_store.flags[s] & EntityStore.F_BUILDING) != 0 or _store.hp[s] <= 0.0:
			continue
		if tick - _store.last_damage_tick[s] < _delay_ticks or (s < unsupplied.size() and unsupplied[s] != 0):
			continue
		var top: float = _defs.hp_max(_store.owner[s], _store.def_id[s])
		var missing: float = top - _store.hp[s]
		if missing <= 0.0:
			continue
		var heal: float = minf(rate_hp_s(top), missing)
		var cost: int = ceili(missing * _ore_per_hp) - ceili((missing - heal) * _ore_per_hp)   # one ceil over the whole repair
		if _economy.try_spend(_store.team[s], cost, 0):
			_store.hp[s] += heal
