"""Paste/run once through the Blender MCP `execute_blender_code` tool (ART-04, 07 s4.1, s4.6).

Puts tools/blender/lib on sys.path, (re)loads pw and prints the installed glTF exporter options.
Set PW_REPO (absolute path of the repo checkout) in the environment before starting Blender; if this file is run
from disk the repo root is derived from __file__. Without either it raises.
It never touches existing collections: recipes start with pw.begin(), which replaces only PW_<asset_id>.
"""
import importlib
import os
import sys

REPO = os.environ.get("PW_REPO")
if not REPO and "__file__" in globals():
    REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not REPO:
    raise RuntimeError("set the PW_REPO environment variable (absolute path of the repo checkout) before running this")
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
