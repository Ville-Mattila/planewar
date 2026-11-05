class_name DrawerContextKit extends RefCounted
## Test adapter (and reference for app's): fills a DrawerContext from a SimView's player_state / team_state. `ui` cannot
## name those view types (tools/deps.json), so only tests and app may read them.

const PLAYER_SLOTS: int = 8
const LOCK_FROM_VIEW: int = -2   ## lock_left: read PlayerStateView.early_spend_left_ore


static func from_view(v: SimView, player: int, lock_left: int = LOCK_FROM_VIEW) -> DrawerContext:
	var c: DrawerContext = DrawerContext.new()
	c.player = player
	var ps: PlayerStateView = v.player_state(player)
	if ps == null:
		c.eliminated = true
		c.commander_rights = false
		return c
	c.team = ps.team
	c.doctrine = ps.doctrine
	c.commander_rights = ps.commander_rights
	c.eliminated = ps.eliminated
	c.unit_count = ps.unit_count if ps.unit_count > 0 else v.unit_count(player)
	c.lock_left_ore = ps.early_spend_left_ore if lock_left == LOCK_FROM_VIEW else lock_left
	var ts: TeamStateView = v.team_state(ps.team)
	if ts != null:
		c.ore = ts.ore
		c.ice = ts.ice
		c.unit_cap = ts.unit_cap
		c.structure_cap = ts.structure_cap
	for slot: int in PLAYER_SLOTS:
		var o: PlayerStateView = v.player_state(slot)
		if o != null:
			c.set_player(slot, o.team, o.kind, o.connected, o.eliminated)
	return c
