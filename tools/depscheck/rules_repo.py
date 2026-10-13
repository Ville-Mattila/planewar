"""Repo-level rules D4, D5 (directories), D8, D10 for check_deps.py."""

from __future__ import annotations

import re
from pathlib import Path

from .source import Context, Violation

TEST_ROOTS = ("godot/test", "tools/tests")


def check_autoloads(ctx: Context) -> list[Violation]:
    """D4: [autoload] holds exactly Log, ContentDB, App."""
    sect = ctx.project.get("autoload", {})
    want = set(ctx.cfg["autoloads"])
    out = []
    for name, (no, _) in sect.items():
        if name not in want:
            out.append(Violation("godot/project.godot", no, "D4", f"autoload '{name}' is not allowed (only {', '.join(sorted(want))})"))
    for name in sorted(want - set(sect)):
        out.append(Violation("godot/project.godot", 1, "D4", f"autoload '{name}' is missing"))
    return out


def check_addons(ctx: Context) -> list[Violation]:
    """D5: godot/addons holds only the allowlisted addons."""
    base = ctx.root / "godot" / "addons"
    if not base.is_dir():
        return []
    return [
        Violation(f"godot/addons/{d.name}", 1, "D5", f"addon '{d.name}' is not on the allowlist ({', '.join(ctx.cfg['addons'])})")
        for d in sorted(base.iterdir())
        if d.is_dir() and d.name not in ctx.cfg["addons"]
    ]


def check_warning_config(ctx: Context) -> list[Violation]:
    """D8: the warning keys of docs/03 s1.1 are all 2 in project.godot."""
    dbg = ctx.project.get("debug", {})
    out = []
    enable = dbg.get("gdscript/warnings/enable")
    if enable is None or enable[1] != "true":
        out.append(Violation("godot/project.godot", enable[0] if enable else 1, "D8", "gdscript/warnings/enable must be true"))
    for key in ctx.cfg["warning_keys"]:
        full = f"gdscript/warnings/{key}"
        got = dbg.get(full)
        if got is None:
            out.append(Violation("godot/project.godot", 1, "D8", f"{full} missing (must be 2)"))
        elif got[1] != "2":
            out.append(Violation("godot/project.godot", got[0], "D8", f"{full}={got[1]} (must be 2)"))
    return out


def _test_section(text: str) -> tuple[int, list[str]]:
    """Return (heading line, lines) of the 'Test entry points' section of a MODULE.md."""
    lines = text.splitlines()
    start = -1
    for i, ln in enumerate(lines):
        if re.match(r"#{1,6}\s*test entry points", ln.strip(), re.I) or re.match(r"\*\*test entry points\.?\*\*", ln.strip(), re.I):
            start = i
            break
    if start < 0:
        return 0, []
    body = [lines[start]]
    for ln in lines[start + 1:]:
        if re.match(r"#{1,6}\s", ln):
            break
        body.append(ln)
    return start + 1, body


def _exists(root: Path, token: str) -> bool:
    t = token.strip().strip("`").replace("res://", "godot/")
    if "/" not in t:
        return any(any(root.joinpath(r).rglob(t)) for r in TEST_ROOTS if root.joinpath(r).is_dir())
    cands = [t] if t.startswith(("godot/", "tools/")) else [f"godot/{t}"]
    for c in cands:
        if any(root.glob(c)) if "*" in c else root.joinpath(c).exists():
            return True
    return False


def check_module_tests(ctx: Context, module_md: Path) -> list[Violation]:
    """D10: every path under 'Test entry points' of a MODULE.md exists on disk."""
    rel = ctx.rel(module_md)
    heading, body = _test_section(module_md.read_text(encoding="utf-8"))
    if not heading:
        return [Violation(rel, 1, "D10", "no 'Test entry points' section")]
    out = []
    checked = 0
    for off, ln in enumerate(body):
        for tok in re.findall(r"`([^`]+)`", ln):
            pathlike = "/" in tok or re.search(r"\.(gd|py|json|tscn)$", tok)
            if not pathlike or " " in tok:
                continue
            checked += 1
            if not _exists(ctx.root, tok):
                out.append(Violation(rel, heading + off, "D10", f"test entry point '{tok}' does not exist"))
    if checked == 0:
        out.append(Violation(rel, heading, "D10", "section lists no test entry points (paths in backticks)"))
    return out


def check_module_docs(ctx: Context) -> list[Violation]:
    out = []
    if ctx.src_dir.is_dir():
        for md in sorted(ctx.src_dir.glob("*/MODULE.md")):
            out += check_module_tests(ctx, md)
    return out
