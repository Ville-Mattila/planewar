"""Paste/run once through the Blender MCP `execute_blender_code` tool (ART-04, 07 s4.1, s4.6).

Puts tools/blender/lib on sys.path, (re)loads pw and prints the installed glTF exporter options. Set REPO below
to the absolute path of the repo checkout (or define PW_REPO in the environment before starting Blender).
It never touches existing collections: recipes start with pw.begin(), which replaces only PW_<asset_id>.
"""
import importlib
import os
import sys

REPO = os.environ.get("PW_REPO", r"C:\Työt\Koodaus\Planewar")
LIB = os.path.join(REPO, "tools", "blender", "lib")
if not os.path.isfile(os.path.join(LIB, "pw.py")):
    raise RuntimeError(f"pw.py not found under {LIB}; set REPO / PW_REPO")
if LIB not in sys.path:
    sys.path.insert(0, LIB)
import pw_core  # noqa: E402
import pw  # noqa: E402

importlib.reload(pw_core)
importlib.reload(pw)
print("pw loaded from", pw.__file__)
print("glTF export options:", ", ".join(pw.export_options()))
