class_name PlacementRings extends RefCounted
## Which rings the armed def shows (docs/06 s7.3), from the SimView and content. Outpost has no radius requirement: it
## shows the presence ring (follows the ghost), amber rings around friendly Cores / Outposts and red ones around enemy
## ones the team can see, construction sites included (`Build.can_place` counts them for SPACING). Every other def shows the build radius of own finished structures, and visible enemy ones in red.


static func rings(view: SimView, team: int, def: StringName) -> Array[PlacementRing]:
	var out: Array[PlacementRing] = []
	if view == null or ContentDB.structure(ContentDB.def_index(def)) == null:
		return out
	var ec: EconomyDef = ContentDB.economy
	var outpost: bool = def == &"outpost"
	var core: int = ContentDB.def_index(&"core")
	var out_def: int = ContentDB.def_index(&"outpost")
	if outpost and ec != null:
		out.append(_ring(PlacementRing.Kind.PRESENCE, Vector3.ZERO, ec.outpost_presence_radius_m, true, -1))
	for id: int in view.structures():
		if not view.alive(id):
			continue
		var mine: bool = view.team(id) == team
		if not mine and not view.visible_to(team, id):
			continue                                                       # fog: never reveal what the team cannot see
		var d: int = view.def_id(id)
		if outpost:
			if (d == core or d == out_def) and ec != null:
				var kind: PlacementRing.Kind = PlacementRing.Kind.SPACING_FRIENDLY if mine else PlacementRing.Kind.SPACING_ENEMY
				var r: float = ec.outpost_spacing_friendly_m if mine else ec.outpost_spacing_enemy_m
				out.append(_ring(kind, view.pos(id), r, false, id))
			continue
		if (view.flags(id) & DrawerModel.FLAG_BUILDING) != 0:
			continue                                                       # build radius needs a finished structure; spacing (above) counts sites too
		var sd: StructureDef = ContentDB.structure(d)
		if sd != null and sd.build_radius > 0.0:
			out.append(_ring(PlacementRing.Kind.BUILD if mine else PlacementRing.Kind.ENEMY_BUILD, view.pos(id), sd.build_radius, false, id))
	return out


static func _ring(kind: PlacementRing.Kind, center: Vector3, radius: float, follows: bool, source: int) -> PlacementRing:
	var r: PlacementRing = PlacementRing.new()
	r.kind = kind
	r.center = center
	r.radius_m = radius
	r.follows_ghost = follows
	r.source = source
	return r
