class_name PlayerResult extends RefCounted
## One player's row of the match result (02 s17.1 "Match result fields"; 04 s2.3 `MATCH_END` per_player[]). Plain data
## filled by `ScoreKeeper.result`; the wire encoding is `net`'s / `server`'s (NET-22).

var slot: int = 0
var team: int = -1
var score_pilot: int = 0
var score_commander: int = 0
var kills: int = 0
var deaths: int = 0
var structures_built: int = 0
var structures_destroyed: int = 0
var manual_landings: int = 0
var sorties: int = 0
var ore_mined: int = 0
var ore_spent: int = 0
var ice_delivered: int = 0
var pilot_time_s: PackedInt32Array = PackedInt32Array()   ## seconds possessed per ship class: dart, lancer, bomber, scout, hauler
var medals: PackedByteArray = PackedByteArray()           ## `medals.json` order; empty until the medal evaluator lands (GD-28)
