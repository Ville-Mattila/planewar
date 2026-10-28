class_name LandingHudData extends RefCounted
## Plain data of the landing guide, service panel and status cluster for one ship, read only through SimView
## (UX-18). The pad normal is the radial direction at the pad (pads sit on the sphere, 03 s6.4).

var ship: int = 0
var pad: int = -1                   ## nearest friendly pad id, -1 none
var pad_dist_m: float = -1.0
var pad_radius_m: float = 10.0
var agl_m: float = 0.0
var v_vert: float = 0.0
var v_horiz: float = 0.0
var nose_deg: float = 0.0
var phase: LandingMath.Phase = LandingMath.Phase.APPROACH
var visible: bool = false
var pad_occupied: bool = false      ## the nearest pad holds another ship: grey it out, point to the next free one
var drift: Vector2 = Vector2.ZERO   ## drift arrow in du
var docked: bool = false
var service: Vector3 = Vector3.ZERO ## fuel, ammo, repair 0..1
var waiting: int = 0                ## 0 none, 1 Ice, 2 Ore (from the WAITING_FOR_* alerts; the caller sets it)
var fuel01: float = 1.0
var ammo: int = 0
var bombs: int = 0
var rockets: int = 0
var flip_cd01: float = 0.0
var boost: int = 0


## `agl_m` comes from the caller (terrain height under the ship); `pad_radius_m` from the pad's def.
static func from_view(v: SimView, id: int, agl: float, radius_m: float) -> LandingHudData:
	var d: LandingHudData = LandingHudData.new()
	d.ship = id
	d.agl_m = agl
	d.pad_radius_m = radius_m
	d.fuel01 = v.fuel01(id)
	d.ammo = v.ammo(id)
	d.bombs = v.bombs(id)
	d.rockets = v.rockets(id)
	d.flip_cd01 = v.flip_cooldown01(id)
	d.boost = v.boost_state(id)
	d.docked = v.dock_state(id) == 2
	d.service = v.service_progress(id)
	var pad_id: int = v.nearest_friendly_pad(id)
	if pad_id <= 0 or not v.alive(pad_id):
		d.visible = d.docked
		return d
	d.pad = pad_id
	var pad_pos: Vector3 = v.pos(pad_id)
	var up: Vector3 = pad_pos.normalized()
	var p: Vector3 = v.pos(id)
	var vel: Vector3 = v.vel(id)
	d.pad_dist_m = p.distance_to(pad_pos)
	d.v_vert = LandingMath.vert_speed(vel, up)
	d.v_horiz = LandingMath.horiz_speed(vel, up)
	d.nose_deg = LandingMath.nose_from_vertical_deg(-v.basis(id).z, up)
	d.phase = LandingMath.phase(d.pad_dist_m, agl)
	var occ: int = v.pad_occupant(pad_id)
	d.pad_occupied = occ != 0 and occ != id
	var east: Vector3 = Sphere.POLE_AXIS.cross(up)
	east = east.normalized() if east.length_squared() > 0.000001 else Vector3.RIGHT
	d.drift = LandingMath.drift_arrow(LandingMath.pad_offset(p, pad_pos, up, east, up.cross(east)), radius_m)
	d.visible = d.docked or LandingMath.guide_visible(d.pad_dist_m, agl, d.fuel01)
	return d
