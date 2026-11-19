class_name BookContext extends RefCounted
## What a book condition reads (05 s7.3), filled by the Commander once per think from `SimView` and Perception; reused,
## no allocation after `size_defs`. `have_done` counts finished own structures and units by def id (a `when` clause
## `have:<def>>=N`), `have_all` also counts sites (`skip_if_have`, so a queued Solar Array is not built twice).

var t_s: float = 0.0           ## match time, seconds
var ore: float = 0.0
var ice: float = 0.0
var power01: float = 1.0       ## supply / demand of the team (SimView.stockpile z)
var enemy_seen: bool = false   ## the team perceives at least one enemy contact
var affordable: bool = true    ## set per step by the host when the step's condition reads it
var presence: bool = false     ## set per step by the host when the step's condition reads it
var have_done: PackedInt32Array = PackedInt32Array()
var have_all: PackedInt32Array = PackedInt32Array()


## Sizes both count arrays to `n` def ids and zeroes them.
func size_defs(n: int) -> void:
	var _a: int = have_done.resize(n)
	var _b: int = have_all.resize(n)
	have_done.fill(0)
	have_all.fill(0)
