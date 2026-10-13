extends RefCounted
## Test helper: byte layout of a SoA store by reflection over its public packed arrays.


## Sum of element bytes over the public packed arrays sized to `n` slots; returns [count, bytes].
static func layout_of(obj: Object, n: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array([0, 0])
	for p: Dictionary in obj.get_property_list():
		var pname: String = p["name"]
		if pname.begins_with("_") or (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var v: Variant = obj.get(pname)
		var elem: int = 0
		var size: int = -1
		match typeof(v):
			TYPE_PACKED_BYTE_ARRAY:
				elem = 1
				size = (v as PackedByteArray).size()
			TYPE_PACKED_INT32_ARRAY:
				elem = 4
				size = (v as PackedInt32Array).size()
			TYPE_PACKED_FLOAT32_ARRAY:
				elem = 4
				size = (v as PackedFloat32Array).size()
			TYPE_PACKED_VECTOR3_ARRAY:
				elem = 12
				size = (v as PackedVector3Array).size()
		if size == n:
			out[0] += 1
			out[1] += elem
	return out
