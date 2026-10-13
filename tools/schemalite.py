"""Stdlib-only validator for the JSON Schema (draft 2020-12) subset used by tools/schemas/.

The docs name no schema library and the dependency allowlist (01 ADR-14) has none, so this
implements exactly the keywords the CONTRACT-0 schemas use. A schema that uses any other keyword
is rejected by `check_schema`, so an unsupported keyword can never be silently ignored.

Supported: $ref (local "#/..." and sibling "<file>.schema.json#/..."), $defs, type, enum, const,
properties, required, additionalProperties, propertyNames, minProperties, maxProperties, items,
minItems, maxItems, uniqueItems, minimum, maximum, exclusiveMinimum, exclusiveMaximum, pattern,
minLength, maxLength, oneOf, anyOf. Annotations: $schema, $id, $comment, title, description.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Callable

ANNOTATIONS = {"$schema", "$id", "$comment", "title", "description"}
ASSERTIONS = {
    "$ref", "$defs", "type", "enum", "const", "properties", "required", "additionalProperties",
    "propertyNames", "minProperties", "maxProperties", "items", "minItems", "maxItems", "uniqueItems",
    "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "pattern", "minLength", "maxLength",
    "oneOf", "anyOf",
}
TYPES = {"object", "array", "string", "number", "integer", "boolean", "null"}

Error = tuple[str, str]  # (instance JSON pointer, message)


def is_type(value: Any, name: str) -> bool:
    if name == "null":
        return value is None
    if name == "boolean":
        return isinstance(value, bool)
    if name == "object":
        return isinstance(value, dict)
    if name == "array":
        return isinstance(value, list)
    if name == "string":
        return isinstance(value, str)
    if isinstance(value, bool):
        return False
    if name == "number":
        return isinstance(value, (int, float))
    if name == "integer":
        return isinstance(value, int) or (isinstance(value, float) and value.is_integer())
    raise ValueError(f"unknown type {name}")


def canon(value: Any) -> str:
    """Canonical text for JSON equality: 1 == 1.0, but true != 1."""
    def norm(v: Any) -> Any:
        if isinstance(v, bool) or v is None or isinstance(v, str):
            return v
        if isinstance(v, (int, float)):
            return int(v) if float(v).is_integer() else float(v)
        if isinstance(v, list):
            return [norm(x) for x in v]
        return {k: norm(x) for k, x in v.items()}
    return json.dumps(norm(value), sort_keys=True, separators=(",", ":"))


def _ptr(base: str, key: Any) -> str:
    return f"{base}/{str(key).replace('~', '~0').replace('/', '~1')}"


class SchemaStore:
    """Loads `<stem>.schema.json` files from one directory and resolves $ref between them."""

    def __init__(self, directory: Path) -> None:
        self.dir = directory
        self.docs: dict[str, dict] = {}

    def load(self, name: str) -> dict:
        if name not in self.docs:
            self.docs[name] = json.loads((self.dir / name).read_text(encoding="utf-8"))
        return self.docs[name]

    def resolve(self, ref: str, current: str) -> tuple[dict, str]:
        doc_name, _, frag = ref.partition("#")
        doc_name = doc_name or current
        node: Any = self.load(doc_name)
        for part in [p for p in frag.split("/") if p]:
            part = part.replace("~1", "/").replace("~0", "~")
            if not isinstance(node, dict) or part not in node:
                raise KeyError(f"unresolvable $ref '{ref}' in {current}")
            node = node[part]
        return node, doc_name


class Validator:
    def __init__(self, store: SchemaStore) -> None:
        self.store = store

    def validate(self, instance: Any, schema: dict, doc: str, path: str = "") -> list[Error]:
        out: list[Error] = []
        self._v(instance, schema, doc, path, out)
        return out

    def _v(self, x: Any, sch: dict, doc: str, path: str, out: list[Error]) -> None:
        if "$ref" in sch:
            target, tdoc = self.store.resolve(sch["$ref"], doc)
            self._v(x, target, tdoc, path, out)
        if "type" in sch:
            names = sch["type"] if isinstance(sch["type"], list) else [sch["type"]]
            if not any(is_type(x, n) for n in names):
                out.append((path, f"expected {'/'.join(names)}, got {canon(x)[:60]}"))
                return
        if "const" in sch and canon(x) != canon(sch["const"]):
            out.append((path, f"must equal {canon(sch['const'])}, got {canon(x)[:60]}"))
        if "enum" in sch and canon(x) not in {canon(e) for e in sch["enum"]}:
            out.append((path, f"{canon(x)[:60]} is not one of {[e for e in sch['enum']]}"))
        if is_type(x, "number"):
            self._num(x, sch, path, out)
        if isinstance(x, str):
            self._str(x, sch, path, out)
        if isinstance(x, list):
            self._arr(x, sch, doc, path, out)
        if isinstance(x, dict):
            self._obj(x, sch, doc, path, out)
        for key, need in (("oneOf", lambda n: n == 1), ("anyOf", lambda n: n >= 1)):
            if key in sch:
                self._combo(x, sch[key], key, need, doc, path, out)

    def _combo(self, x: Any, subs: list, key: str, need: Callable[[int], bool], doc: str, path: str, out: list[Error]) -> None:
        results = [self.validate(x, s, doc, path) for s in subs]
        ok = sum(1 for r in results if not r)
        if not need(ok):
            if ok == 0:
                best = min(results, key=len)
                out.extend(best if best else [(path, f"no {key} branch matched")])
            else:
                out.append((path, f"{ok} {key} branches matched (exactly one required)"))

    @staticmethod
    def _num(x: float, sch: dict, path: str, out: list[Error]) -> None:
        if "minimum" in sch and x < sch["minimum"]:
            out.append((path, f"{x} < minimum {sch['minimum']}"))
        if "maximum" in sch and x > sch["maximum"]:
            out.append((path, f"{x} > maximum {sch['maximum']}"))
        if "exclusiveMinimum" in sch and x <= sch["exclusiveMinimum"]:
            out.append((path, f"{x} <= exclusiveMinimum {sch['exclusiveMinimum']}"))
        if "exclusiveMaximum" in sch and x >= sch["exclusiveMaximum"]:
            out.append((path, f"{x} >= exclusiveMaximum {sch['exclusiveMaximum']}"))

    @staticmethod
    def _str(x: str, sch: dict, path: str, out: list[Error]) -> None:
        if "pattern" in sch and not re.search(sch["pattern"], x):
            out.append((path, f"'{x}' does not match {sch['pattern']}"))
        if "minLength" in sch and len(x) < sch["minLength"]:
            out.append((path, f"string shorter than {sch['minLength']}"))
        if "maxLength" in sch and len(x) > sch["maxLength"]:
            out.append((path, f"string longer than {sch['maxLength']}"))

    def _arr(self, x: list, sch: dict, doc: str, path: str, out: list[Error]) -> None:
        if "minItems" in sch and len(x) < sch["minItems"]:
            out.append((path, f"{len(x)} items < minItems {sch['minItems']}"))
        if "maxItems" in sch and len(x) > sch["maxItems"]:
            out.append((path, f"{len(x)} items > maxItems {sch['maxItems']}"))
        if sch.get("uniqueItems") and len({canon(v) for v in x}) != len(x):
            out.append((path, "items are not unique"))
        if "items" in sch:
            for n, v in enumerate(x):
                self._v(v, sch["items"], doc, _ptr(path, n), out)

    def _obj(self, x: dict, sch: dict, doc: str, path: str, out: list[Error]) -> None:
        props = sch.get("properties", {})
        for key in sch.get("required", []):
            if key not in x:
                out.append((path, f"missing required key '{key}'"))
        if "minProperties" in sch and len(x) < sch["minProperties"]:
            out.append((path, f"fewer than {sch['minProperties']} keys"))
        if "maxProperties" in sch and len(x) > sch["maxProperties"]:
            out.append((path, f"more than {sch['maxProperties']} keys"))
        for key, val in x.items():
            sub = _ptr(path, key)
            if "propertyNames" in sch:
                self._v(key, sch["propertyNames"], doc, sub, out)
            if key in props:
                self._v(val, props[key], doc, sub, out)
                continue
            extra = sch.get("additionalProperties", True)
            if extra is False:
                out.append((sub, f"unknown key '{key}'"))
            elif isinstance(extra, dict):
                self._v(val, extra, doc, sub, out)


def check_schema(store: SchemaStore, name: str) -> list[str]:
    """Meta-check one schema file: only supported keywords, every $ref resolves, every `required`
    key is declared when additionalProperties is false, and draft 2020-12 is declared."""
    doc = store.load(name)
    problems: list[str] = []
    if doc.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        problems.append(f"{name}: $schema must be draft 2020-12")
    if doc.get("$id") != name:
        problems.append(f"{name}: $id must equal the file name")

    def walk(node: Any, where: str) -> None:
        if not isinstance(node, dict):
            problems.append(f"{name}{where}: schema must be an object")
            return
        for key, val in node.items():
            here = f"{where}/{key}"
            if key in ANNOTATIONS:
                continue
            if key not in ASSERTIONS:
                problems.append(f"{name}{here}: unsupported keyword '{key}'")
            elif key == "$ref":
                try:
                    store.resolve(val, name)
                except (KeyError, OSError) as exc:
                    problems.append(f"{name}{here}: {exc}")
            elif key in ("properties", "$defs"):
                for k, v in val.items():
                    walk(v, f"{here}/{k}")
            elif key in ("items", "propertyNames") or (key == "additionalProperties" and isinstance(val, dict)):
                walk(val, here)
            elif key in ("oneOf", "anyOf"):
                for n, v in enumerate(val):
                    walk(v, f"{here}/{n}")
            elif key == "type":
                for t in val if isinstance(val, list) else [val]:
                    if t not in TYPES:
                        problems.append(f"{name}{here}: unknown type '{t}'")
        if node.get("additionalProperties") is False:
            missing = [r for r in node.get("required", []) if r not in node.get("properties", {})]
            if missing:
                problems.append(f"{name}{where}: required keys not declared in properties: {missing}")

    walk(doc, "")
    return problems
