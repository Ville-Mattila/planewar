#!/usr/bin/env python3
"""Validate content JSON against tools/schemas/ (03 s9, ADR-09). Stdlib only (see schemalite.py).

CONTRACT-0 scope: meta-check every schema; validate godot/content/defs/*.json and
godot/content/maps/*/recipe.json against their schemas; validate every docs/examples/**/*.json
through tools/doc_example_schemas.json; a few cross-file rules the schemas cannot express
(unique ids, a_thrust >= 2 g, weapon range_min_m < range_m, bot profile cadence == its promise or the
normal cadence for Adjutant profiles, unique recipe feature ids). R0 B.8 (amendments 01) names the rules.
TA-08 adds dangling-reference checks between def files and the content hash (tools/content_hash.py, 03 s9.2).
R0 B.9 (amendments 02) adds: modes `pause_scope` / `caps_web_mobile` consistency with `hosting`, promise
locale keys `promise.<id>.audience` / `.human_target`, a `launch_pad` structure has no service pads.

Usage:
    python tools/validate_content.py [--root DIR] [--print-hash]

--print-hash prints only the content hash of godot/content/defs (rules: tools/content_hash.py).

Exit codes: 0 ok, 1 violations, 2 I/O or usage error. Output: one "<path>:<pointer>: <message>"
line per violation, then a summary line.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from content_hash import HashError, content_hash  # noqa: E402
from schemalite import SchemaStore, Validator, check_schema  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
# Entity defs share one id namespace (ContentDB.def_index, 03 s9.2). Weapons and projectiles are
# per-file namespaces resolved by weapon_index / projectile_index (R0 B.8 A-1: the weapon and the
# projectile are both `bomb`).
ENTITY_FILES = ("ships", "ground_units", "structures", "towers")
SINGLETONS = ("rules", "economy", "match_rules")
# Tier profiles name their promise; Adjutant profiles have none and run at Normal cadence (R0 B.8 A-6, 05 s8).
TIER_PROFILES = ("easy", "normal", "hard", "brutal")
ADJUTANT_PREFIX = "adjutant_"
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.counts = {"schemas": 0, "defs": 0, "maps": 0, "examples": 0, "parse_only": 0}

    def add(self, where: str, msg: str) -> None:
        self.errors.append(f"{where}: {msg}")


def load_json(path: Path, rep: Report, rel: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except ValueError as exc:
        rep.add(rel, f"invalid JSON: {exc}")
    return None


def gravity_of(root: Path) -> Any:
    """rules.gravity from godot/content/defs/rules.json, or None when that file is absent or unreadable
    (run_defs reports unreadable JSON; the hover floor then cannot be checked, as in check_cross)."""
    path = root / "godot/content/defs/rules.json"
    if not path.is_file():
        return None
    try:
        rules = json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return None
    return rules.get("gravity") if isinstance(rules, dict) else None


def schema_for(store: SchemaStore, stem: str, pointer: str = "") -> tuple[dict, str]:
    name = f"{stem}.schema.json"
    if not pointer or pointer == "#":
        return store.load(name), name
    return store.resolve(pointer, name)


def validate(val: Validator, rep: Report, rel: str, data: Any, stem: str, pointer: str = "") -> None:
    sch, doc = schema_for(val.store, stem, pointer)
    for path, msg in val.validate(data, sch, doc):
        rep.add(f"{rel}:{path or '/'}", msg)


def collection(data: Any, stem: str) -> list[dict]:
    if isinstance(data, dict) and isinstance(data.get(stem), list):
        return [e for e in data[stem] if isinstance(e, dict)]
    return []


def check_unique_ids(rep: Report, defs: dict[str, Any]) -> None:
    seen: dict[str, str] = {}
    for stem, data in sorted(defs.items()):
        if stem in SINGLETONS:
            continue
        local: set[str] = set()
        for n, e in enumerate(collection(data, stem)):
            ident = e.get("id")
            where = f"godot/content/defs/{stem}.json:/{stem}/{n}/id"
            if ident in local:
                rep.add(where, f"duplicate id '{ident}'")
            local.add(ident)
            if stem in ENTITY_FILES:
                if ident in seen and seen[ident] != stem:
                    rep.add(where, f"id '{ident}' already defined in {seen[ident]}.json (entity def ids share one namespace, 03 s9.2)")
                seen.setdefault(ident, stem)


def check_hover_floor(rep: Report, where: str, ship: dict, gravity: Any) -> None:
    """O-2 (R0 B.1): every ship hovers at 2.0 * rules.gravity. The schema carries only the gravity-anchor
    bound (ships.schema.json), so this is the one place the floor is enforced: def files (check_cross)
    and docs/examples ships (run_examples, when rules.json exists)."""
    a = ship.get("a_thrust")
    if isinstance(a, (int, float)) and isinstance(gravity, (int, float)) and a < 2.0 * gravity:
        rep.add(f"{where}/a_thrust", f"{a} < 2.0 * rules.gravity ({2.0 * gravity}) (R0 B.1, O-2 hover margin)")


def check_cross(rep: Report, defs: dict[str, Any]) -> None:
    rules = defs.get("rules") if isinstance(defs.get("rules"), dict) else {}
    for n, ship in enumerate(collection(defs.get("ships"), "ships")):
        check_hover_floor(rep, f"godot/content/defs/ships.json:/ships/{n}", ship, rules.get("gravity"))
    for n, weapon in enumerate(collection(defs.get("weapons"), "weapons")):
        lo, hi = weapon.get("range_min_m"), weapon.get("range_m")
        if isinstance(lo, (int, float)) and isinstance(hi, (int, float)) and lo >= hi:
            rep.add(f"godot/content/defs/weapons.json:/weapons/{n}/range_min_m",
                    f"range_min_m {lo} must be < range_m {hi} (R0 B.8 A-2)")
    if "bot_promises" in defs:
        check_profiles(rep, rules.get("tick_hz", 30), defs)
    check_amendments_02(rep, defs)
    check_landing_grade(rep, defs)
    check_quality_tiers(rep, defs)


QUALITY_TIERS = ("LOW", "MEDIUM", "HIGH")


def check_quality_tiers(rep: Report, defs: dict[str, Any]) -> None:
    """03 s13 / R0 C2-29: exactly one entry per tier name LOW, MEDIUM, HIGH; the id is the lowercased tier name."""
    if "quality_tiers" not in defs:
        return
    tiers = collection(defs.get("quality_tiers"), "quality_tiers")
    where = "godot/content/defs/quality_tiers.json:/quality_tiers"
    names = [t.get("tier") for t in tiers]
    if sorted(str(n) for n in names) != sorted(QUALITY_TIERS):
        rep.add(where, f"must hold exactly one entry each for {', '.join(QUALITY_TIERS)} (R0 C2-29), got {names}")
    for n, t in enumerate(tiers):
        if isinstance(t.get("tier"), str) and t.get("id") != t["tier"].lower():
            rep.add(f"{where}/{n}/id", f"id '{t.get('id')}' must be '{t['tier'].lower()}' for tier {t['tier']}")


def check_amendments_02(rep: Report, defs: dict[str, Any]) -> None:
    """R0 B.9 (docs/reviews/R0-amendments-02.md) cross-field rules the schemas cannot express."""
    for n, mode in enumerate(collection(defs.get("modes"), "modes")):
        where = f"godot/content/defs/modes.json:/modes/{n}"
        hosting = mode.get("hosting") if isinstance(mode.get("hosting"), list) else []
        scope = mode.get("pause_scope")
        if scope is not None and mode.get("pause_save") is not True:
            rep.add(f"{where}/pause_scope", "pause_scope needs pause_save true (R0 B.9 A-16)")
        if scope == "listen_host" and "listen" not in hosting:
            rep.add(f"{where}/pause_scope", "pause_scope 'listen_host' needs 'listen' in hosting (R0 B.9 A-16)")
        if scope in (None, "in_process") and mode.get("pause_save") is True and "in_process" not in hosting:
            rep.add(f"{where}/pause_save", "pause_save true with in_process scope needs 'in_process' in hosting (R0 B.9 A-16)")
        if "caps_web_mobile" in mode and "in_process" not in hosting:
            rep.add(f"{where}/caps_web_mobile", "caps_web_mobile applies to in_process hosting only (R0 B.9 A-17)")
    for n, prom in enumerate(collection(defs.get("bot_promises"), "bot_promises")):
        ident = prom.get("id")
        for field, suffix in (("audience_key", "audience"), ("human_target_key", "human_target")):
            want = f"promise.{ident}.{suffix}"
            if isinstance(prom.get(field), str) and prom.get(field) != want:
                rep.add(f"godot/content/defs/bot_promises.json:/bot_promises/{n}/{field}",
                        f"'{prom.get(field)}' must be '{want}' (R0 B.9 A-18)")
    for stem in ("structures", "towers"):
        for n, s in enumerate(collection(defs.get(stem), stem)):
            if s.get("launch_pad") is True and s.get("pads", 0) != 0:
                rep.add(f"godot/content/defs/{stem}.json:/{stem}/{n}/pads",
                        f"a launch_pad structure has no service pads; pads {s.get('pads')} must be 0 (R0 B.9 A-19)")


def check_landing_grade(rep: Report, defs: dict[str, Any]) -> None:
    """FEAT-01 (08 SL-1): scoring.json landing_grade mirrors the 02 landing block (one set of numbers, two
    names), its q weights sum to 1.0, and its grade thresholds and points match the 02 values."""
    scoring = defs.get("scoring")
    if not isinstance(scoring, dict) or not isinstance(scoring.get("landing_grade"), dict):
        return
    where = "godot/content/defs/scoring.json:/landing_grade"
    grade, landing = scoring["landing_grade"], scoring.get("landing") or {}
    weights = grade.get("weights") or {}
    if all(isinstance(v, (int, float)) for v in weights.values()) and weights:
        total = sum(weights.values())
        if abs(total - 1.0) > 1e-9:
            rep.add(f"{where}/weights", f"weights sum to {total}, must be 1.0 (08 SL-1 rule 2)")
    pairs = (
        ("weights", grade.get("weights"), landing.get("q_weights")),
        ("thresholds", grade.get("thresholds"), landing.get("q_thresholds")),
        ("points", grade.get("points"), landing.get("points")),
    )
    for key, mine, theirs in pairs:
        if mine != theirs:
            rep.add(f"{where}/{key}", f"{mine} differs from the 02 landing block ({theirs}) (08 SL-1 vs 02 s17.1)")
    scalars = (
        ("hot_multiplier", "hot_mult"), ("hot_radius_m", "hot_enemy_range_m"),
        ("hot_window_s", "hot_hit_window_s"), ("dead_stick_fuel01", "dead_stick_fuel01"),
        ("dead_stick_points", "dead_stick_bonus"),
    )
    for mine_key, theirs_key in scalars:
        if grade.get(mine_key) != landing.get(theirs_key):
            rep.add(f"{where}/{mine_key}", f"{grade.get(mine_key)} differs from the 02 landing {theirs_key} "
                                           f"({landing.get(theirs_key)})")


def cadence_pairs(prom: dict, hz: float, with_rate: bool) -> tuple[tuple[str, Any], ...]:
    pairs: tuple[tuple[str, Any], ...] = (("think_period_ticks", round(prom.get("think_s", 0) * hz)),
                                          ("reaction_delay_s", prom.get("reaction_s")))
    return pairs + (("max_commands_per_min", prom.get("command_rate_cap")),) if with_rate else pairs


def check_profiles(rep: Report, hz: float, defs: dict[str, Any]) -> None:
    """R0 C2-13 and B.8 A-6: tier profiles mirror their promise's cadence and rate; Adjutant profiles
    have no promise and run at the `normal` cadence (05 s8), with their own command rate."""
    promises = {p.get("id"): p for p in collection(defs.get("bot_promises"), "bot_promises")}
    for n, prof in enumerate(collection(defs.get("bot_profiles"), "bot_profiles")):
        where = f"godot/content/defs/bot_profiles.json:/bot_profiles/{n}"
        ident, pid = prof.get("id"), prof.get("promise")
        if pid is None:
            if ident in TIER_PROFILES:
                rep.add(f"{where}/promise", f"tier profile '{ident}' must name its promise (R0 C2-13)")
                continue
            prom, label, with_rate = promises.get("normal"), "the normal cadence (05 s8)", False
        else:
            if ident is not None and ident.startswith(ADJUTANT_PREFIX):
                rep.add(f"{where}/promise", f"Adjutant profile '{ident}' has no promise; expected null (R0 B.8 A-6)")
            prom, label, with_rate = promises.get(pid), f"promise '{pid}'", True
        if prom is None:
            rep.add(f"{where}/promise", f"unknown promise '{pid}'" if pid is not None else "no 'normal' promise to mirror")
            continue
        for field, want in cadence_pairs(prom, hz, with_rate):
            if prof.get(field) != want:
                rep.add(f"{where}/{field}", f"{prof.get(field)} differs from {label} ({want}) (R0 C2-13)")


def walk_refs(node: Any, key: str, path: str = ""):
    """Yield (pointer, value) for every string-valued `key` anywhere under node."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key and isinstance(v, str):
                yield f"{path}/{k}", v
            else:
                yield from walk_refs(v, key, f"{path}/{k}")
    elif isinstance(node, list):
        for n, v in enumerate(node):
            yield from walk_refs(v, key, f"{path}/{n}")


