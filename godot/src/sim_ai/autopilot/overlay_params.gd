class_name OverlayParams extends RefCounted
## Per-class parameters of the overlays SAFETY and RECOVER_CEILING (05 s2.4, s4.4; AI-08), read-only, built once
## from the class's autopilot def plus the ship def and the world rules. Ships carry the LINK_BRIDGE parameters
## (`BridgeParams`: flight gains, probe, pull-up threshold) so the SAFETY law and `Assist.link_bridge` read the
## same numbers; ground units only hold the brake time. No numeric defaults (ADR-09).

## Top-level ship keys besides BridgeParams.KEYS and the `flight` block. `recover_ceiling_*` are AI-08 additions
## to the 05 s4.4 set (05 s2.4 table: flight-path angle -20 degrees, exit at 1,400 m); needs content (AI-19).
const KEYS: PackedStringArray = ["safety_clear_tti_s", "safety_min_hold_s", "safety_max_hold_s",
	"safety_force_rtb_fuel01", "recover_ceiling_gamma_deg", "recover_ceiling_exit_alt_m"]

var bridge: BridgeParams = null        ## null for ground units
var ground: bool = false               ## 05 s2.4: ground SAFETY = brake for safety_min_hold_s, then resume
var clear_tti_s: float = 0.0           ## SAFETY and PULL_UP end at TTI >= this (4.0 s)
var min_hold_ticks: int = 0            ## SAFETY lasts at least this long (0.5 s)
var max_hold_ticks: int = 0            ## ... and at most (3.0 s) unless a PULL_UP is still running
var force_rtb_fuel01: float = 0.0      ## system RETURN below this fuel fraction (0.20)
var rc_gamma_rad: float = 0.0          ## RECOVER_CEILING flight-path angle (-20 degrees)
var rc_exit_alt_m: float = 0.0         ## RECOVER_CEILING ends at or below this altitude (1,400 m)
var ceiling_hard_m: float = 0.0        ## rules.ceiling_hard_m: a release at or above it recovers (C11)
var v_cruise: float = 0.0              ## ShipDef.v_cruise: RECOVER_CEILING speed command


## Ship-class parameters; null when a key is missing or not a number.
static func for_ship(ap: Dictionary, def: ShipDef, rules: RulesDef, tick_hz: int,
		flight_common: FlightCommonDef) -> OverlayParams:
	var bp: BridgeParams = BridgeParams.from_autopilot(ap, def, rules, tick_hz, flight_common)
	if bp == null or not _has_numbers(ap, KEYS):
		return null
	var r: OverlayParams = OverlayParams.new()
	r.bridge = bp
	r.clear_tti_s = _f(ap, "safety_clear_tti_s")
	r.min_hold_ticks = roundi(_f(ap, "safety_min_hold_s") * float(tick_hz))
	r.max_hold_ticks = roundi(_f(ap, "safety_max_hold_s") * float(tick_hz))
	r.force_rtb_fuel01 = _f(ap, "safety_force_rtb_fuel01")
	r.rc_gamma_rad = deg_to_rad(_f(ap, "recover_ceiling_gamma_deg"))
	r.rc_exit_alt_m = _f(ap, "recover_ceiling_exit_alt_m")
	r.ceiling_hard_m = rules.ceiling_hard_m
	r.v_cruise = def.v_cruise
	return r


## Ground-unit parameters (only `safety_min_hold_s` is read); null when it is missing.
static func for_ground(ap: Dictionary, rules: RulesDef, tick_hz: int) -> OverlayParams:
	if not _has_numbers(ap, PackedStringArray(["safety_min_hold_s"])):
		return null
	var r: OverlayParams = OverlayParams.new()
	r.ground = true
	r.min_hold_ticks = roundi(_f(ap, "safety_min_hold_s") * float(tick_hz))
	r.ceiling_hard_m = rules.ceiling_hard_m
	return r


static func _has_numbers(ap: Dictionary, keys: PackedStringArray) -> bool:
	for k: String in keys:
		if not (ap.get(k) is float or ap.get(k) is int):
			return false
	return true


static func _f(d: Dictionary, k: String) -> float:
	var x: Variant = d[k]
	if x is int:
		var i: int = x
		return float(i)
	var f: float = x
	return f
