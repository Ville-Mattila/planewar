class_name DockedMode extends RefCounted
## AI-45: the DOCKED mode of the ship brains against the real Docking (05 s6.2 as amended by R0 B.24 A-119). A ship
## parked on a service pad keeps its brain mode DOCKED (thrust 0, nothing driven) until `leaves` says so: its service
## is complete (`SimView.service_progress` full, the state SERVICED announces), or an ALERT WAITING_FOR_ICE / WAITING_FOR_ORE
## named it (`note_alert` sets `AiState.OV_SVC_PAUSED`, fed by `AiDriver.on_event`) and `fuel01` has reached
## `landing.auto_launch_fuel01` (02 s2.3: an AUTO ship waits until fuel >= 50 %). Then the brain is in LAUNCH mode and
## drives full thrust along the pad normal; the sim's thrust hold (flight_common, A-119) does the rest. The Bomber leaves only on an order (05 s2.5 row 3). All numbers are defs; static, no allocation.


## ALERT event (a = AlertKind, b = ship): remembers a service pause for a registered ship of a class that hears it
## (`AiBrain.hears_service_pause`); the memory survives Overlays.enter / clear and ends when the ship flies (`clear`).
static func note_alert(st: AiState, ev: SimEvent, brains: Array[AiBrain]) -> void:
	if ev.a != AlertKind.Kind.WAITING_FOR_ICE and ev.a != AlertKind.Kind.WAITING_FOR_ORE:
		return
	var s: int = EntityId.slot(ev.b)
	if s <= 0 or s >= st.capacity or st.cls[s] == AiState.NO_CLASS or st.eid[s] != ev.b:
		return
	var br: AiBrain = brains[st.cls[s]] if st.cls[s] < brains.size() else null
	if br != null and br.hears_service_pause():   # ships only: construction / production alerts name structures
		st.ov_flags[s] |= AiState.OV_SVC_PAUSED


## True when the docked ship `id` (slot `s`) should launch now. `needs_order`: the Bomber, which only leaves on an
## order. `auto_launch01`: the class's landing.auto_launch_fuel01 (negative: no pause exit).
static func leaves(id: int, s: int, view: SimView, st: AiState, needs_order: bool, auto_launch01: float) -> bool:
	if needs_order:   # a RETURN head is the order that brought it home (05 s2.5: it completes on landing)
		var head: OrderSpec = view.order_head(id)
		return head != null and head.kind != OrderSpec.Kind.RETURN
	var pr: Vector3 = view.service_progress(id)
	if pr.x >= 1.0 and pr.y >= 1.0 and pr.z >= 1.0:
		return true
	return (st.ov_flags[s] & AiState.OV_SVC_PAUSED) != 0 and auto_launch01 >= 0.0 and view.fuel01(id) >= auto_launch01


## The pause memory ends with the stay.
static func clear(st: AiState, s: int) -> void:
	st.ov_flags[s] &= ~AiState.OV_SVC_PAUSED
