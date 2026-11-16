class_name LinkLimits extends RefCounted
## Per-link limits of the server (04 s2.2 handshake timeouts, s11.3 strikes, s11.4 rate table). Transport policy, not sim
## state, so the numbers are here with their citation; the two the sim defs already own (command rate and burst:
## rules.json command_rate_per_s / command_burst, R0 C2-27; LOADED timeout: match_rules.json load_timeout_s) are
## taken from those defs by `from_defs`, never duplicated.

## 04 s11.4 channel hard caps before parsing: ch0 1,024 B, ch1 64 B, ch2/ch3 2,048 B inbound.
const CHANNEL_CAP: PackedInt32Array = [1024, 64, 2048, 2048]

var hello_timeout_ms: int = 5000       ## 04 s2.2: TCP/UDP connect -> valid HELLO
var load_timeout_ms: int = 60000       ## 04 s2.2: WELCOME -> LOADED (match_rules.json load_timeout_s)
var close_delay_ms: int = 500          ## 04 s2.2: close 500 ms after REFUSE so the message flushes
var packets_per_s: float = 120.0       ## 04 s11.4
var packet_burst: float = 120.0
var bytes_per_s: float = 8.0 * 1024.0  ## 04 s11.4: 8 KB/s inbound
var byte_burst: float = 8.0 * 1024.0
var command_per_s: float = 10.0        ## 04 s11.3/s11.4 (rules.json)
var command_burst: float = 30.0
var chat_per_s: float = 2.0            ## 04 s11.4
var chat_burst: float = 5.0
var ping_per_s: float = 1.0            ## QUICK_PING, 04 s11.4
var ping_burst: float = 3.0
var keyframe_interval_ms: int = 5000   ## REQUEST_KEYFRAME: 1 per 5 s
var strike_limit: int = 20             ## 04 s11.3: 20 strikes per window -> KICK
var strike_window_ms: int = 60000
var kick_ban_ms: int = 60000           ## REFUSE(RATE_LIMIT) on reconnect, enforced by ServerSession (NET-15)
var input_queue_max: int = 16          ## channel-1 packets held per link between ticks (oldest dropped)
var control_queue_max: int = 32        ## channel-0 control packets held per link between ticks (newest dropped)


static func channel_cap(channel: int) -> int:
	return CHANNEL_CAP[channel] if channel >= 0 and channel < CHANNEL_CAP.size() else 0


## Defaults with the command bucket from rules.json and the load timeout from match_rules.json.
static func from_defs(rules: RulesDef, match_rules: MatchRulesDef) -> LinkLimits:
	var l: LinkLimits = LinkLimits.new()
	if rules != null:
		l.command_per_s = float(rules.command_rate_per_s)
		l.command_burst = float(rules.command_burst)
	if match_rules != null:
		l.load_timeout_ms = int(match_rules.load_timeout_s * 1000.0)
	return l
