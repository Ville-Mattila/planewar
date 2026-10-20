# tools/blender

Blender asset tooling (docs/07 s4). Recipes are Python; `.blend` files are never committed.

| File | Role |
|---|---|
| `lib/pw.py` | helper library used by recipes (needs `bpy`, Blender >= 4.2): `begin`, `box`, `prism`, `poly_plate`, `paint`, `mirror_x`, `hardpoint`, `emblem_quad`, `foundation`, `landing_struts`, `far_mesh`, `finalize`, `export_glb` (07 s4.4) |
| `lib/pw_core.py` | pure Python (no `bpy`): palette -> UV, mesh generators, foundation rule, strut layout, the check rules behind `finalize()` |
| `mcp_bootstrap.py` | run once through the Blender MCP `execute_blender_code` tool: sets `sys.path`, reloads `pw`, prints the exporter options |
| `run_headless.py` | `python tools/blender/run_headless.py <recipe.py> [out_dir]`: fresh `blender -b --factory-startup` run (uses `$BLENDER_BIN`, PATH, or the newest Program Files install); never touches a running Blender |
| `selftest/` | acceptance recipes (`prop_test_box`, `ship_test_gear`) and negative fixtures |
| `palette.json`, `build_palette.py` | colour source of truth (ART-02) |

## Recipe skeleton

```python
import pw
pw.begin("ship_dart", "ship")           # creates PW_ship_dart; replaces only a previous collection of that name
body = pw.prism("Fuselage", 6, 0.9, 0.15, 12.0, "Y", (0, 0, 0), "hull_300")
pw.hardpoint("HP_Nose", (0, 6, 0)); pw.hardpoint("HP_Tail", (0, -6, 0))
pw.landing_struts(1.1, 1.6, [(0, -6, 0)])   # HP_Gear_0..2
report = pw.finalize("ship_dart")       # dict: ok, tris, checks[{id,status,detail}]; ids follow validate_glb.py (07 s4.7)
pw.export_glb("ship_dart", out_dir)
```

## Behaviour worth knowing

- Geometry is built in place at identity transform; `finalize()` rejects rotated/scaled objects.
- `finalize()` joins everything except `Foundation`, `Turret`, `Barrel`, `Roof`, `Arm_L/R` and `*Far` parts into `Hull`,
  dissolves coplanar faces (1 degree, UV and material boundaries respected), flat-shades, adds a Triangulate modifier,
  and normalises the material slot to `PW_Atlas`.
- `finalize()` reports V01, V03, V04, V06, V07, V09-V12, V14, V15. V02, V05, V08, V13 need the glb and the scale chart
  and show `skip`. V03 is `skip` until a budget is passed (`finalize(id, budget=...)`; `asset_budgets.json` is ART-05).
- `export_glb` creates the identity root node `PascalCase(id)` (V02), asserts every glTF exporter option it uses exists.
- `landing_struts(length, foot_radius, around)`: one `around` point = single engine (feet on a circle of `foot_radius`);
  three points = boom/engine attach points (feet pushed outward by `length*sin 20`; `foot_radius` unused). 30 tris total.
- `far_mesh` decimates to <= `target_tris` and repaints to the dominant swatch; repaint the team zone with `paint` after.

## Tests

```
python -m unittest discover -s tools/tests -p "test_pw_*.py"
```
`test_pw_core.py` is pure Python. `test_pw_blender.py` runs the selftest recipes in real Blender and re-reads the exported glb
in pure Python; it skips when no Blender is found.
