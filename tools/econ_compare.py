"""econ_compare: parse the 02 s8.7-8.9 tables and compare them with an econ_model run (GD-21).

The doc numbers are read from docs/02-game-design.md at run time (never retyped), so a doc revision changes the
comparison without a code change. Tolerances (02 GD-21 acceptance): checkpoints +-5 s; aggregates +-5 % of the doc
value, with an absolute floor so a stock of 6 Ore is not judged at 0.3 Ore (floor 10 for Ore/Ice, 1 for counts/power).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "docs" / "02-game-design.md"
BOOKS = Path(__file__).resolve().parent / "econ_books"
REL = 0.05
FLOOR = {"ore": 10, "ice": 10, "ore_in": 10, "ore_spent": 10, "ice_in": 10, "ice_out": 10, "harvesters": 1, "ships": 1,
         "power_sup": 1, "power_dem": 1}
CHECKPOINT_TOL_S = 5.0


def num(cell: str):
    """'1,260' -> 1260; '0 / 70' and '32/24' -> (a, b); '-' and prose -> None."""
    c = cell.replace("*", "").replace(",", "").strip()
    m = re.fullmatch(r"(-?\d+(?:\.\d+)?)\s*/\s*(-?\d+(?:\.\d+)?)", c)
    if m:
        return float(m.group(1)), float(m.group(2))
    m = re.fullmatch(r"-?\d+(?:\.\d+)?", c)
    return float(c) if m else None


def parse_time(cell: str) -> float | None:
    m = re.search(r"(\d+):(\d{2})", cell.replace("*", ""))
    return int(m.group(1)) * 60 + int(m.group(2)) if m else None


def section(heading_prefix: str, text: str | None = None) -> str:
    text = text if text is not None else DOC.read_text(encoding="utf-8")
    m = re.search(r"^### " + re.escape(heading_prefix) + r".*$", text, re.M)
    if not m:
        raise ValueError(f"02: heading '### {heading_prefix}' not found")
    end = re.search(r"^#{2,3} ", text[m.end():], re.M)
    return text[m.start(): m.end() + (end.start() if end else len(text))]


def tables(sec: str) -> list[list[list[str]]]:
    """Markdown tables of a section as lists of rows of cell strings (header first, separator dropped)."""
    out: list[list[list[str]]] = []
    cur: list[list[str]] = []
    for line in sec.splitlines() + [""]:
        if line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
                continue
            cur.append(cells)
        elif cur:
            out.append(cur)
            cur = []
    return out


def doc_minutes(match: str, text: str | None = None) -> dict[int, dict]:
    """The 8.7 / 8.8 minute-by-minute table as {minute: {column: value}} in the model's column names."""
    sec = section("8.7 " if match == "1v1" else "8.8 ", text)
    tb = [t for t in tables(sec) if t[0][0] == "Min"][0]
    res: dict[int, dict] = {}
    for row in tb[1:]:
        v = [num(c) for c in row]
        i = {"ore": 1, "ice": 2, "harvesters": 3, "ore_in": 4, "ore_spent": 5}
        d = {k: v[j] for k, j in i.items()}
        d["ice_in"], d["ice_out"] = v[6] if isinstance(v[6], tuple) else (None, None)
        d["power_sup"], d["power_dem"] = v[7] if isinstance(v[7], tuple) else (None, None)
        res[int(v[0])] = d
    return res


def doc_windows(match: str, text: str | None = None) -> dict[int, dict]:
    """The 8.9 table of a match, keyed by the window's end minute."""
    sec = section("8.9 ", text)
    tbs = [t for t in tables(sec) if t[0][0] == "Window"]
    tb = tbs[0] if match == "1v1" else tbs[1]
    res: dict[int, dict] = {}
    for row in tb[1:]:
        end = int(row[0].split("-")[1])
        v = [num(c) for c in row]
        res[end] = dict(ore=v[1], ice=v[2], harvesters=v[3], ships=v[4], ore_in=v[5], ore_spent=v[6], ice_in=v[7],
                        ice_out=v[8], power_sup=v[9][0], power_dem=v[9][1])
    return res


def window_of(minutes: list[dict], end: int) -> dict:
    a, b = minutes[end - 1], minutes[end]       # minutes[k] = end of minute k; the window covers minutes end-1, end
    return dict(ore=b["ore"], ice=b["ice"], harvesters=b["harvesters"], ships=b["ships"],
                ore_in=(a["ore_in"] + b["ore_in"]) / 2, ore_spent=(a["ore_spent"] + b["ore_spent"]) / 2,
                ice_in=(a["ice_in"] + b["ice_in"]) / 2, ice_out=(a["ice_out"] + b["ice_out"]) / 2,
                power_sup=b["power"][0], power_dem=b["power"][1])


