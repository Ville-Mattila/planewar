class_name MatchRules extends RefCounted
## One match's rules (R0 C2-12): 03's configuration (mode, caps profile, budget profile, flags) and 02's phase API.
## Built once per match by `from_defs` (or by the campaign per mission); `SimWorld` serializes it (S4).
## Phases (02 s12.1): PLAYING from tick 0, EXPOSURE from `core_exposure_s`, ENDED from `hard_end_s` (a victory
## ends the match earlier; that is world state, `SimView.match_phase()`). A negative timer (JSON null) never fires.

enum Phase { PLAYING, EXPOSURE, ENDED }

## 01 s3.3 arc bands as divisors of `core_exposure_s` (Open 0-5, Expand 5-15, Siege 15-30 of a 30 min exposure).
## Documented defaults of `match_rules.json` `arc_open_divisor` / `arc_expand_divisor` (R0 B.11 A-51, read by `from_defs`).
const _ARC_OPEN_DIV: int = 6
const _ARC_EXPAND_DIV: int = 2

var mode: StringName = &""
var caps_profile: StringName = &"standard"
var caps: CapsDef = null
var sim_budget_profile: PackedInt32Array = PackedInt32Array()
var core_exposure_s: float = -1.0
var hard_end_s: float = -1.0
var debug_commands: bool = false
var profile_enabled: bool = false
var friendly_fire: bool = false
var adjutant_allowed: StringName = &"off"
var sun_period_s: float = 0.0
var ranked: bool = false
var arc_open_divisor: int = _ARC_OPEN_DIV               ## match_rules.json (A-51); not S4 state: `adopt_match_def` on deserialize
var arc_expand_divisor: int = _ARC_EXPAND_DIV
var tick_hz: int = 0                                    ## rules.json tick_hz; converts the second timers to ticks


## Rules for `mode` with the caps profile `caps_profile` (empty: the mode's own `caps`), from content's defs.
## `adjutant_allowed` is the most permissive entry of the mode's `adjutant` list.
static func from_defs(mode_def: ModeDef, match_def: MatchRulesDef, rules: RulesDef, profile: StringName) -> MatchRules:
	var m: MatchRules = MatchRules.new()
	m.tick_hz = rules.tick_hz
	m.sim_budget_profile = rules.sim_budget_profile.duplicate()
	m.debug_commands = rules.debug_commands
	m.profile_enabled = rules.profile_enabled
	m.friendly_fire = rules.friendly_fire
	if mode_def != null:
		m.mode = mode_def.id
		m.core_exposure_s = mode_def.core_exposure_s
		m.hard_end_s = mode_def.hard_end_s
		m.ranked = mode_def.rating != &"none"
		for a: String in mode_def.adjutant:
			if a == "full" or (a == "economy" and m.adjutant_allowed == &"off"):
				m.adjutant_allowed = StringName(a)
	m.adopt_match_def(match_def)
	m.caps_profile = profile if profile != &"" else (mode_def.caps if mode_def != null else &"standard")
	var found: Variant = match_def.caps.get(m.caps_profile) if match_def != null else null
	m.caps = found if found is CapsDef else CapsDef.new()
	return m


## Takes the arc divisors from `match_def` (null or non-positive: the documented defaults stay).
func adopt_match_def(match_def: MatchRulesDef) -> void:
	if match_def != null:
		arc_open_divisor = match_def.arc_open_divisor if match_def.arc_open_divisor > 0 else _ARC_OPEN_DIV
		arc_expand_divisor = match_def.arc_expand_divisor if match_def.arc_expand_divisor > 0 else _ARC_EXPAND_DIV


## 02 s12.1 rules phase of `tick` from the clock alone.
func phase(tick: int) -> Phase:
	var s: float = _clock(tick)
	if hard_end_s >= 0.0 and s >= hard_end_s:
		return Phase.ENDED
	if core_exposure_s >= 0.0 and s >= core_exposure_s:
		return Phase.EXPOSURE
	return Phase.PLAYING


## 01 s3.3 clock band of `tick`, scaled by `core_exposure_s`; OPEN throughout when the mode has no exposure timer.
func arc(tick: int) -> MatchArc.Arc:
	if core_exposure_s <= 0.0:
		return MatchArc.Arc.OPEN
	var s: float = _clock(tick)
	if s >= core_exposure_s:
		return MatchArc.Arc.OVERTIME
	if s * float(arc_expand_divisor) >= core_exposure_s:
		return MatchArc.Arc.SIEGE
	if s * float(arc_open_divisor) >= core_exposure_s:
		return MatchArc.Arc.EXPAND
	return MatchArc.Arc.OPEN


func _clock(tick: int) -> float:
	return float(tick) / float(tick_hz) if tick_hz > 0 else 0.0
