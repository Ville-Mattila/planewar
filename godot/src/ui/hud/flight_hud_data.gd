class_name FlightHudData extends RefCounted
## Plain data for the flight instruments; built from a craft state, no live sim needed.

var pitch_rad: float
var bank_rad: float
var heading: float = NAN        ## degrees; NAN = undefined (POLE)
var pole: bool
var home_bearing: float = NAN   ## degrees, NAN = none
var alt_m: float
var agl_m: float
var vs_mps: float
var speed_mps: float
var band: HudMath.Band = HudMath.Band.LOW
var link01: float = 1.0
var link_visible: bool
var link_lost: bool
var dip_rad: float


## pos/vel in world space, b = craft basis, ground_radius from ViewState; home_dir = direction to home or ZERO.
static func from_state(pos: Vector3, vel: Vector3, b: Basis, ground_radius: float, home_dir: Vector3) -> FlightHudData:
	var d: FlightHudData = FlightHudData.new()
	var n: Vector3 = pos.normalized()
	d.pitch_rad = HudMath.pitch(-b.z, n)
	d.bank_rad = CamMath.bank_angle(b, n)
	d.heading = HudMath.heading_deg(-b.z, n)
	d.pole = HudMath.is_pole(n)
	d.alt_m = HudMath.altitude(pos)
	d.agl_m = pos.length() - ground_radius
	d.vs_mps = vel.dot(n)
	d.speed_mps = vel.length()
	d.band = HudMath.band(d.agl_m, d.alt_m)
	d.link01 = HudMath.uplink(d.alt_m)
	d.link_visible = HudMath.uplink_visible(d.alt_m)
	d.link_lost = HudMath.uplink_lost(d.alt_m)
	d.dip_rad = HudMath.limb_dip(d.alt_m)
	if home_dir != Vector3.ZERO:
		d.home_bearing = HudMath.heading_deg(home_dir, n)
	return d
