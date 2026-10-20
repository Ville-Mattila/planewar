"""begin() replaces only a previous PW_<id>; other collections and objects survive (07 s4.1 MCP safety rule)."""
import bpy

import pw

other = bpy.data.collections.new("UserStuff")
bpy.context.scene.collection.children.link(other)
keep = bpy.data.objects.new("Keep", None)
other.objects.link(keep)

pw.begin("prop_twice", "prop")
pw.box("A", (1, 1, 1), (0, 0, 0.5), "hull_300")
pw.begin("prop_other", "prop")
pw.box("B", (1, 1, 1), (0, 0, 0.5), "hull_300")
pw.begin("prop_twice", "prop")  # replaces only PW_prop_twice
assert len(bpy.data.collections["PW_prop_twice"].objects) == 0
assert len(bpy.data.collections["PW_prop_other"].objects) == 1
assert "Keep" in bpy.data.objects and "UserStuff" in bpy.data.collections
assert "A" not in bpy.data.objects and "A" not in bpy.data.meshes
try:
    pw.begin("prop_x", "ship")
except ValueError:
    pass
else:
    raise AssertionError("class/id prefix mismatch must raise")
print("BEGIN_TWICE_OK")