def ids_of(defs: dict[str, Any], stem: str) -> set[str]:
    return {e.get("id") for e in collection(defs.get(stem), stem)}


def check_dangling(rep: Report, defs: dict[str, Any]) -> None:
    """Def-to-def references (03 s9.2): every `weapon` in ships, ground_units, structures and towers names a
    weapons.json id; every weapons `projectile` names a projectiles.json id. A check runs only when its target
    file is present (defs are authored in parallel); a present file with a missing id is a violation."""
    for stem in (*ENTITY_FILES, "weapons"):
        key, target = ("projectile", "projectiles") if stem == "weapons" else ("weapon", "weapons")
        if stem not in defs or target not in defs:
            continue
        known = ids_of(defs, target)
        for n, e in enumerate(collection(defs[stem], stem)):
            for ptr, ref in walk_refs(e, key, f"/{stem}/{n}"):
                if ref not in known and ID_RE.match(ref):  # malformed ids are the schema's finding
                    rep.add(f"godot/content/defs/{stem}.json:{ptr}", f"dangling {key} '{ref}': no such id in {target}.json")


def check_recipe_ranges(rep: Report, rel: str, recipe: dict) -> None:
    """Rules the recipe schema cannot express (TA-07): craters.scatter diam_m is [min, max] in order."""
    craters = recipe.get("craters")
    scatter = craters.get("scatter") if isinstance(craters, dict) else None
    diam = scatter.get("diam_m") if isinstance(scatter, dict) else None
    if isinstance(diam, list) and len(diam) == 2 and all(isinstance(x, (int, float)) for x in diam) and diam[0] > diam[1]:
        rep.add(f"{rel}:/craters/scatter/diam_m", f"diam_m {diam} must be ascending [min, max] (R0 B.2)")


