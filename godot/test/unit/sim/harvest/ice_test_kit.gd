class_name IceTestKit extends RefCounted
## Fixtures for the GD-14 tests (sim/harvest/MODULE.md I1-I8): the HarvestTestKit world (flat datum, players 0 and 1 on
## teams 0 and 1, no start kit), a Cold Trap node and an Ice Extractor on it placed by metres of arc along +Y from +X,
## Haulers hovering `alt` metres above the datum, and the team Ice pool.

const K: GDScript = preload("res://test/unit/sim/harvest/harvest_test_kit.gd")
const DT: float = 1.0 / 30.0
const HOVER_M: float = 20.0    ## a Hauler's altitude: inside `radius + salvage_deliver_m` of the structure below it


static func world() -> SimWorld:
	return K.world()


## A Cold Trap of `capacity` Ice at `east`; returns its index.
static func node(w: SimWorld, east: float, capacity: int = 2000, rate: float = 0.8, radius: float = 100.0) -> int:
	return w.economy().ice.nodes.add(K.dir_at(east), capacity, rate, radius)


## A finished Ice Extractor of `owner` at `east`.
static func extractor(w: SimWorld, east: float, owner: int = 0) -> int:
	return K.put(w, &"ice_extractor", owner, east)


## A Hauler of `owner` hovering `alt` m above the datum at `east`.
static func hauler(w: SimWorld, east: float, owner: int = 0, alt: float = HOVER_M) -> int:
	var p: Vector3 = Vector3(K.R, east, 0.0).normalized() * (K.R + alt)
	var s: int = w._applier.spawn(WorldTestKit.def_id(&"hauler"), owner, w._players.team[owner], p, Vector3.ZERO,
			Vector3(0.0, 1.0, 0.0), w.tick())
	assert(s > 0)
	return s


## Runs the Ice pass alone `n` times (the world does not tick, so hovering ships do not fall).
static func pass_n(w: SimWorld, n: int) -> void:
	var ice: IceExtract = w.economy().ice
	for _i: int in n:
		ice.step(DT)


static func ice(w: SimWorld, team: int = 0) -> int:
	return w.economy().economy.stockpile(team).y


## Sets the team Ice pool to `amount` (clamped by the cap) by crediting or spending the difference.
static func set_pool(w: SimWorld, amount: int, team: int = 0) -> void:
	var now: int = ice(w, team)
	if amount > now:
		w.economy().economy.credit(team, 0, amount - now)
	elif amount < now:
		var _ok: bool = w.economy().economy.try_spend(team, 0, now - amount)
