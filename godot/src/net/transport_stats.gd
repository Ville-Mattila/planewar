class_name TransportStats extends RefCounted
## Per-connection counters returned by Transport.stats(); each call returns the counts since the previous call
## (04 s6.1). loss_estimate is the share of unreliable packets sent that the link dropped (0..1).

var bytes_in: int = 0
var bytes_out: int = 0
var packets_in: int = 0
var packets_out: int = 0
var loss_estimate: float = 0.0
