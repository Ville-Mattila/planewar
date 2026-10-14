"""Per-file rules D1, D2, D3, D5 (references), D6, D7, D9 for check_deps.py."""

from __future__ import annotations

import re
from pathlib import Path

from .source import CLASS_RE, Context, Line, Violation, module_of, scan

# A-50: a qualified token Foo.Bar references Foo only; a member after a dot is not a type.
IDENT_RE = re.compile(r"(?<![.\w])[A-Z][A-Za-z0-9_]*\b")
RES_SRC_RE = re.compile(r"res://(src|scenes)/([A-Za-z0-9_]+)/([^\"']*)")
D2_PATTERNS = [
    (re.compile(r"\bextends\s+Node\w*"), "extends a Node type"),
    (re.compile(r"\bget_tree\s*\("), "get_tree("),
    (re.compile(r"\bget_node(_or_null)?\s*\("), "get_node("),
    (re.compile(r"\$"), "$ node path"),
    (re.compile(r"\badd_child\s*\("), "add_child("),
    (re.compile(r"\bSignal\b"), "Signal"),
    (re.compile(r"^\s*signal\b"), "signal declaration"),
    (re.compile(r"\bawait\b"), "await"),
]
D3_WORDS = re.compile(r"\b(Thread|WorkerThreadPool|Mutex|Semaphore)\b")
D9_PATTERNS = [
    (re.compile(r"\bOS\.execute\b"), "OS.execute"),
    (re.compile(r"\bJavaScriptBridge\b"), "JavaScriptBridge"),
    (re.compile(r"""FileAccess\.open\(\s*["']/"""), 'FileAccess.open("/'),
]
NUM_RE = r"(?<![\w.])%s(?:\.0*)?(?![\w.])"
FLOAT_RE = re.compile(r"(?<![\w.])(?:\d[\d_]*\.\d*|\.\d+|\d[\d_]*(?=[eE][+-]?\d))(?:[eE][+-]?\d+)?(?![\w.])")
POS_LEN_RE = re.compile(
    r"\b(?:\w*_)?(?:pos|position|len|length|dist|distance|alt|altitude)(?:_\w*)?\b"
    r"|\bp\b|\.length(?:_squared)?\s*\(|\.distance_(?:squared_)?to\s*\("
)


def check_layering(ctx: Context, rel: str, owner: str, lines: list[Line], src_rel: str) -> list[Violation]:
    """D1. `owner` is the module the file belongs to."""
    spec = ctx.modules.get(owner)
    if spec is None:
        return [Violation(rel, 1, "D1", f"unknown module '{owner}' (not in tools/deps.json)")]
    allowed = spec["may_depend_on"]
    named = spec.get("named_types", {})
    named_all = {c for lst in named.values() for c in lst}
    out: list[Violation] = []

    def ok(target: str, cls: str | None) -> bool:
        if target == owner or allowed == "*" or target in allowed:
            return True
        return cls is not None and cls in named_all and cls in named.get(target, [])

    for ln in lines:
        seen: set[str] = set()
        for s in ln.strs:
            m = RES_SRC_RE.search(s)
            if not m:
                continue
            target = m.group(2)
            if target not in ctx.modules:
                continue
            cls = ctx.path_class.get(f"src/{target}/{m.group(3)}") if m.group(1) == "src" else None
            if not ok(target, cls) and target not in seen:
                seen.add(target)
                out.append(Violation(rel, ln.no, "D1", f"{owner} must not depend on {target} (path {s})"))
        for ident in IDENT_RE.findall(ln.code):
            target = ctx.class_module.get(ident)
            if target is None or ident in seen:
                continue
            if not ok(target, ident):
                seen.add(ident)
                out.append(Violation(rel, ln.no, "D1", f"{owner} must not depend on {target} (type {ident})"))
    return out


def check_no_nodes(rel: str, lines: list[Line]) -> list[Violation]:
    out = []
    for ln in lines:
        for pat, what in D2_PATTERNS:
            if pat.search(ln.code):
                out.append(Violation(rel, ln.no, "D2", f"{what} is forbidden in sim/sim_ai/core"))
    return out


def _guarded_by_not_web(lines: list[Line], idx: int) -> bool:
    """True if lines[idx] sits inside a `not OS.has_feature("web")` branch (indentation walk)."""
    def indent(t: str) -> int:
        return len(t) - len(t.lstrip("\t "))

    cur = indent(lines[idx].text)
    for j in range(idx - 1, -1, -1):
        t = lines[j].text
        if not t.strip():
            continue
        ind = indent(t)
        if ind >= cur:
            continue
        cur = ind
        s = t.strip()
        if re.match(r"(if|elif)\b", s) and re.search(r"not\s+OS\.has_feature\(\s*[\"']web[\"']\s*\)", s):
            return True
        if s.startswith("else"):  # else of `if OS.has_feature("web")`
            for k in range(j - 1, -1, -1):
                u = lines[k].text
                if u.strip() and indent(u) == ind:
                    us = u.strip()
                    return bool(re.match(r"(if|elif)\b", us)) and "OS.has_feature(\"web\")" in us and "not " not in us
                if u.strip() and indent(u) < ind:
                    break
    return False


def check_threads(ctx: Context, rel: str, src_rel: str, lines: list[Line]) -> list[Violation]:
    allow = ctx.cfg.get("d3_allowlist", {}).get(src_rel, [])
    out = []
    for idx, ln in enumerate(lines):
        for m in D3_WORDS.finditer(ln.code):
            word = m.group(1)
            if word in allow:
                if not _guarded_by_not_web(lines, idx):
                    out.append(Violation(rel, ln.no, "D3", f'{word} must sit inside a `not OS.has_feature("web")` branch'))
            else:
                out.append(Violation(rel, ln.no, "D3", f"{word} is forbidden (web is single-threaded; ADR-14)"))
    return out


