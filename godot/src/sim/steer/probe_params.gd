class_name ProbeParams extends RefCounted
## Parameter struct of TerrainProbe (05 s5.3): one per autopilot profile, filled from the `autopilots` def
## (`min_clearance_m`, `clearance_per_mps`, `probe_times_s`) plus rules.gravity. Read-only to the probe, so the
## same instance is shared by every ship of a profile. No numeric defaults live here (ADR-09): build it with
## `make` from def values (Dart anchors: 25, 0.25, [0.5 1 1.5 2 3 4], 6, 0.6, 0.5).

var min_clearance_m: float = 0.0       ## autopilots.min_clearance_m
var clearance_per_mps: float = 0.0     ## autopilots.clearance_per_mps
var probe_times_s: PackedFloat32Array = PackedFloat32Array()   ## autopilots.probe_times_s, ascending, > 0
var gravity: float = 0.0               ## rules.gravity, m/s^2 along local down
var lift_max_frac: float = 0.0         ## cap of the lift as a fraction of speed (05 s5.3: 0.6)
var lift_min_time_s: float = 0.0       ## floor of the sample time in the lift division (05 s5.3: 0.5)


static func make(min_clearance: float, per_mps: float, times: PackedFloat32Array, g: float, lift_frac: float,
		lift_min_time: float) -> ProbeParams:
	var p: ProbeParams = ProbeParams.new()
	p.min_clearance_m = min_clearance
	p.clearance_per_mps = per_mps
	p.probe_times_s = times
	p.gravity = g
	p.lift_max_frac = lift_frac
	p.lift_min_time_s = lift_min_time
	return p


## Required clearance `h_req = min_clearance_m + clearance_per_mps * speed` (Dart at 110 m/s: 52.5 m).
func required_clearance(speed: float) -> float:
	return min_clearance_m + clearance_per_mps * speed
