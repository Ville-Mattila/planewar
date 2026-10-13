#!/usr/bin/env python3
"""MODULE.md signature drift detector (TA-27; 03 s15.1, ADR-14 (01:588)).

Compares the "Public API" section of every godot/src/<module>/MODULE.md with the public top-level
declarations in that module's GDScript: class_name (and extends), func / static func, signal, const,
var / static var, enum. Names starting with `_` are private (except `_init`, which may be documented).
Stdlib only.

Usage:  python tools/gen_module_api.py --check [--root DIR] [--module NAME ...]
Exit:   0 no drift, 1 drift (every finding printed as `file:line: GMA-x message`), 2 usage error.

Finding codes:
  GMA-1  documented class not found in code (and not marked planned)
  GMA-2  documented member not found in code (and not planned)
  GMA-3  documented member differs from code (signature, type, extends, enum body, static-ness)
  GMA-4  public class or member in code but absent from Public API
  GMA-5  unparseable line in a Public API code block

Planned-API markers (so planned-but-unimplemented API does not fail; see docs/templates/MODULE.md.template):
  * `[planned]`, `[planned: TA-12]` or `[owner-task: TA-12]` in the comment of a line marks every
    statement on that line as planned. On a `class_name` line it marks the whole class.
  * A comment line `# planned: A, B, C` inside the code block marks those classes planned.
  * Planned means "may be absent from the code". Once the code has the symbol it is compared like
    any other, so the marker should be deleted when the task lands (a stale marker is not an error).

Autoloads have no class_name: write `# autoload: godot/src/<module>/<file>.gd ...` (or a bare
`Log` line) before their members; the `# planned:` directive accepts the autoload name.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MARKER_RE = re.compile(r"\[(?:planned|owner-task)\b[^\]]*\]")
PLANNED_DIRECTIVE_RE = re.compile(r"^\s*planned\s*:\s*(.+)$")
AUTOLOAD_COMMENT_RE = re.compile(r"autoload:\s*(\S+\.gd)")
IDENT = r"[A-Za-z_]\w*"
SKIP_DIRS = frozenset({"fixture", "fixtures"})


@dataclass
class Member:
    kind: str  # func | signal | const | var | enum
    name: str
    line: int
    static: bool = False
    params: tuple | None = None  # tuple of (name, type|None, default|None)
    ret: str | None = None
    vtype: str | None = None
    body: tuple | None = None  # enum members as (name, value|None)
    planned: bool = False


@dataclass
class ClassInfo:
    name: str
    file: str
    line: int
    extends: str | None = None
    members: dict[tuple[str, str], Member] = field(default_factory=dict)
    planned: bool = False


# --------------------------------------------------------------------------- lexing helpers


def split_comment(line: str) -> tuple[str, str]:
    """Split `line` into (code, comment) honouring quoted strings."""
    quote = ""
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 1
            elif ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i], line[i + 1 :]
        i += 1
    return line, ""


def depth_delta(code: str) -> int:
    d, quote, i = 0, "", 0
    while i < len(code):
        ch = code[i]
        if quote:
            if ch == "\\":
                i += 1
            elif ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch in "([{":
            d += 1
        elif ch in ")]}":
            d -= 1
        i += 1
    return d


def split_top(text: str, sep: str) -> list[str]:
    """Split on `sep` (one char) outside brackets and strings."""
    out, cur, d, quote, i = [], [], 0, "", 0
    while i < len(text):
        ch = text[i]
        if quote:
            cur.append(ch)
            if ch == "\\" and i + 1 < len(text):
                i += 1
                cur.append(text[i])
            elif ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch in "([{":
            d += 1
            cur.append(ch)
        elif ch in ")]}":
            d -= 1
            cur.append(ch)
        elif ch == sep and d == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    out.append("".join(cur))
    return out


def norm(s: str | None) -> str | None:
    return None if s is None else re.sub(r"\s+", " ", s.strip())


# --------------------------------------------------------------------------- statement parsing


def parse_params(text: str) -> tuple:
    params = []
    for raw in split_top(text, ","):
        raw = raw.strip()
        if not raw:
            continue
        m = re.match(rf"^({IDENT})\s*(?::\s*([^=]+?))?\s*(?::?=\s*(.+))?$", raw)
        if not m:
            raise ValueError(f"bad parameter '{raw}'")
        params.append((m.group(1), norm(m.group(2)), norm(m.group(3))))
    return tuple(params)


def parse_statement(stmt: str, line: int) -> tuple[str, object]:
    """Return (tag, payload). Tags: class (name, extends), member (Member), extends (str), none."""
    s = stmt.strip()
    s = re.sub(r"^(?:@\w+(?:\([^)]*\))?\s+)+", "", s)  # drop @export / @onready annotations
    m = re.match(rf"^class_name\s+({IDENT})(?:\s+extends\s+(\S+))?$", s)
    if m:
        return "class", (m.group(1), m.group(2))
    m = re.match(r"^extends\s+(\S+)$", s)
    if m:
        return "extends", m.group(1)
    m = re.match(rf"^(static\s+)?func\s+({IDENT})\s*\(", s)
    if m:
        start = m.end() - 1
        d, i = 0, start
        while i < len(s):
            d += {"(": 1, ")": -1}.get(s[i], 0)
            if d == 0:
                break
            i += 1
        if d != 0:
            raise ValueError("unbalanced parentheses in func")
        params = parse_params(s[start + 1 : i])
        rest = s[i + 1 :]
        mr = re.match(r"^\s*(?:->\s*([^:]+?))?\s*(?::.*)?$", rest)
        if not mr:
            raise ValueError("bad return clause")
        return "member", Member("func", m.group(2), line, bool(m.group(1)), params, norm(mr.group(1)))
    m = re.match(rf"^signal\s+({IDENT})\s*(?:\((.*)\))?$", s)
    if m:
        return "member", Member("signal", m.group(1), line, params=parse_params(m.group(2) or ""))
    m = re.match(rf"^(?:(static)\s+)?(var|const)\s+({IDENT})\s*(?::\s*([^=]+?))?\s*(?::?=.*)?$", s)
    if m:
        return "member", Member(m.group(2), m.group(3), line, bool(m.group(1)), vtype=norm(m.group(4)))
    m = re.match(rf"^enum\s+({IDENT})\s*\{{(.*)\}}$", s)
    if m:
        body = []
        for item in split_top(m.group(2), ","):
            item = item.strip()
            if item:
                name, _, val = item.partition("=")
                body.append((name.strip(), norm(val) if val else None))
        return "member", Member("enum", m.group(1), line, body=tuple(body))
    if re.match(r"^enum\s*\{", s) or re.match(r"^(?:@\w+\s*)+$", s) or s.startswith("class "):
        return "none", None
    raise ValueError(f"cannot parse '{s[:60]}'")


# --------------------------------------------------------------------------- code side


def logical_lines(lines: list[str], top_only: bool):
    """Yield (lineno, code, comment) joining bracket-continued lines; `top_only` drops indented lines."""
    i = 0
    while i < len(lines):
        raw = lines[i].rstrip("\n")
        code, comment = split_comment(raw)
        start = i + 1
        if top_only and (raw[:1] in (" ", "\t") or not code.strip()):
            i += 1
            continue
        d = depth_delta(code)
        text = code.strip() if not top_only else code.rstrip()
        while d > 0 and i + 1 < len(lines):
            i += 1
            c2, cm2 = split_comment(lines[i].rstrip("\n"))
            text += " " + c2.strip()
            comment += " " + cm2
            d += depth_delta(c2)
        yield start, text.strip(), comment
        i += 1


def parse_gd(path: Path, rel: str) -> tuple[ClassInfo | None, list[str]]:
    """Parse the public top-level surface of a .gd file. Returns (class or None, problems)."""
    problems: list[str] = []
    info: ClassInfo | None = None
    extends: str | None = None
    anon = ClassInfo(path.stem, rel, 1)
    lines = path.read_text(encoding="utf-8").splitlines()
    for lineno, code, _ in logical_lines(lines, top_only=True):
        if not code:
            continue
        try:
            tag, payload = parse_statement(code, lineno)
        except ValueError as e:
            problems.append(f"{rel}:{lineno}: GMA-5 {e}")
            continue
        if tag == "class":
            name, ext = payload  # type: ignore[misc]
            info = ClassInfo(name, rel, lineno, ext)
        elif tag == "extends":
            extends = payload  # type: ignore[assignment]
        elif tag == "member":
            mem: Member = payload  # type: ignore[assignment]
            if mem.name.startswith("_") and mem.name != "_init":
                continue
            anon.members[(mem.kind, mem.name)] = mem
    target = info or anon
    target.members = anon.members
    if target.extends is None:
        target.extends = extends
    return (info, problems) if info else (anon, problems)


def autoloads(root: Path) -> dict[str, str]:
    """Return {autoload name: repo-relative .gd path} from godot/project.godot."""
    proj = root / "godot" / "project.godot"
    out: dict[str, str] = {}
    if not proj.is_file():
        return out
    in_section = False
    for line in proj.read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            in_section = line.strip() == "[autoload]"
        elif in_section:
            m = re.match(r'^(\w+)="\*?res://(.+\.gd)"', line)
            if m:
                out[m.group(1)] = "godot/" + m.group(2)
    return out


# --------------------------------------------------------------------------- doc side


def public_api_blocks(md: Path):
    """Yield (lineno, text) for every line inside code fences of the '## Public API' section."""
    in_api = in_fence = False
    for n, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith("## "):
            in_api = line.strip() == "## Public API"
            in_fence = False
        elif in_api and line.startswith("```"):
            in_fence = not in_fence
        elif in_api and in_fence:
            yield n, line


def parse_doc(md: Path, rel: str, auto: dict[str, str]):
    """Return (doc classes keyed by class name or autoload path, problems, planned names)."""
    classes: dict[str, ClassInfo] = {}
    problems: list[str] = []
    planned_names: set[str] = set()
    cur: ClassInfo | None = None
    block = list(public_api_blocks(md))
    lines = [t for _, t in block]
    nums = [n for n, _ in block]
    auto_by_name = auto

    def start(key: str, line: int, planned: bool, ext: str | None = None) -> ClassInfo:
        c = classes.get(key) or ClassInfo(key, rel, line, ext)
        c.planned = c.planned or planned
        classes[key] = c
        return c

    for idx, code, comment in logical_lines(lines, top_only=False):
        lineno = nums[idx - 1]
        stripped = comment.strip()
        d = PLANNED_DIRECTIVE_RE.match(stripped)
        if d and not code:
            planned_names.update(x.strip() for x in re.split(r"[,\s]+", d.group(1)) if x.strip())
            continue
        a = AUTOLOAD_COMMENT_RE.search(comment) if re.match(r"^\s*autoload:", comment) else None
        if a and not code:
            cur = start(a.group(1), lineno, False)
            continue
        if not code:
            continue
        planned = bool(MARKER_RE.search(comment))
        text = re.sub(r"\s\.\.\s", ";", code)  # "const A: int .. const B: int" lists both
        for stmt in split_top(text, ";"):
            stmt = stmt.strip()
            if not stmt:
                continue
            if re.match(rf"^{IDENT}$", stmt):  # bare autoload name, e.g. `Log`
                cur = start(stmt, lineno, planned)
                continue
            try:
                tag, payload = parse_statement(stmt, lineno)
            except ValueError as e:
                problems.append(f"{rel}:{lineno}: GMA-5 {e}")
                continue
            if tag == "class":
                name, ext = payload  # type: ignore[misc]
                cur = start(name, lineno, planned, ext)
                cur.extends = ext
            elif tag == "member":
                mem: Member = payload  # type: ignore[assignment]
                mem.planned = planned
                if cur is None:
                    problems.append(f"{rel}:{lineno}: GMA-5 member '{mem.name}' before any class_name or autoload line")
                else:
                    cur.members[(mem.kind, mem.name)] = mem
    for key, c in classes.items():
        base = Path(key).stem if key.endswith(".gd") else key
        if key in planned_names or base in planned_names:
            c.planned = True
        for alias, path in auto_by_name.items():
            if alias in planned_names and path == key.replace("\\", "/"):
                c.planned = True
    return classes, problems


# --------------------------------------------------------------------------- comparison


def describe(m: Member) -> str:
    if m.kind in ("func", "signal"):
        ps = ", ".join(n + (f": {t}" if t else "") + (f" = {d}" if d else "") for n, t, d in m.params or ())
        return f"{m.kind} {m.name}({ps})" + (f" -> {m.ret}" if m.ret else "")
    if m.kind == "enum":
        return f"enum {m.name} {{{', '.join(n for n, _ in m.body or ())}}}"
    return f"{m.kind} {m.name}" + (f": {m.vtype}" if m.vtype else "")


def diff_member(doc: Member, code: Member) -> str | None:
    if doc.kind in ("func", "signal"):
        if doc.static != code.static:
            return f"static-ness differs (doc {'static' if doc.static else 'instance'}, code {'static' if code.static else 'instance'})"
        dp, cp = doc.params or (), code.params or ()
        if len(dp) != len(cp) or any(a[0].lstrip("_") != b[0].lstrip("_") for a, b in zip(dp, cp)):
            return "parameter names differ"
        for a, b in zip(dp, cp):
            if a[1] and b[1] and a[1] != b[1] and b[1] != a[1] + "Fixture":  # interim typed stand-in
                return f"parameter '{a[0]}' type differs (doc {a[1]}, code {b[1]})"
            if (a[2] is None) != (b[2] is None):
                return f"parameter '{a[0]}' default differs (doc {a[2]}, code {b[2]})"
            if a[2] and b[2] and a[2] != b[2]:
                return f"parameter '{a[0]}' default differs (doc {a[2]}, code {b[2]})"
        if doc.kind == "func" and (doc.ret or "void") != (code.ret or "void"):
            return f"return type differs (doc {doc.ret or 'void'}, code {code.ret or 'void'})"
        return None
    if doc.kind in ("var", "const"):
        if doc.kind == "var" and doc.static != code.static:
            return "static-ness differs"
        if doc.vtype and code.vtype and doc.vtype != code.vtype:
            return f"type differs (doc {doc.vtype}, code {code.vtype})"
        return None
    if doc.kind == "enum":
        dn = [n for n, _ in doc.body or ()]
        cn = [n for n, _ in code.body or ()]
        if dn != cn:
            return f"enum members differ (doc {dn}, code {cn}); enums are append-only with frozen ordinals"
        for (n, dv), (_, cv) in zip(doc.body or (), code.body or ()):
            if dv and cv and dv != cv:
                return f"enum value of {n} differs (doc {dv}, code {cv})"
    return None


def documented_ancestor_member(doc: dict, d: ClassInfo, mkey: tuple[str, str]) -> Member | None:
    """Find mkey on the documented parent chain of class `d` (doc classes keyed by name)."""
    seen: set[str] = set()
    ext = d.extends
    while ext and ext not in seen and ext in doc:
        seen.add(ext)
        if mkey in doc[ext].members:
            return doc[ext].members[mkey]
        ext = doc[ext].extends
    return None


def compare_module(module: str, root: Path) -> list[str]:
    src = root / "godot" / "src" / module
    md = src / "MODULE.md"
    mrel = md.relative_to(root).as_posix()
    auto = autoloads(root)
    findings: list[str] = []

    code_by_name: dict[str, ClassInfo] = {}
    code_by_path: dict[str, ClassInfo] = {}
    nested = [p.parent for p in src.rglob("MODULE.md") if p.parent != src]   # sub-modules (R0 B.9 A-21) have their own MODULE.md
    for gd in sorted(src.rglob("*.gd")):
        if any(n in gd.parents for n in nested):
            continue
        rel = gd.relative_to(root).as_posix()
        info, problems = parse_gd(gd, rel)
        findings += problems
        if info is None:
            continue
        code_by_path[rel] = info
        is_autoload = rel in auto.values()
        if not is_autoload and any(p.name == "fixture" for p in gd.parents if p != src):
            continue
        if is_autoload:
            for name, path in auto.items():
                if path == rel:
                    code_by_name[name] = info
        else:
            code_by_name[info.name] = info
        info.planned = False
    skip_undoc = {i.file for i in code_by_path.values() if any(part in SKIP_DIRS for part in Path(i.file).parts)}

    doc, problems = parse_doc(md, mrel, auto)
    findings += problems
    matched: set[int] = set()
    for key, d in doc.items():
        code = code_by_path.get(key) if key.endswith(".gd") else code_by_name.get(key)
        label = Path(key).stem if key.endswith(".gd") else key
        if code is None:
            if not d.planned:
                findings.append(f"{mrel}:{d.line}: GMA-1 class '{label}' is documented but not found in godot/src/{module}/ (add `[planned]` if it is not implemented yet)")
            continue
        matched.add(id(code))
        if d.extends and code.extends and d.extends != code.extends:
            findings.append(f"{mrel}:{d.line}: GMA-3 class '{label}' extends {d.extends} in the doc, {code.extends} in {code.file}:{code.line}")
        for mkey, dm in d.members.items():
            cm = code.members.get(mkey)
            if cm is None:
                if dm.planned or d.planned:
                    continue
                findings.append(f"{mrel}:{dm.line}: GMA-2 {label}: documented `{describe(dm)}` not found in {code.file}")
                continue
            why = diff_member(dm, cm)
            if why:
                findings.append(f"{mrel}:{dm.line}: GMA-3 {label}.{dm.name}: {why}; code {code.file}:{cm.line} has `{describe(cm)}`")
        for mkey, cm in code.members.items():
            if mkey[1] == "_init" or mkey in d.members or cm.kind not in ("func", "signal"):
                continue  # consts / vars / enums may be documented as ranges or in prose; only call signatures must be listed
            parent = documented_ancestor_member(doc, d, mkey)
            if parent is not None:  # an override of a method documented on a documented parent class counts as documented
                why = diff_member(parent, cm)
                if why:
                    findings.append(f"{code.file}:{cm.line}: GMA-3 {label}.{cm.name}: override differs from the documented parent signature: {why}; parent `{describe(parent)}`, code `{describe(cm)}`")
                continue
            findings.append(f"{code.file}:{cm.line}: GMA-4 {label}: public `{describe(cm)}` is not in {mrel} Public API (document it or prefix `_`)")
    for code in code_by_name.values():
        if id(code) in matched or code.file in skip_undoc:
            continue
        findings.append(f"{code.file}:{code.line}: GMA-4 class '{code.name}' is not in {mrel} Public API")
    return findings


def modules(root: Path, only: list[str] | None) -> list[str]:
    src = root / "godot" / "src"
    found = sorted(p.parent.relative_to(src).as_posix() for p in src.rglob("MODULE.md"))
    return [m for m in found if not only or m in only]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="MODULE.md vs GDScript signature drift detector (TA-27).")
    ap.add_argument("--check", action="store_true", help="fail (exit 1) on drift; the only mode")
    ap.add_argument("--root", type=Path, default=REPO, help="repo root (default: this repo)")
    ap.add_argument("--module", action="append", help="limit to a module (repeatable)")
    args = ap.parse_args(argv)
    if not args.check:
        ap.error("--check is required")
    root = args.root.resolve()
    mods = modules(root, args.module)
    if not mods:
        print("gen_module_api: no godot/src/*/MODULE.md found", file=sys.stderr)
        return 2
    total = 0
    for m in mods:
        found = compare_module(m, root)
        total += len(found)
        for f in found:
            print(f)
    if total:
        print(f"gen_module_api: {total} drift finding(s) in {len(mods)} module(s)", file=sys.stderr)
        return 1
    print(f"gen_module_api: OK ({len(mods)} modules: {', '.join(mods)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
