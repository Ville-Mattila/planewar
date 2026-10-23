class_name BomberBrain extends DartBrain
## The Bomber autopilot (05 s6.4, AI-14) on the DartBrain pipeline (think: docked check, one probe, PULL_UP with the
## A-92 exit, the RTB rule, dispatch, shaping; act: the A-89 check, the mode's controller, the AttackRun sight).
## AUTO = DOCKED (01 s4.3): docked it stays DOCKED; airborne with no order the RTB rule asks for one system RETURN
## (FLAG_PREPEND) and the landing pilot takes it to the best pad, or LOITERs over home at `no_pad_loiter_altitude_m`
## re-trying the pad choice each choice period while no pad is free. Orders: ATTACK (AttackRun, level release:
## `dart_dive` off), MOVE, RETURN, HOLD; PATROL / GUARD fly their legs and orbits without a choice point (it never
## dogfights: `DartModes.engages` off). An ATTACK on a ship is not a bomber's job: the run is marked done at once. After
## any ATTACK completes or fails: RETURN (`_return_after_attack`). Under attack before R2 the run aborts to egress
## (`AttackRun.abort_on_hit`); once R2 has begun it continues (05 s6.3's hull abort still applies). Gunless: the RTB
## rule has no ammo term; egress flips on an inbound rocket (AttackRun R4). Released mid-run, the run re-plans
## (05 s2.5, `AttackRun.resume`): no bombs -> DONE -> RETURN; within `ip_dist_m` and `continue_deg` of the nose ->
## RUN_IN from there; otherwise a new IP.


## The Bomber brain from content (`ap` = ap_bomber's dictionary); null when a required block is missing.
static func create(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> BomberBrain:
	var b: BomberBrain = BomberBrain.new()
	if not DartBrain.fill(b, c, ap, def, t, ring2_m, false, false) or not b.prm.has_bombs:
		return null
	b.modes.engages = false
	b.modes.run.dart_dive = false
	b.modes.run.abort_on_hit = true
	return b


func _dispatch(id: int, s: int, m: int, head: OrderSpec, kind: int, view: SimView, st: AiState, tick: int) -> int:
	if kind == OrderSpec.Kind.RETURN:
		return modes.think_return(id, s, m, head, view, st, tick)
	if kind == OrderSpec.Kind.ATTACK and (st.bflags[s] & B_RUN_DONE) == 0:
		if head.target != 0 and view.def_kind(head.target) == EntityStore.K_SHIP:
			st.sub[s] = AttackRun.Step.DONE   # no air-to-air weapon: done at once, RETURN follows
			st.bflags[s] |= B_RUN_DONE
			return modes.think_patrol(id, s, m, null, -1, view, st, tick)
		return modes.think_attack(id, s, m, head, view, st, tick)
	if kind == OrderSpec.Kind.MOVE:
		return modes.think_move(id, s, head, view, st)
	return modes.think_patrol(id, s, m, head, kind, view, st, tick)


## 05 s6.4: AUTO is DOCKED, so an airborne Bomber without an order (order_tick -1) asks for RETURN like the RTB rule.
func _needs_rtb(id: int, s: int, view: SimView, st: AiState, tick: int) -> bool:
	return st.order_tick[s] == -1 or super._needs_rtb(id, s, view, st, tick)


func _return_after_attack() -> bool:
	return true
