"""Negative fixture for finalize(): a kept-separate part with an illegal name (V15) is reported; the material
slot of every part is normalised to PW_Atlas (V04 passes)."""
import bpy

import pw

pw.begin("prop_defects", "prop")
good = pw.box("Crate", (2, 2, 2), (0, 0, 1), "hull_300")
pw.paint(good, "team_paint_mid", faces=[1])
rogue = pw.box("Bad.Far", (1, 1, 1), (4, 0, 0.5), "hull_300")  # '*Far' parts stay separate; '.' is illegal
rogue.data.materials.clear()
rogue.data.materials.append(bpy.data.materials.new("Other"))
rep = pw.finalize("prop_defects")
st = {c["id"]: c["status"] for c in rep["checks"]}
assert rep["ok"] is False, st
assert st["V15"] == "fail", st
assert st["V04"] == "pass", st
print("DEFECTS_OK")
