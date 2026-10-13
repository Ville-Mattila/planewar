class_name MapDef extends Def
## Metadata of maps/<map_id>/recipe.json (R0 B.2). The terrain bytes belong to sim/Terrain; the full
## recipe stays in `raw` for the sim and the baker. Not part of the content hash (R0 B.1).


static func from_dict(d: Dictionary) -> MapDef:
	var m: MapDef = MapDef.new()
	m._read_common(d)
	return m
