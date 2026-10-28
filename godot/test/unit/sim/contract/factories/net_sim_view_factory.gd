class_name NetSimViewFactory extends SimViewFactory
## NetSimView (NET-17) under the shared contract: the scene's world is served by NetViewRig (a test-side server) to a
## ClientSession of player slot 0 / team 0 over LocalTransport (HELLO, WELCOME, LOADED, ENTITY_META, POSSESSED,
## TEAM_STATE, the FULL SNAPSHOT with the pilot block), and the client's view is sampled at the world's tick. The
## world is first moved onto the wire lattice (NetViewRig.snap_world: pos / vel / orientation round trips) so decoded
## values compare exactly; the quantisation error itself is net's N7 (test_codec_roundtrip.gd).
## exempt(): each accessor below fails for a reason 04 s5.6 / s3.7 gives (a field the client does not receive returns
## the default with `unknown`), or for a contract question listed in net/client/MODULE.md Open items. The replicable
## part of every exempt clause is asserted in test/unit/net/test_net_sim_view.gd and test/net/test_client_session.gd.

const U8_QUANTUM: float = 1.0 / 255.0
const U8_FIELDS: PackedStringArray = ["hp01", "flip_cooldown01", "supply01", "production_progress01"]
const _EXEMPT: PackedStringArray = [
	# The scene's wreck is not visible to team 0 (visible_to(0, wreck) is false in the clause itself), so a team-0
	# client never receives it (04 s4.1 interest = team vision; net/interest I1); the rocket is a projectile entity
	# with no roster index until NET-58's projectile block (R0 B.22 A-112). A received wreck is covered by
	# test_net_sim_view.gd::test_a_received_wreck (radius = the hull's def radius with unknown set, A-114).
	"alive", "radius", "def_kind", "wrecks", "ids_in_cell", "projectiles_near", "read_poses",
	# No wire source in the 04 s3.7 replication map: SimView default + unknown (04 s5.6).
	"overlay", "cargo", "cargo_kind", "link",
	# TEAM_DETAIL sources (04 s3.7 rows supply01, pads, orders, factories): NET-39.
	"supply01", "pad_occupant", "order_head", "order_issuer", "auto_replenish_target",
	# GD-38 / GD-41: inherit -1.0 until a codec carries dome charge / wreck ore (04 s5.6 "return the def default").
	"shield01", "wreck_ore",
	# Other teams' vision and TEAM_STATE are not sent to this client (04 s3.7 "Unknown when: other teams").
	"visible_enemy_ships", "stockpile", "unit_count",
	# NET-39 (R0 B.22 A-111: net may name the types now; the TEAM_DETAIL / TEAM_STATE player rows are NET-39's).
	"team_state", "player_state",
	# GD-15 tightened these from defaults to Docking values. service_progress: the pilot block carries it for the own
	# possessed unit only (04 s3.7), and the scene's docked `c` is not possessed; pad_queue: TEAM_DETAIL pads (NET-39);
	# landing_grade_last: the LANDING event is not routed into the client view yet (net_unknown.gd).
	"service_progress", "pad_queue", "landing_grade_last",
]


func label() -> String:
	return "NetSimView"


func make(scene: SimViewScene) -> SimView:
	var rig: NetViewRig = NetViewRig.new(scene.world, scene.content)
	if not rig.snap_world():
		return null                                # no fixed point on the wire lattice: the contract reports no view
	var cs: ClientSession = rig.add_client(0, 0)
	rig.pump(4)
	rig.send_tick(scene.world.tick())
	rig.pump(3)
	var v: NetSimView = cs.view()
	v.sample(float(scene.world.tick()))
	return v


## One wire quantum for the fields 04 s3.3 carries as a u8 fraction (R0 B.22 A-113): hp (`round(hp01 * 255)`), the pilot
## block's flip_cooldown01, and TEAM_DETAIL's supply01 / progress01 bytes; EPS (exact) for everything else.
func tolerance(accessor: StringName) -> float:
	return U8_QUANTUM if U8_FIELDS.has(String(accessor)) else SimViewContract.EPS


func exempt() -> PackedStringArray:
	return _EXEMPT
