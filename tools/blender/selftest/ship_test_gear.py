"""ART-04 acceptance recipe: a minimal ship exercising mirror_x, landing_struts and the ship checks (V09-V11)."""
import json
import os
import tempfile

import pw

OUT = os.environ.get("PW_OUT", os.path.join(tempfile.gettempdir(), "pw_out"))
ID = "ship_test_gear"

pw.begin(ID, "ship")
DY, DZ = 0.42, -0.4  # centre the bbox on the origin (the struts reach behind the nozzle; V09)
pw.prism("Fuselage", 6, 0.9, 0.15, 12.0, "Y", (0.0, DY, DZ), "hull_300")
wing = pw.poly_plate("Wing", [(0.0, 2.0), (4.5, -3.0), (4.5, -4.0), (0.0, -4.0)], 0.25, (0.0, DY, DZ), "hull_400")
pw.paint(wing, "team_paint_mid", faces=[1])  # top face
pw.mirror_x([wing])
pw.prism("Engine", 6, 0.8, 0.8, 1.6, "Y", (0.0, DY - 5.4, DZ), "metal_gun")
pw.hardpoint("HP_Nose", (0.0, DY + 6.0, DZ))
pw.hardpoint("HP_Tail", (0.0, DY - 6.2, DZ))
pw.landing_struts(length=1.1, foot_radius=1.6, around=[(0.0, DY - 6.2, DZ)])
report = pw.finalize(ID)
print("PW_REPORT " + json.dumps(report))
if not report["ok"]:
    raise SystemExit("finalize() reported failures")
print("PW_GLB " + pw.export_glb(ID, OUT))
