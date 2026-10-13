#!/usr/bin/env python3
"""Regenerate tools/tests/content_hash_vector.json (only when the canonical form changes: an ADR event)."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import content_hash as c  # noqa: E402

FILES = {
    "a_ships.json": '{"ships":[{"id":"dart","z":1.0,"a":[2,0.1,-0.0,1e-05,1234.5,3.0e2,0.30000000000000004],'
                    '"_doc":"x","presentation":{"model":"res://d.glb"},'
                    '"nested":{"_doc":"y","k":"caf\\u00e9 \\"q\\" \\\\ \\n \\u0001 \\u00e4\\u00f6"}}]}',
    "assists.json": '{ "assists" : [ {"id":"auto_level","gain":0.25,"on":true,"off":false,"none":null} ] }',
    "b_rules.json": '{"gravity":6.0,"tick_hz":30}',
    "chat_filter.json": '{"words":["x"]}',
    "sfx.json": '{"sfx":[{"id":"zap"}]}',
    "vfx_prewarm.json": '{"x":1}',
}

inc = c.included_names(list(FILES))
canon = [c.canonical_text(FILES[n]) for n in inc]
out = {
    "_doc": "Content hash vector (03 s9.2, R0 C2-34). `files`: def file name -> raw JSON text. Include/exclude by "
            "name (sfx.json, vfx_prewarm.json, chat_filter.json excluded), sort names byte-wise (`included`), "
            "canonicalise each (rules: tools/content_hash.py), join with \\n, SHA-256 the UTF-8 bytes. "
            "`canonical` lists the per-file strings in hash order.",
    "files": FILES,
    "included": inc,
    "canonical": canon,
    "sha256": c.hash_texts(FILES),
}
Path(__file__).resolve().parent.joinpath("tests/content_hash_vector.json").write_text(
    json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(out["sha256"])
