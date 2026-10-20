"""ART-04 acceptance recipe: a fresh file builds a test box asset (prop_test_box) and exports it.

Run headless: python tools/blender/run_headless.py tools/blender/selftest/prop_test_box.py <out_dir>
Run via MCP:  execute mcp_bootstrap.py once, then this file.
"""
import json
import os
import tempfile

import pw

OUT = os.environ.get("PW_OUT", os.path.join(tempfile.gettempdir(), "pw_out"))
ID = "prop_test_box"

pw.begin(ID, "prop")
box = pw.box("Crate", size=(4.0, 4.0, 4.0), loc=(0.0, 0.0, 2.0), swatch="hull_300")
pw.paint(box, "team_paint_mid", faces=[1])  # top face = team zone (1 of 6 faces: ~17 % of the surface)
pw.hardpoint("HP_Dock", (0.0, 0.0, 4.0))
report = pw.finalize(ID)
print("PW_REPORT " + json.dumps(report))
if not report["ok"]:
    raise SystemExit("finalize() reported failures")
print("PW_GLB " + pw.export_glb(ID, OUT))