def load_d6_allow(root: Path) -> tuple[set[tuple[str, str]], list[Violation]]:
    path = root / "tools" / "d6_allow.txt"
    entries: set[tuple[str, str]] = set()
    errs: list[Violation] = []
    if not path.is_file():
        return entries, errs
    for no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        spec, _, reason = s.partition(" ")
        fpath, _, lno = spec.rpartition(":")
        if not fpath or not lno or not reason.strip():
            errs.append(Violation("tools/d6_allow.txt", no, "D6", "entry must be '<path>:<line> <reason>'"))
            continue
        if fpath.startswith("godot/"):
            fpath = fpath[len("godot/"):]
        entries.add((fpath, lno))
    return entries, errs


def check_literals(ctx: Context, rel: str, src_rel: str, lines: list[Line], allow: set[tuple[str, str]]) -> list[Violation]:
    d6 = ctx.cfg["d6"]
    if src_rel in d6["exempt_files"]:
        return []
    err_scope = any(src_rel.startswith(p) for p in d6["error_scopes"])
    float_scope = src_rel.startswith(d6["float_scope"])
    lit_res = [re.compile(NUM_RE % re.escape(lit)) for lit in d6["literals"]]
    ok_floats = set(d6["allowed_floats"])
    out: list[Violation] = []
    for ln in lines:
        hit = False
        for rx in lit_res:
            m = rx.search(ln.code)
            if not m:
                continue
            hit = True
            if err_scope and POS_LEN_RE.search(ln.code):
                out.append(Violation(rel, ln.no, "D6", f"literal {m.group(0)} in an expression with a position/length variable; use Sphere.PLANET_RADIUS"))
            elif (src_rel, str(ln.no)) not in allow and (src_rel, "*") not in allow:
                out.append(Violation(rel, ln.no, "D6", f"literal {m.group(0)}; derive from Sphere.PLANET_RADIUS or list in tools/d6_allow.txt", warning=True))
        if hit or not float_scope or re.search(r"\b(PI|TAU)\b", ln.code):
            continue
        if (src_rel, str(ln.no)) in allow or (src_rel, "*") in allow:
            continue
        for fm in FLOAT_RE.finditer(ln.code):
            try:
                val = float(fm.group(0).replace("_", ""))
            except ValueError:
                continue
            if val not in ok_floats:
                out.append(Violation(rel, ln.no, "D6", f"float literal {fm.group(0)} in sim; numbers belong in content/defs (ADR-09)", warning=True))
                break
    return out


def check_file_shape(ctx: Context, rel: str, src_rel: str, text: str, lines: list[Line]) -> list[Violation]:
    """D7."""
    out: list[Violation] = []
    n = len(text.splitlines())
    limit = ctx.cfg["max_file_lines"]
    if n > limit:
        out.append(Violation(rel, limit + 1, "D7", f"file has {n} lines (max {limit})"))
    if src_rel in ctx.autoload_files:
        return out
    names = [(ln.no, m.group(1)) for ln in lines if (m := CLASS_RE.match(ln.code))]
    if not names:
        out.append(Violation(rel, 1, "D7", "class_name missing"))
    for no, name in names[1:]:
        out.append(Violation(rel, no, "D7", f"more than one class_name in file ({name})"))
    return out


def check_web_safety(ctx: Context, rel: str, src_rel: str, lines: list[Line]) -> list[Violation]:
    """D9."""
    if src_rel.startswith(ctx.cfg["d9_exempt_prefix"]):
        return []
    out = []
    for ln in lines:
        for pat, what in D9_PATTERNS:
            if pat.search(ln.text if "open" in what else ln.code):
                out.append(Violation(rel, ln.no, "D9", f"{what} outside src/platform/"))
    return out


def check_addon_refs(ctx: Context, rel: str, lines: list[Line]) -> list[Violation]:
    """D5 (reference half)."""
    if any(rel.startswith(p) for p in ctx.cfg["addon_ref_allowed"]):
        return []
    return [
        Violation(rel, ln.no, "D5", "res://addons/ reference outside test/ and platform/")
        for ln in lines
        if any("res://addons/" in s for s in ln.strs)
    ]


def check_gd(ctx: Context, path: Path, allow: set[tuple[str, str]]) -> list[Violation]:
    rel = ctx.rel(path)
    src_rel = ctx.src_rel(path)
    owner = module_of(src_rel)
    if owner is None:
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = scan(text)
    out = check_layering(ctx, rel, owner, lines, src_rel)
    if owner in ctx.cfg["no_nodes_modules"] and src_rel not in ctx.autoload_files:
        out += check_no_nodes(rel, lines)
    out += check_threads(ctx, rel, src_rel, lines)
    out += check_literals(ctx, rel, src_rel, lines, allow)
    out += check_file_shape(ctx, rel, src_rel, text, lines)
    out += check_web_safety(ctx, rel, src_rel, lines)
    out += check_addon_refs(ctx, rel, lines)
    return out


def check_tscn(ctx: Context, path: Path) -> list[Violation]:
    """D1 (scene script/resource paths) and D5 references for .tscn files."""
    rel = ctx.rel(path)
    parts = path.resolve().relative_to((ctx.root / "godot").resolve()).parts
    lines = []
    for no, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        lines.append(Line(no, "", raw, tuple(re.findall(r'"(res://[^"]*)"', raw))))
    out = check_addon_refs(ctx, rel, lines)
    if len(parts) >= 3 and parts[0] == "scenes" and parts[1] in ctx.modules:
        out += check_layering(ctx, rel, parts[1], lines, "")
    return out
