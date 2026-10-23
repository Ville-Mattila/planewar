class_name KnownBlipFixture extends RefCounted
## The NET-56 fixture shared by test_known_blip_presentation.gd (test_dying_blip_rests_300_ticks_at_blip_pos) and
## NET-17's NetSimView contract test (test_net_sim_view.gd): a DYING entry with zero velocity, FULL at tick 10, then a
## C-BLIP at tick 20, so it is a known blip whose bucket must be shown, never dead-reckoned, from tick 20 on.

const G: float = 6.0
const DT: float = 1.0 / 30.0
const SLOT: int = 4
const FULL_TICK: int = 10
const BLIP_TICK: int = 20
const BLIP: int = 0x0A1B2C
const RESTS: PackedInt32Array = [0, 1, 30, 111, 300]   ## ticks after BLIP_TICK the bucket is checked at


static func pos_q() -> int:
	return Codec.quantize_pos(Sphere.from_lat_lon(0.2, 0.3, Sphere.PLANET_RADIUS + 300.0))


## Applies the fixture's two records to `f` (FULL DYING at FULL_TICK, C-BLIP at BLIP_TICK).
static func apply(f: BaselineFrame) -> void:
	f.set_full_cached(SLOT, FULL_TICK, pos_q(), 0, 0, DeadReckon.pack_fine(0, 0, 0), 255, Codec.FLAG_DYING, -1)
	f.set_blip(SLOT, BLIP_TICK, BLIP)


## The bucket levels the known blip must show.
static func bucket(f: BaselineFrame) -> Vector3i:
	return Vector3i(Codec.pos_e(f.pos[SLOT]), Codec.pos_n(f.pos[SLOT]), Codec.pos_u(f.pos[SLOT]))