def within(col: str, doc: float, model: float) -> bool:
    return abs(model - doc) <= max(REL * abs(doc), FLOOR.get(col, 1))


def fmt_t(t: float) -> str:
    return f"{int(t // 60)}:{int(t % 60):02d}"


def _ints(pattern: str, text: str, group_count: int = 1) -> list[float]:
    m = re.search(pattern, text)
    return [float(m.group(i + 1).replace(",", "")) for i in range(group_count)] if m else []


def static_checks(defs, text: str | None = None) -> list[dict]:
    """Closed-form tables straight from the defs: 8.2 trips, 8.3 Hauler cycles, 8.6 storage."""
    rows: list[dict] = []
    h = defs.items["harvester"]
    for row in tables(section("8.2 ", text))[0][1:]:
        d = num(row[0].split("m")[0])
        t = defs.trip_time(d)
        opm = 60 * h["cargo_ore"] / t
        pay = h["cost_ore"] / opm
        for col, doc, mv, tol in (("T_trip", num(row[2].replace("s", "")), t, 0.06), ("Ore/min", num(row[3]), opm, 0.5),
                                  ("payback", num(row[4].split()[0]), pay, 0.06)):
            rows.append(dict(kind="static", name=f"8.2 d={d:g} {col}", doc=doc, model=mv, tol="rounding",
                             ok=abs(mv - doc) <= tol))
    for row in tables(section("8.3 ", text))[0][1:]:
        d = num(row[3].split("m")[0])
        t = defs.haul_cycle(d)
        for col, doc, mv, tol in (("T_h", num(row[4].replace("s", "")), t, 1.0), ("Ice/s", num(row[5].split()[0]), 400 / t, 0.06)):
            rows.append(dict(kind="static", name=f"8.3 d={d:g} {col}", doc=doc, model=mv, tol="rounding",
                             ok=abs(mv - doc) <= tol))
    sec = section("8.6 ", text)
    items = defs.items
    fresh = [sum(items[i].get(k, 0) for i in ("core", "refinery")) for k in ("storage_ore", "storage_ice")]
    typ = [sum(items[i].get(k, 0) * n for i, n in (("core", 1), ("refinery", 2), ("outpost", 1)))
           for k in ("storage_ore", "storage_ice")]
    for name, doc, mv in (("fresh Ore", 4500, fresh[0]), ("fresh Ice", 1300, fresh[1]), ("10:00 Ore", 6250, typ[0]),
                          ("10:00 Ice", 1900, typ[1])):
        rows.append(dict(kind="static", name=f"8.6 {name}", doc=doc, model=mv, tol="exact",
                         ok=f"{doc:,}" in sec and mv == doc))
    return rows


def totals(match: str, sim, text: str | None = None) -> list[dict]:
    """The prose totals: 8.7 'By 10:00' and the 8.9 24-minute totals (structures + units; repair is not modelled)."""
    rows: list[dict] = []
    para = [x for x in section("8.9 ", text).split("\n\n") if x.startswith("24-minute totals")][0 if match == "1v1" else 1]
    ore_in = _ints(r"Ore income ([\d,]+)", para)
    st = _ints(r"on structures ([\d,]+)", para) + _ints(r"units ([\d,]+)", para)
    ice_in = _ints(r"Ice income ([\d,]+)", para)
    ice_out = _ints(r"services ([\d,]+) and builds ([\d,]+)", para, 2)
    m = sim.minutes
    for name, doc, mv in (("24 min Ore income", ore_in[0], sum(x["ore_in"] for x in m)),
                          ("24 min Ore spent (structures+units)", st[0] + st[1], sum(x["ore_spent"] for x in m)),
                          ("24 min Ice income", ice_in[0], sum(x["ice_in"] for x in m)),
                          ("24 min Ice spent (services+builds)", sum(ice_out), sum(x["ice_out"] for x in m))):
        rows.append(dict(kind="total", name=name, doc=doc, model=mv, ok=abs(mv - doc) <= REL * doc, tol="5 %"))
    if match == "1v1":
        mined, spent = _ints(r"mined ([\d,]+) Ore, spent ([\d,]+)", section("8.7 ", text), 2)
        mv_mined = sum(x["ore_in"] for x in m[:11]) - 600
        mv_spent = sum(x["ore_spent"] for x in m[:11])
        rows.append(dict(kind="total", name="by 10:00 Ore mined", doc=mined, model=mv_mined,
                         ok=abs(mv_mined - mined) <= REL * mined, tol="5 %"))
        rows.append(dict(kind="total", name="by 10:00 Ore spent", doc=spent, model=mv_spent,
                         ok=abs(mv_spent - spent) <= REL * spent, tol="5 %"))
    return rows


