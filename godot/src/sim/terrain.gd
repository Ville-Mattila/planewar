class_name Terrain extends RefCounted
## Read-only terrain sampler shared by sim and presentation (03 s6.2).
## TA-13 owns the baked-face loader (load, biome_at, surface_point, slope_deg_at, SHA check). Until a map is
## loaded the surface is the datum sphere: height 0, normal radial. That is the flat `Terrain` stub
## S-FLIGHT-1 runs on (03 s14.6).


## Metres above the datum at direction `dir` (need not be normalised).
func height_at(_dir: Vector3) -> float:
	return 0.0


## Unit surface normal at direction `dir`.
func normal_at(dir: Vector3) -> Vector3:
	return dir.normalized()
