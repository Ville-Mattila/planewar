"""Shared helpers for tools/check_deps.py: violations, GDScript line scanner, project context."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

CLASS_RE = re.compile(r"^\s*class_name\s+(\w+)")


@dataclass(frozen=True)
class Violation:
    path: str  # repo-relative, forward slashes
    line: int
    rule: str  # "D1".."D10"
    msg: str
    warning: bool = False

    def format(self) -> str:
        kind = "warning: " if self.warning else ""
        return f"{self.path}:{self.line}: {self.rule} {kind}{self.msg}"


@dataclass(frozen=True)
class Line:
    no: int
    code: str  # comments removed, string contents blanked ("")
    text: str  # comments removed, strings intact
    strs: tuple[str, ...]  # string literal contents on this line


def scan(text: str) -> list[Line]:
    """Split GDScript into lines with comments and string contents separated out."""
    out: list[Line] = []
    triple = ""  # active triple-quote delimiter across lines
    for no, raw in enumerate(text.splitlines(), 1):
        code: list[str] = []
        txt: list[str] = []
        strs: list[str] = []
        cur: list[str] = []
        quote = triple
        i = 0
        n = len(raw)
        while i < n:
            c = raw[i]
            if quote:
                if c == "\\" and quote in ('"', "'"):
                    cur.append(raw[i : i + 2])
                    txt.append(raw[i : i + 2])
                    i += 2
                    continue
                if raw.startswith(quote, i):
                    strs.append("".join(cur))
                    cur = []
                    code.append(quote)
                    txt.append(quote)
                    i += len(quote)
                    quote = ""
                    triple = ""
                    continue
                cur.append(c)
                txt.append(c)
                i += 1
                continue
            if c == "#":
                break
            if c in ('"', "'"):
                quote = c * 3 if raw.startswith(c * 3, i) else c
                if len(quote) == 3:
                    triple = quote
                code.append(quote)
                txt.append(quote)
                i += len(quote)
                continue
            code.append(c)
            txt.append(c)
            i += 1
        if quote and len(quote) == 3:
            strs.append("".join(cur))
        out.append(Line(no, "".join(code), "".join(txt), tuple(strs)))
    return out


def parse_project(path: Path) -> dict[str, dict[str, tuple[int, str]]]:
    """Parse project.godot into {section: {key: (line, raw_value)}}."""
    sections: dict[str, dict[str, tuple[int, str]]] = {}
    if not path.is_file():
        return sections
    cur = ""
    for no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        s = raw.strip()
        if not s or s.startswith(";"):
            continue
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1]
            sections.setdefault(cur, {})
        elif "=" in s:
            key, _, val = s.partition("=")
            val = re.split(r"\s;", val, maxsplit=1)[0].strip()
            sections.setdefault(cur, {})[key.strip()] = (no, val)
    return sections


@dataclass
class Context:
    root: Path
    cfg: dict
    project: dict
    class_module: dict[str, str] = field(default_factory=dict)  # class/autoload name -> module
    path_class: dict[str, str] = field(default_factory=dict)  # "src/x/y.gd" -> class name
    autoload_files: set[str] = field(default_factory=set)  # "src/core/log.gd" (godot-relative)
    modules: dict = field(default_factory=dict)
    src_dir: Path = field(default=Path())

    def rel(self, p: Path) -> str:
        return p.resolve().relative_to(self.root.resolve()).as_posix()

    def src_rel(self, p: Path) -> str:
        """Path relative to godot/ (e.g. src/sim/x.gd)."""
        return p.resolve().relative_to((self.root / "godot").resolve()).as_posix()


def module_of(src_rel: str) -> str | None:
    parts = src_rel.split("/")
    if len(parts) >= 3 and parts[0] == "src":
        return parts[1]
    return None


def build_context(root: Path) -> Context:
    cfg = json.loads((root / "tools" / "deps.json").read_text(encoding="utf-8"))
    project = parse_project(root / "godot" / "project.godot")
    ctx = Context(root=root, cfg=cfg, project=project, modules=cfg["modules"], src_dir=root / "godot" / "src")
    for name, (_, val) in project.get("autoload", {}).items():
        m = re.search(r'res://([^"]+)', val)
        if m:
            ctx.autoload_files.add(m.group(1))
            mod = module_of(m.group(1))
            if mod:
                ctx.class_module[name] = mod
                ctx.path_class[m.group(1)] = name
    if ctx.src_dir.is_dir():
        for gd in sorted(ctx.src_dir.rglob("*.gd")):
            rel = ctx.src_rel(gd)
            mod = module_of(rel)
            if not mod:
                continue
            for ln in scan(gd.read_text(encoding="utf-8", errors="replace")):
                m = CLASS_RE.match(ln.code)
                if m:
                    ctx.class_module.setdefault(m.group(1), mod)
                    ctx.path_class[rel] = m.group(1)
                    break
    return ctx