def power_rows(sim, text: str | None = None) -> list[dict]:
    """8.4 'typical base' supply/demand at the doc's instants (1v1 model)."""
    rows: list[dict] = []
    for row in tables(section("8.4 ", text))[-1][1:]:
        t = parse_time(row[0])
        if t is None:
            continue
        sd = (num(row[1]), num(row[2].split()[0]))
        sup, dem = sim.power_log.get(int(t), (None, None))
        for col, doc, mv in (("supply", sd[0], sup), ("demand", sd[1], dem)):
            rows.append(dict(kind="power", name=f"8.4 {row[0].split()[0]} {col}", doc=doc, model=mv,
                             ok=mv is not None and abs(mv - doc) <= max(REL * doc, 1), tol="5 %"))
    return rows


def compare(match: str, sim, text: str | None = None) -> list[dict]:
    rows: list[dict] = []
    if match == "1v1":
        rows += static_checks(sim.defs, text) + power_rows(sim, text)
    rows += totals(match, sim, text)
    book = json.loads((BOOKS / f"{match}.json").read_text(encoding="utf-8"))
    for cp in book.get("checkpoints", []):
        mt = sim.event_time(cp["event"])
        dt = parse_time(cp["doc"])
        rows.append(dict(kind="checkpoint", name=cp["name"], doc=dt, model=mt,
                         ok=mt is not None and abs(mt - dt) <= CHECKPOINT_TOL_S, tol=f"+-{CHECKPOINT_TOL_S:g} s"))
    for minute, d in doc_minutes(match, text).items():
        if minute >= len(sim.minutes):
            continue
        m = sim.minutes[minute]
        for col, dv in d.items():
            if dv is None or minute == 0:
                continue
            mv = m["power"][0 if col == "power_sup" else 1] if col.startswith("power") else m[col]
            rows.append(dict(kind="minute", name=f"min {minute} {col}", doc=dv, model=mv, ok=within(col, dv, mv),
                             tol="5 %"))
    for end, d in doc_windows(match, text).items():
        if end >= len(sim.minutes):
            continue
        w = window_of(sim.minutes, end)
        for col, dv in d.items():
            rows.append(dict(kind="window", name=f"{end - 2}-{end} {col}", doc=dv, model=w[col], ok=within(col, dv, w[col]),
                             tol="5 %"))
    return rows


def render(match: str, sim, rows: list[dict], minutes: bool, log: bool) -> str:
    out = [f"== {match}: {len(rows)} comparisons, {sum(1 for r in rows if not r['ok'])} outside tolerance =="]
    if minutes:
        out.append("min  ore   ice  harv ships  ore_in ore_spent ice_in ice_out power")
        for m in sim.minutes:
            out.append(f"{m['minute']:>3} {m['ore']:>5} {m['ice']:>5} {m['harvesters']:>4} {m['ships']:>5} {m['ore_in']:>7} "
                       f"{m['ore_spent']:>9} {m['ice_in']:>6} {m['ice_out']:>7} {m['power'][0]}/{m['power'][1]}")
    if log:
        out += [f"{fmt_t(t)}  {lab}" for t, lab in sorted(sim.events)]
    for kind in ("static", "checkpoint", "power", "minute", "window", "total"):
        sel = [r for r in rows if r["kind"] == kind]
        if not sel:
            continue
        bad = [r for r in sel if not r["ok"]]
        out.append(f"-- {kind}: {len(sel) - len(bad)}/{len(sel)} within {sel[0]['tol'] if sel else ''}")
        for r in bad:
            d = fmt_t(r["doc"]) if kind == "checkpoint" else f"{r['doc']:g}"
            m = "never" if r["model"] is None else (fmt_t(r["model"]) if kind == "checkpoint" else f"{r['model']:g}")
            out.append(f"   MISS {r['name']}: doc {d}, model {m}")
    return "\n".join(out)
