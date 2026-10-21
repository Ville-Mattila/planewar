class_name PerfGate extends RefCounted
## Report-only timing gate for tests under godot/test/unit|sim|net (R0 B.17 A-97; 03 s4.4, 05 s11.1).
## On a GitHub-hosted runner a wall-clock bound never fails a test: check() prints one PERF_REPORT line and returns
## true. Only when PLANEWAR_PINNED_RUNNER == "1" (set by TA-42 on the pinned runner, or by a developer locally) is the
## bound asserted. Use as assert_bool(PerfGate.check(...)).override_failure_message(...).is_true() and keep at least one
## deterministic work counter hard-asserted beside it. Runaway guards (>= 10x the recorded figure) do not use this.

const ENV_NAME: String = "PLANEWAR_PINNED_RUNNER"


static func pinned() -> bool:
	return OS.get_environment(ENV_NAME) == "1"


static func check(name: String, us: float, bound_us: float, cite: String, host: float = 1.0) -> bool:
	var p: bool = pinned()
	print("PERF_REPORT name=%s us=%.3f bound_us=%.3f host=%.2f pinned=%d cite=%s" % [name, us, bound_us, host, 1 if p else 0, cite])
	if not p:
		return true
	return us < bound_us
