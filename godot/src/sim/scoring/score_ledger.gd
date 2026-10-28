class_name ScoreLedger extends RefCounted
## The per-player score and result counters of one match (02 s17.1; 03 s3.2 `scoring` side table, player half): the
## Pilot and Commander scores and every counter of the MATCH_END per-player row. Plain packed arrays indexed by player
## slot; whole points are kept in `pilot` / `commander`, the fraction below one point in `_frac` (index slot * 2 + side)
## so many small awards (1 point per 10 damage) add up exactly. Written by `ScoreKeeper` only; part of S4.

const SLOTS: int = PlayerTable.SLOTS
const CLASS_COUNT: int = 5   ## pilot_time_s classes in the 04 s2.3 order: dart, lancer, bomber, scout, hauler
const CLASS_IDS: PackedStringArray = ["dart", "lancer", "bomber", "scout", "hauler"]
const _PER_SLOT: PackedStringArray = ["pilot", "commander", "kills", "deaths", "structures_built", "structures_destroyed",
	"manual_landings", "sorties", "ore_mined", "ore_spent", "ice_delivered"]
const _STATE: PackedStringArray = ["pilot", "commander", "kills", "deaths", "structures_built", "structures_destroyed",
	"manual_landings", "sorties", "ore_mined", "ore_spent", "ice_delivered", "pilot_ticks", "_frac"]

var pilot: PackedInt32Array = PackedInt32Array()                 ## score earned while possessing
var commander: PackedInt32Array = PackedInt32Array()             ## everything else
var kills: PackedInt32Array = PackedInt32Array()                 ## enemy units destroyed by the player's entities
var deaths: PackedInt32Array = PackedInt32Array()                ## the player's units destroyed
var structures_built: PackedInt32Array = PackedInt32Array()
var structures_destroyed: PackedInt32Array = PackedInt32Array()  ## enemy finished structures destroyed by the player's entities
var manual_landings: PackedInt32Array = PackedInt32Array()       ## graded manual landings (HARD or better)
var sorties: PackedInt32Array = PackedInt32Array()               ## possessions of a ship
var ore_mined: PackedInt32Array = PackedInt32Array()
var ore_spent: PackedInt32Array = PackedInt32Array()             ## net of refunds (the `Build.spent_ore` ledger)
var ice_delivered: PackedInt32Array = PackedInt32Array()
var pilot_ticks: PackedInt32Array = PackedInt32Array()           ## [slot * CLASS_COUNT + class] ticks possessed
var _frac: PackedFloat64Array = PackedFloat64Array()


func _init() -> void:
	var e: int = pilot.resize(SLOTS) | commander.resize(SLOTS) | kills.resize(SLOTS) | deaths.resize(SLOTS)
	e |= structures_built.resize(SLOTS) | structures_destroyed.resize(SLOTS) | manual_landings.resize(SLOTS)
	e |= sorties.resize(SLOTS) | ore_mined.resize(SLOTS) | ore_spent.resize(SLOTS) | ice_delivered.resize(SLOTS)
	e |= pilot_ticks.resize(SLOTS * CLASS_COUNT) | _frac.resize(SLOTS * 2)
	assert(e == OK)
	for a: PackedInt32Array in [pilot, commander, kills, deaths, structures_built, structures_destroyed, manual_landings,
			sorties, ore_mined, ore_spent, ice_delivered, pilot_ticks]:
		a.fill(0)
	_frac.fill(0.0)


## Adds `points` (>= 0, fractions allowed) to the Pilot or Commander side of `slot`; the sub-point remainder carries.
func credit(slot: int, pilot_side: bool, points: float) -> void:
	if slot < 0 or slot >= SLOTS or points <= 0.0:
		return
	var f: int = slot * 2 + (0 if pilot_side else 1)
	var sum: float = _frac[f] + points
	var whole: int = floori(sum)
	_frac[f] = sum - float(whole)
	if pilot_side:
		pilot[slot] += whole
	else:
		commander[slot] += whole


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and StateIO.sizes_ok(self, _PER_SLOT, SLOTS) \
			and StateIO.sizes_ok(self, ["pilot_ticks"], SLOTS * CLASS_COUNT) and StateIO.sizes_ok(self, ["_frac"], SLOTS * 2)
