class_name ProbeResult extends RefCounted
## Output of TerrainProbe.probe (05 s5.3): one preallocated instance per brain, overwritten by every call, so a
## think allocates nothing.

var tti_s: float = INF                 ## first crossing found at sample resolution; INF if clear
var min_clearance_m: float = INF       ## clearance of the worst (lowest) sample
var worst_t_s: float = 0.0             ## time of the worst sample
var worst_dir: Vector3 = Vector3.ZERO  ## unit direction over the planet of the worst sample
var lift_mps: float = 0.0              ## extra climb along local up for v_cmd (0 when clear)
var climb_need_mps: float = -INF       ## AI-13: max over samples of (h_req - drop-free c'_k) / max(t_k, lift_min_time_s): the extra
                                       ## radial speed over the current one that clears every sample by h_req (< 0: spare)
