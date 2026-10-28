class_name LandingStamp extends RefCounted
## Plain data of the grade stamp, built from a LANDING SimEvent (docs/06 s6.4, R0 C3-13, A-121). Points come from
## scoring.json `landing_grade` (points per grade, hot_multiplier, dead_stick_points): hot multiplies the grade
## points, dead stick adds a flat bonus beside it. CRASH, BENT and AUTO score 0 base points.

const SCORING_PATH: String = "res://content/defs/scoring.json"
const FLAG_MANUAL: int = 1
const FLAG_HOT: int = 2
const FLAG_DEAD_STICK: int = 4
const GRADE_KEYS: Array[StringName] = [&"hud.grade.crash", &"hud.grade.bent", &"hud.grade.hard", &"hud.grade.fair",
		&"hud.grade.clean", &"hud.grade.ace", &"hud.grade.auto"]
const POINT_KEYS: Array[String] = ["", "", "hard", "fair", "clean", "ace", ""]   # indexed by LandingGrade.Grade

static var _cfg: Dictionary = {}

var ship: int = 0
var pad: int = 0
var grade: int = LandingGrade.Grade.AUTO
var q: float = 0.0
var manual: bool = false
var hot: bool = false
var dead_stick: bool = false
var v_vert: float = 0.0
var v_horiz: float = 0.0
var base_points: int = 0
var hot_mult: float = 1.0
var bonus_points: int = 0


## Null unless `e` is a well-formed LANDING event (grade in range, five extra bytes).
static func from_event(e: SimEvent) -> LandingStamp:
	if e == null or e.kind != SimEvent.Kind.LANDING or e.extra.size() < 5 or e.extra[0] >= GRADE_KEYS.size():
		return null
	var s: LandingStamp = LandingStamp.new()
	s.ship = e.a
	s.pad = e.b
	s.grade = e.extra[0]
	s.q = e.value
	var flags: int = e.extra[2]
	s.manual = (flags & FLAG_MANUAL) != 0
	s.hot = (flags & FLAG_HOT) != 0
	s.dead_stick = (flags & FLAG_DEAD_STICK) != 0
	s.v_vert = float(e.extra[3]) * 0.1
	s.v_horiz = float(e.extra[4]) * 0.1
	var cfg: Dictionary = _config()
	var pts: Dictionary = _sub(cfg, "points")
	var key: String = POINT_KEYS[s.grade]
	s.base_points = int(Def.num(pts.get(key, 0))) if key != "" else 0
	s.hot_mult = Def.num(cfg.get("hot_multiplier", 1.0)) if s.hot else 1.0
	if s.dead_stick and s.grade != LandingGrade.Grade.CRASH:
		s.bonus_points = int(Def.num(cfg.get("dead_stick_points", 0)))
	return s


## Points shown on the stamp: grade points x hot multiplier, plus the dead-stick bonus.
func total_points() -> int:
	return int(roundf(float(base_points) * hot_mult)) + bonus_points


func label_key() -> StringName:
	return GRADE_KEYS[grade]


func color() -> Color:
	match grade:
		LandingGrade.Grade.ACE, LandingGrade.Grade.CLEAN:
			return UiTokens.UI_OK
		LandingGrade.Grade.FAIR, LandingGrade.Grade.AUTO:
			return UiTokens.UI_ACCENT
		LandingGrade.Grade.HARD, LandingGrade.Grade.BENT:
			return UiTokens.UI_WARN
	return UiTokens.UI_DANGER


static func _config() -> Dictionary:
	if _cfg.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCORING_PATH))
		var root: Dictionary = parsed if parsed is Dictionary else {}
		_cfg = _sub(root, "landing_grade")
	return _cfg


static func _sub(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key)
	var out: Dictionary = v if v is Dictionary else {}
	return out
