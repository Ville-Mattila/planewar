"""Content hash (03 s9.2, R0 C2-34). Stdlib only. Reproduced byte-for-byte by ContentDB (TA-09).

Inputs: godot/content/defs/*.json (top level only), in byte-wise ascending file-name order, except
sfx.json and vfx_prewarm.json (and chat_filter.json, hash-excluded by 03 s9.2). content/ui/**,
content/locale/** and content/maps/** are not inputs. assists.json is included.

Canonical form of one file (UTF-8, no BOM):
  * parse the JSON; every object key named `presentation` or `_doc`, at any depth, is removed;
  * objects: keys sorted by Unicode code point (Python sorted() on str; GDScript Array.sort() on
    String), written `{"k":v,"k2":v2}`; arrays keep order `[a,b]`; no whitespace anywhere;
  * strings: `"` + chars + `"`, escaping only `"` -> \\", `\\` -> \\\\, and control chars < 0x20 as
    \\b \\t \\n \\f \\r or \\u00xx (lower-case hex). Everything else (incl. non-ASCII) is emitted raw;
  * numbers: JSON has one number type (GDScript parses all as float), so a number whose value is
    integral is written as an integer with no `.0`, no exponent, `-0` -> `0`; any other number is
    written as the shortest decimal digit string that round-trips the IEEE-754 double, in plain
    decimal (never an exponent), e.g. 0.1, 0.00001, 1234.5. NaN/Infinity and integers with
    |value| >= 2^53 are errors;
  * `true`, `false`, `null` literals.
The hash is SHA-256 (lower-case hex) over the per-file canonical strings joined with a single `\\n`
(no trailing newline; file names are not hashed). Zero input files hash the empty string.
Vector: tools/tests/content_hash_vector.json.
"""

from __future__ import annotations

import hashlib
import json
from decimal import Decimal
from pathlib import Path
from typing import Any

EXCLUDED_FILES = ("sfx.json", "vfx_prewarm.json", "chat_filter.json")
STRIPPED_KEYS = ("presentation", "_doc")
MAX_SAFE = 2 ** 53
_ESC = {'"': '\\"', "\\": "\\\\", "\b": "\\b", "\t": "\\t", "\n": "\\n", "\f": "\\f", "\r": "\\r"}


class HashError(ValueError):
    pass


def _string(s: str) -> str:
    return '"' + "".join(_ESC.get(c) or (f"\\u{ord(c):04x}" if ord(c) < 0x20 else c) for c in s) + '"'


def _number(x: int | float) -> str:
    if isinstance(x, float) and (x != x or x in (float("inf"), float("-inf"))):
        raise HashError("non-finite number")
    if x == int(x):
        if abs(x) >= MAX_SAFE:
            raise HashError(f"integer {x} outside +-2^53")
        return str(int(x))
    return format(Decimal(repr(float(x))), "f")


def canonical(v: Any) -> str:
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int, float)):
        return _number(v)
    if isinstance(v, str):
        return _string(v)
    if isinstance(v, list):
        return "[" + ",".join(canonical(e) for e in v) + "]"
    if isinstance(v, dict):
        return "{" + ",".join(_string(k) + ":" + canonical(v[k]) for k in sorted(v) if k not in STRIPPED_KEYS) + "}"
    raise HashError(f"unsupported value {type(v).__name__}")


def _reject_constant(name: str) -> Any:
    raise HashError(f"non-finite number {name}")


def canonical_text(text: str) -> str:
    return canonical(json.loads(text, parse_constant=_reject_constant))


def included_names(names: list[str]) -> list[str]:
    return sorted((n for n in names if n.endswith(".json") and n not in EXCLUDED_FILES), key=lambda n: n.encode())


def hash_texts(files: dict[str, str]) -> str:
    """files: file name -> raw JSON text. Applies the exclusion list; names are sorted byte-wise."""
    body = "\n".join(canonical_text(files[n]) for n in included_names(list(files)))
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def content_hash(defs_dir: Path) -> str:
    files = {p.name: p.read_text(encoding="utf-8-sig") for p in defs_dir.glob("*.json")} if defs_dir.is_dir() else {}
    return hash_texts(files)
