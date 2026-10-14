class_name DamageSink extends RefCounted
## The one place hit points change (02 s4.3, GD-08): subtracts damage, stamps `last_damage_tick` / `attacker`, flags
## DIRTY_VITALS, emits HIT with the applied value and hands a zero-HP entity to the deferred death list (03 s4.1 rule
## 6). Invulnerable structures take nothing. Idempotent on an entity already at 0 HP, so two blasts in one tick never
## double-count a kill. Lane-internal.

var _store: EntityStore
var _events: SimEvents
var _applier: CommandApplier
var _defs: WorldDefs


func _init(store: EntityStore, events: SimEvents, applier: CommandApplier, defs: WorldDefs) -> void:
	_store = store
	_events = events
	_applier = applier
	_defs = defs


## True while `s` is alive and not already destroyed this tick.
func standing(s: int) -> bool:
	return (_store.flags[s] & EntityStore.F_ALIVE) != 0 and _store.hp[s] > 0.0


## Subtracts `amount` from slot `s`; false when nothing was applied (dead, invulnerable, amount <= 0).
func damage(s: int, amount: float, attacker: int, tick: int) -> bool:
	if amount <= 0.0 or not standing(s) or _invulnerable(s):
		return false
	_stamp(s, attacker, tick)
	var left: float = _store.hp[s] - amount
	var _e: SimEvent = _events.emit(SimEvent.Kind.HIT, _store.id_of(s), attacker, _store.pos[s], amount, _store.team[s])
	if left <= 0.0:
		_store.hp[s] = 0.0
		_applier.kill(s)
	else:
		_store.hp[s] = left
	return true


## Outright destruction (bomb kill radius, ramming): HP to 0, death at the end of step 9; no HIT event.
func destroy(s: int, attacker: int, tick: int) -> bool:
	if not standing(s) or _invulnerable(s):
		return false
	_stamp(s, attacker, tick)
	_store.hp[s] = 0.0
	_applier.kill(s)
	return true


func _stamp(s: int, attacker: int, tick: int) -> void:
	_store.last_damage_tick[s] = tick
	_store.attacker[s] = attacker
	_store.dirty[s] |= EntityStore.DIRTY_VITALS


func _invulnerable(s: int) -> bool:
	if _store.kind[s] != EntityStore.K_STRUCTURE:
		return false
	var sd: StructureDef = _defs.base.structure(_store.def_id[s])
	return sd != null and sd.invulnerable
