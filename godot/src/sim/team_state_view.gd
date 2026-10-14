class_name TeamStateView extends RefCounted
## Read-only view of 03 s3.2 `TeamState` (R0 B.8 A-8); wire form 04 TEAM_STATE 0x85. `SimView.team_state(team)`
## returns one reused instance per team, refilled on every call (S3: no allocation on read).

const CORE_EXPOSURE: int = 1
const LOW_POWER: int = 2
const CORE_SHIELD_UP: int = 4
const SPEND_LOCK_ACTIVE: int = 8

var team: int = 0
var unknown: bool = false
var ore: int = 0
var ice: int = 0
var ore_cap: int = 0
var ice_cap: int = 0
var power_supply: float = 0.0
var power_demand: float = 0.0
var unit_cap: int = 0
var structure_cap: int = 0
var members: PackedInt32Array = PackedInt32Array()
var eliminated: bool = false
var flags: int = 0
