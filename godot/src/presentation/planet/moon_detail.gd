class_name MoonDetail extends RefCounted
## CPU mirror of the detail constants of `shaders/moon_terrain.gdshader` (07 s3.1): crater layer amplitudes,
## the mean-zero bowl + rim profile and the footprint fade. All static. `test_moon_terrain.gd` parses the shader
## and asserts the constants agree. Visual only: nothing here touches `Terrain.height_at`.

const CELLS_M: PackedFloat32Array = [40.0, 15.0, 6.0]
const AMPLITUDES_M: PackedFloat32Array = [0.6, 0.4, 0.2]
const TOTAL_M: float = 1.2                    ## 07 s3.1: visual displacement is at most 1.2 m
const FOOTPRINT_KEEP: float = 0.5             ## displacement factor inside a footprint (R0 C2-31)
const FOOTPRINT_OUTER: float = 1.5
const FOOTPRINT_MAX_M: float = TOTAL_M * FOOTPRINT_KEEP   ## 0.6 m


## Crater height in units of the layer amplitude at normalised radius t = dist / crater radius (0..1):
## -1 at the centre (bowl), +1/3 at the rim, mean zero over the disc.
static func profile(t: float) -> float:
	if t >= 1.0:
		return 0.0
	var u: float = t * t
	return -3.0 * (1.0 - u) * (1.0 / 3.0 - u)


## Displacement multiplier at `dist` from a footprint centre of radius `radius` (mirrors footprint_scale).
static func footprint_scale(dist: float, radius: float) -> float:
	return lerpf(FOOTPRINT_KEEP, 1.0, smoothstep(radius, radius * FOOTPRINT_OUTER, dist))


## Largest displacement magnitude (m) at `dist` from a footprint of `radius`.
static func max_displacement(dist: float, radius: float) -> float:
	return TOTAL_M * footprint_scale(dist, radius)


## Displacement multiplier from the camera distance: 1 up to half the detail range, 0 at the range (0 = off).
static func range_fade(dist: float, range_m: float) -> float:
	if range_m <= 0.0:
		return 0.0
	return 1.0 - smoothstep(0.5 * range_m, range_m, dist)