def check_recipe_ids(rep: Report, rel: str, recipe: Any) -> None:
    if isinstance(recipe, dict):
        check_recipe_ranges(rep, rel, recipe)
    res = recipe.get("resources") if isinstance(recipe, dict) else None
    if not isinstance(res, dict):
        return
    seen: set[str] = set()
    for block in ("slot_features", "ring_features", "pole_features"):
        for n, feat in enumerate(res.get(block) or []):
            ident = feat.get("id") if isinstance(feat, dict) else None
            if ident in seen:
                rep.add(f"{rel}:/resources/{block}/{n}/id", f"duplicate feature id '{ident}'")
            seen.add(ident)


def run_schemas(store: SchemaStore, rep: Report, schema_dir: Path) -> set[str]:
    stems = set()
    for path in sorted(schema_dir.glob("*.schema.json")):
        rep.counts["schemas"] += 1
        stems.add(path.name[: -len(".schema.json")])
        rep.errors.extend(f"tools/schemas/{problem}" for problem in check_schema(store, path.name))
    return stems


def run_defs(val: Validator, rep: Report, root: Path, stems: set[str]) -> None:
    defs: dict[str, Any] = {}
    for path in sorted((root / "godot/content/defs").glob("*.json")):
        rel = path.relative_to(root).as_posix()
        rep.counts["defs"] += 1
        data = load_json(path, rep, rel)
        if data is None:
            continue
        if path.stem not in stems:
            rep.add(rel, f"no schema tools/schemas/{path.stem}.schema.json (03 s9.4: every def file has one)")
            continue
        validate(val, rep, rel, data, path.stem)
        defs[path.stem] = data
    check_unique_ids(rep, defs)
    check_cross(rep, defs)
    check_dangling(rep, defs)
    for path in sorted((root / "godot/content/maps").glob("*/recipe.json")):
        rel = path.relative_to(root).as_posix()
        rep.counts["maps"] += 1
        data = load_json(path, rep, rel)
        if data is None:
            continue
        validate(val, rep, rel, data, "map_recipe")
        if isinstance(data, dict) and data.get("id") != path.parent.name:
            rep.add(f"{rel}:/id", f"id '{data.get('id')}' must equal the directory name '{path.parent.name}'")
        check_recipe_ids(rep, rel, data)
    ramps = root / "godot/content/biome_ramps.json"
    if ramps.is_file():   # ART-14: source of moon_ramp.png, 8 biomes with unique ids 0-7
        data = load_json(ramps, rep, "godot/content/biome_ramps.json")
        if data is not None:
            validate(val, rep, "godot/content/biome_ramps.json", data, "biome_ramps")
            ids = [b.get("id") for b in data.get("biomes", []) if isinstance(b, dict)]
            if sorted(ids) != list(range(8)):
                rep.add("godot/content/biome_ramps.json:/biomes", "ids must be exactly 0-7, once each")


