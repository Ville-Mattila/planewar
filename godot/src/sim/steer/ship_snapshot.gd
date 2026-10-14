class_name ShipSnapshot extends RefCounted
## Input struct of LandingController (05 s5.5): the landing ship as the caller reads it (SimView in sim_ai, the
## possessed ship's predicted state in Assist). One reused scratch per caller, overwritten before every call.

var b: Basis = Basis()                 ## SimView.basis: x right, y up, z = -forward (thrust axis = -z)
var p: Vector3 = Vector3.ZERO          ## world position (m), planet centre at the origin
var v: Vector3 = Vector3.ZERO          ## world velocity (m/s)
var a_thrust: float = 0.0              ## ShipDef.a_thrust times Kinematics.ceiling_efficiency at the ship's altitude
var eff_fade_start: float = 0.0        ## flight_common.eff_fade_start (thrust efficiency fade, 03 s5.3)
var bounding_radius: float = 0.0       ## ShipDef.bounding_radius (the landing rule's height reference)
var v_cruise: float = 0.0              ## ShipDef.v_cruise (L1, L3, the L2 speed schedule, thrust efficiency)
var ground_h: float = 0.0              ## terrain height under the ship (m above the datum), refreshed by the caller
var lift_mps: float = 0.0              ## TerrainProbe lift of the last think (velocity phases), drop removed
var tti_s: float = INF                 ## TerrainProbe time to impact of the last think
