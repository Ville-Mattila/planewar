class_name SimViewScene extends RefCounted
## The scripted scene every SimView implementation is checked on (TEST-02; 01 s9.4, R0 C2-05, B.5). `build()` makes a
## SimWorld whose entities carry distinctive non-default values in every field a SimView accessor reads, so an
## accessor that returns its neutral default, the wrong slot or a neighbour's value is caught by SimViewContract.
## A factory (SimViewFactory) turns this world into the SimView under test; the expected values below do not
## depend on any view.

const TICK_HZ: float = 30.0             ## 01 s8: 30 Hz sim tick
const AMMO: int = 37
const BOMBS: int = 3
const ROCKETS: int = 2
const CONTROL: int = 5
const AI_TAG: int = 4
const OVERLAY: int = 2              ## ControlMachine.Overlay.RECOVER_CEILING (sim/MODULE.md)
const CARGO: float = 12.5
const CARGO_KIND: int = 1
const HP01: float = 0.5
const FUEL01: float = 0.25
const FLIP_CD01: float = 0.5            ## flip_time = -0.5 * flip_cooldown_s
const MOVE_POINT: Vector3 = Vector3(100.0, 200.0, 300.0)
const EXTRA_STEPS: int = 3

var world: SimWorld
var a: int = 0              ## player 0, team 0 Dart: the subject of most scalar accessors; possessed by slot 0
var b: int = 0              ## player 1, team 1 Dart, 250 m from `a`; visible to team 0
var c: int = 0              ## player 0 Dart docked on `pad`
var pad: int = 0
var core: int = 0
var yard: int = 0
var wreck: int = 0
var rocket: int = 0         ## team 1 rocket aimed at `a`
var dead: int = 0           ## stale generation of `a`
var content: ContentSet


static func build() -> SimViewScene:
	var s: SimViewScene = SimViewScene.new()
	var w: SimWorld = WorldTestKit.world()
	s.world = w
	s.content = WorldTestKit.content()
	s.core = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 300.0))
	s.pad = WorldTestKit.spawn(w, &"pad", 0, 0, WorldTestKit.at(0.0, 200.0))
	s.yard = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 2000.0))
	s.a = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0), Vector3(0, 40, 0))
	s.b = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(500.0, 250.0), Vector3(0, 40, 0))
	s.c = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(20.0, 200.0))
	var order: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, MOVE_POINT)
	var res: CommandResult = w.apply_command(Command.order(0, PackedInt32Array([s.a]), order))
	assert(res.code == CommandResult.Code.ACCEPTED)
	# GD-17: player 0 wants 2 Harvesters (no Vehicle Bay in the scene, so nothing is queued and production_queue stays empty)
	var roster: PackedInt32Array = PackedInt32Array([WorldTestKit.def_id(&"harvester"), 2])
	assert(w.apply_command(Command.toggle_auto_replenish(0, s.yard, true, roster)).code == CommandResult.Code.ACCEPTED)
	s.wreck = s._make_wreck(WorldTestKit.at(100.0, 500.0))
	s.rocket = WorldTestKit.projectile(w, &"rocket", WorldTestKit.at(300.0), Vector3(0, 10, 0), 1, 5.0)
	for _i: int in EXTRA_STEPS:
		w.step()
	s._script_state()
	s.dead = EntityId.make(EntityId.slot(s.a), 99)
	return s


func ship_def() -> ShipDef:
	return content.ships[WorldTestKit.def_id(&"dart")]


func _script_state() -> void:
	var st: EntityStore = world.store()
	var sa: int = EntityId.slot(a)
	var dart: ShipDef = ship_def()
	st.hp[sa] = st.hp[sa] * HP01          # spawned at full hp
	st.fuel[sa] = dart.fuel_s * FUEL01
	st.ammo[sa] = AMMO
	st.bombs[sa] = BOMBS
	st.rockets[sa] = ROCKETS
	st.control_state[sa] = CONTROL
	st.ai_tag[sa] = AI_TAG
	st.overlay[sa] = OVERLAY
	st.cargo[sa] = CARGO
	st.cargo_kind[sa] = CARGO_KIND
	st.possessor[sa] = 0
	st.boost_time[sa] = -0.1                 # neither boosting nor ready: cooling down (2)
	st.flip_time[sa] = -FLIP_CD01 * dart.flip_cooldown_s
	st.visible_mask[EntityId.slot(b)] = 1    # team 0 sees b
	var sc: int = EntityId.slot(c)
	st.flags[sc] |= EntityStore.F_DOCKED
	st.link[sc] = pad
	var pr: ProjectileStore = world.projectiles()
	pr.kind[pr.index_of(rocket)] = ProjectileStore.ROCKET
	pr.target[pr.index_of(rocket)] = a
	world.spatial.rebuild()


## A wreck written straight into the store (Combat's death path is GD-36): a spent Dart hull.
func _make_wreck(p: Vector3) -> int:
	var st: EntityStore = world.store()
	var id: int = st.alloc(EntityStore.K_WRECK, world.tick())
	var sw: int = EntityId.slot(id)
	st.def_id[sw] = WorldTestKit.def_id(&"dart")
	st.pos[sw] = p
	st.fwd[sw] = Vector3(0, 1, 0)
	st.up[sw] = Vector3(1, 0, 0)
	st.radius[sw] = 5.0
	st.owner[sw] = EntityStore.NONE_U8
	st.team[sw] = EntityStore.NONE_U8
	st.possessor[sw] = EntityStore.NONE_U8
	st.order_kind[sw] = EntityStore.NONE_U8
	return id