def run_examples(val: Validator, rep: Report, root: Path, stems: set[str]) -> None:
    ex_dir = root / "docs/examples"
    files = {p.relative_to(ex_dir).as_posix() for p in ex_dir.rglob("*.json")} if ex_dir.is_dir() else set()
    manifest_path = root / "tools/doc_example_schemas.json"
    manifest = load_json(manifest_path, rep, "tools/doc_example_schemas.json") if manifest_path.is_file() else {}
    entries: dict[str, dict] = (manifest or {}).get("examples", {})
    for name in sorted(files - set(entries)):
        rep.add(f"docs/examples/{name}", "not mapped in tools/doc_example_schemas.json")
    for name, spec in sorted(entries.items()):
        rel = f"docs/examples/{name}"
        if name not in files:
            rep.add("tools/doc_example_schemas.json", f"maps '{name}', which does not exist under docs/examples/")
            continue
        rep.counts["examples"] += 1
        text = (ex_dir / name).read_text(encoding="utf-8")
        member = spec.get("fragment_member")
        try:
            data = json.loads("{" + text + "}")[member] if member else json.loads(text)
        except (ValueError, KeyError) as exc:
            rep.add(rel, f"invalid JSON: {exc}")
            continue
        stem = spec.get("schema")
        if stem is None:
            rep.counts["parse_only"] += 1
            if not spec.get("reason"):
                rep.add("tools/doc_example_schemas.json", f"'{name}' has no schema and no reason")
            continue
        if stem not in stems:
            rep.add("tools/doc_example_schemas.json", f"'{name}' names unknown schema '{stem}'")
            continue
        envelope = spec.get("keyed_envelope")
        if envelope is not None:
            for key, body in sorted(data.items()):
                validate(val, rep, f"{rel}:/{key}", {**envelope, "id": key, **body}, stem, spec.get("pointer", ""))
        else:
            validate(val, rep, rel, data, stem, spec.get("pointer", ""))
        if stem == "map_recipe" and not spec.get("pointer"):
            check_recipe_ids(rep, rel, data)
        if stem == "ships" and isinstance(data, dict):
            check_hover_floor(rep, f"{rel}:", data, gravity_of(root))


