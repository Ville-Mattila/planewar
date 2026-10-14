class_name ChunkScheduler extends RefCounted
## Per-frame chunk build budget (03 s7.4, ADR-04, R0 C1-06). The quadtree refills `queue` every frame in
## `plan`; `run` pops by priority until the count cap or the ms cap is spent. A build whose estimated cost
## would overrun the ms cap waits, except under the starvation rule: when the queue is non-empty and no build
## ran in the last `starvation_frames` frames, exactly one build runs regardless of the ms cap, so at least
## one build per (starvation_frames + 1) frames is guaranteed. Both budgets come from quality_tiers.json.

const EST_BLEND: float = 0.25                ## weight of the newest measurement in the cost estimate

var budget_builds_per_frame: int = 6
var budget_ms_per_frame: float = 4.0
var starvation_frames: int = 2
var frames_since_build: int = 0              ## frames in a row with a non-empty queue and no build
var queue: Array[ChunkNode] = []
var est_build_ms: float = 0.0                ## running estimate of one build (exponential average)
var last_builds: int = 0                     ## builds executed by the last run()
var last_ms: float = 0.0                     ## ms spent by the last run()
var last_forced: bool = false                ## the last run() used the starvation rule
var total_builds: int = 0


func configure(cfg: PlanetTierConfig) -> void:
	budget_builds_per_frame = cfg.builds_per_frame
	budget_ms_per_frame = cfg.build_ms_cap
	starvation_frames = cfg.starvation_frames


## Starts a new plan: the queue is rebuilt from scratch every frame (re-prioritised, 03 s7.4).
func begin_plan() -> void:
	queue.clear()


## Adds `node` once per frame; `frame` de-duplicates pushes. A node that was not queued in the previous
## frame starts a new wait at `now_ms` (node.wanted_since_ms, the hole-time statistic of 03 s14.2).
func push(node: ChunkNode, frame: int, now_ms: int) -> void:
	if node.queued_frame == frame:
		return
	if node.queued_frame != frame - 1:
		node.wanted_since_ms = now_ms
	node.queued_frame = frame
	queue.append(node)


## Runs builds by descending priority. `build` is `func(node: ChunkNode) -> float` returning the measured ms,
## or a negative value when the build could not run (no pool slot), which ends the run. Returns the number
## of builds executed.
func run(build: Callable) -> int:
	last_builds = 0
	last_ms = 0.0
	last_forced = false
	if queue.is_empty():
		frames_since_build = 0
		return 0
	queue.sort_custom(_higher_priority)
	var forced: bool = frames_since_build >= starvation_frames
	for node: ChunkNode in queue:
		if last_builds >= budget_builds_per_frame:
			break
		if last_ms + est_build_ms > budget_ms_per_frame and not (forced and last_builds == 0):
			break
		var ms: float = build.call(node)
		if ms < 0.0:
			break
		last_forced = last_forced or (last_ms + est_build_ms > budget_ms_per_frame)
		last_builds += 1
		last_ms += ms
		est_build_ms = ms if total_builds == 0 else lerpf(est_build_ms, ms, EST_BLEND)
		total_builds += 1
		if forced and last_ms > budget_ms_per_frame:
			break
	frames_since_build = 0 if last_builds > 0 else frames_since_build + 1
	return last_builds


static func _higher_priority(a: ChunkNode, b: ChunkNode) -> bool:
	return a.priority > b.priority
