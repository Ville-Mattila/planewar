class_name SfTouchdown extends RefCounted
## Result of one landing evaluation (03 s6.4). Grade ordinals are `LandingGrade.Grade` (sim/MODULE.md, R0 B.3).

enum Outcome { NONE, LANDED, HARD, CRASH, SCRAPE, DAMAGED }
const GRADE_CRASH: int = 0
const GRADE_BENT: int = 1
const GRADE_HARD: int = 2
const GRADE_FAIR: int = 3
const GRADE_CLEAN: int = 4
const GRADE_ACE: int = 5
const GRADE_AUTO: int = 6
const GRADE_NAMES: PackedStringArray = ["CRASH", "BENT", "HARD", "FAIR", "CLEAN", "ACE", "AUTO"]

var outcome: Outcome = Outcome.NONE
var on_pad: bool                  # horizontal offset <= pad_radius_m
var offset_m: float               # horizontal distance to the pad centre in the pad tangent frame
var v_vert: float                 # sink speed along the pad normal (m/s, + = down)
var v_hor: float                  # tangential speed (m/s)
var tilt_deg: float               # angle between body forward (thrust axis) and the pad normal
var damage_hp: float              # hull damage applied by this contact
var q: float                      # LandingGrade quality 0..1 (03 s6.4)
var grade: int = -1               # LandingGrade.Grade, -1 when not a pad landing


func grade_name() -> String:
	return GRADE_NAMES[grade] if grade >= 0 and grade < GRADE_NAMES.size() else "-"


func outcome_name() -> String:
	var k: String = Outcome.keys()[outcome]
	return k
