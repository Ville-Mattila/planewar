class_name MapPathing extends RefCounted
## (BUG-5, A-73 extract) `SimWorld.load_map`'s path-grid load (A-55): the baked weights of the map, then the region
## graphs for each distinct ground-unit slope mask (at most `PathSearch.MASK_SLOTS`, in def order) unless a
## deserialize brings them. The flat datum keeps weight 1 everywhere and builds graphs lazily. Static, map load only.


static func prepare(pathing: Pathing, ground_units: Array[GroundUnitDef], map_dir: String, restoring: bool) -> Error:
	var err: Error = pathing.load_weights(map_dir)
	if err != OK or restoring:
		return err
	var masks: PackedInt32Array = PackedInt32Array()
	for g: GroundUnitDef in ground_units:
		var m: int = Pathing.mask_for(g.max_slope_deg)
		if m > 0 and not masks.has(m) and masks.size() < PathSearch.MASK_SLOTS:
			var _a: bool = masks.push_back(m)
	for m: int in masks:
		pathing.prepare(m)
	return OK