def run(root: Path) -> Report:
    rep = Report()
    schema_dir = root / "tools/schemas"
    store = SchemaStore(schema_dir)
    val = Validator(store)
    stems = run_schemas(store, rep, schema_dir)
    run_defs(val, rep, root, stems)
    run_examples(val, rep, root, stems)
    return rep


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--print-hash", action="store_true", help="print the content hash and exit")
    ap.add_argument("--root", type=Path, default=ROOT, help="repository root (default: this checkout)")
    args = ap.parse_args(argv)
    try:
        if args.print_hash:
            print(content_hash(args.root.resolve() / "godot/content/defs"))
            return 0
        rep = run(args.root.resolve())
    except (OSError, KeyError, HashError, ValueError) as exc:
        print(f"validate_content: {exc}", file=sys.stderr)
        return 2
    for line in rep.errors:
        print(line)
    c = rep.counts
    digest = ""
    if not any("invalid JSON" in e for e in rep.errors):
        try:
            digest = content_hash(args.root.resolve() / "godot/content/defs")
        except (OSError, ValueError) as exc:
            print(f"godot/content/defs: content hash failed: {exc}")
            return 1
    status = "FAIL" if rep.errors else "ok"
    print(f"validate_content: {c['schemas']} schemas, {c['defs']} def files, {c['maps']} map recipes, "
          f"{c['examples']} doc examples ({c['examples'] - c['parse_only']} schema-validated, {c['parse_only']} parse-only): "
          f"{status}" + (f", content_hash {digest}" if digest else "") + (f", {len(rep.errors)} violations" if rep.errors else ""))
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main())
