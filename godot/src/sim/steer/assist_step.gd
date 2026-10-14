class_name AssistStep extends RefCounted
## Tick-order step 4, assist substitution (R0 B.5, C2-04): the server side of `Assist`, called once per tick by
## `SimWorld` (one call per step, A-73). Static and stateless (S8): the world's arrays, the parameter table and the
## two scratch objects are arguments. For each player slot whose possessed entity is under LINK_BRIDGE (05 C10, C13;
## AI-08): a ship with a `BridgeParams` entry that is not DOCKED / LANDED flies `Assist.link_bridge`, a ground unit
## gets `Assist.link_bridge_ground`; structures and ships without an entry keep the decayed input of step 2. At most
## one entity per player slot (<= 8 per tick), no allocation. `Assist.auto_dock` (AI-10) joins here.


static func run(store: EntityStore, players: PlayerTable, inputs: InputSlots, terrain: Terrain,
		bridge: Array[BridgeParams], probe: ProbeResult, scratch: PilotInput) -> void:
	for p: int in PlayerTable.SLOTS:
		var id: int = players.possessed[p]
		if id == 0 or not store.alive(id):
			continue
		var s: int = EntityId.slot(id)
		if s >= InputSlots.ENTITY_SLOTS or store.overlay[s] != ControlMachine.Overlay.LINK_BRIDGE:
			continue
		if store.kind[s] == EntityStore.K_GROUND:
			Assist.link_bridge_ground(scratch)
			inputs.set_entity(s, scratch)
			continue
		var d: int = store.def_id[s] - DefRanges.SHIP_BASE
		var parked: bool = (store.flags[s] & (EntityStore.F_DOCKED | EntityStore.F_LANDED)) != 0
		if store.kind[s] != EntityStore.K_SHIP or parked or d < 0 or d >= bridge.size() or bridge[d] == null:
			continue
		var f: Vector3 = store.fwd[s]
		var u: Vector3 = store.up[s]
		Assist.link_bridge(Basis(f.cross(u), u, -f), store.pos[s], store.vel[s], terrain, bridge[d], probe, scratch)
		inputs.set_entity(s, scratch)
