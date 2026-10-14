class_name MatchArc
## Enum holder for the match clock band (R0 B.3; 01 s3.3; 05 s7 reads it through `SimView.match_arc()`).
## `MatchRules.arc(tick)` maps the clock to a band scaled by the mode's `core_exposure_s` (C3-19).

enum Arc { OPEN, EXPAND, SIEGE, OVERTIME }
