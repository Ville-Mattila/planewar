#!/usr/bin/env python3
"""PLANEWAR colour-blind palette check (ART-02, docs/07 s2.3).

sRGB -> linear -> Machado 2009 (severity 1.0) -> CIELAB D65 -> CIEDE2000.
Usage:
    python tools/art/cvd_check.py tools/blender/palette.json
    python tools/art/cvd_check.py --selftest
Exit code 1 on any failed threshold or failed self-test. Standard library only.
"""
import json
import math
import sys

# Machado, Oliveira, Fernandes 2009, severity 1.0, applied in linear RGB.
MACHADO = {
    "protan": [[0.152286, 1.052583, -0.204868],
               [0.114503, 0.786281, 0.099216],
               [-0.003882, -0.048116, 1.051998]],
    "deutan": [[0.367322, 0.860646, -0.227968],
               [0.280085, 0.672501, 0.047413],
               [-0.011820, 0.042940, 0.968881]],
    "tritan": [[1.255528, -0.076749, -0.178779],
               [-0.078411, 0.930809, 0.147602],
               [0.004733, 0.691367, 0.303900]],
}
VISIONS = ["normal", "protan", "deutan", "tritan"]
CVDS = ["protan", "deutan", "tritan"]

# Thresholds (R0 C1-11, 07 s2.3). Deliberately hard-coded: a palette edit must not relax them.
T_TEAM_NORMAL = 20.0
T_TEAM_CVD = 11.0
T_RELATION = 20.0      # relation trio, all vision types, and vs hull zone / plate
T_TEAM_VS_DARK = 20.0  # team vs hull_700 and UI plate, all vision types
T_2V2 = 15.0           # slots 0-3, all vision types
T_1V1 = 40.0           # slots 0-1, normal vision
HULL_ZONE = ["hull_500", "hull_600", "hull_700", "hull_800"]  # swatches team zones touch


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def simulate(rgb_lin, vision):
    if vision == "normal":
        return rgb_lin
    m = MACHADO[vision]
    out = [sum(m[i][j] * rgb_lin[j] for j in range(3)) for i in range(3)]
    return tuple(min(1.0, max(0.0, v)) for v in out)


def to_lab(rgb_lin):
    r, g, b = rgb_lin
    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
    xn, yn, zn = 0.95047, 1.0, 1.08883

    def f(t):
        return t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116

    fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def lab_of(hexstr, vision):
    lin = tuple(to_linear(c) for c in hex_rgb(hexstr))
    return to_lab(simulate(lin, vision))


def ciede2000(l1, l2):
    L1, a1, b1 = l1
    L2, a2, b2 = l2
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2)
    Cb = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if C1p else 0.0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if C2p else 0.0
    dL = L2 - L1
    dC = C2p - C1p
    if C1p * C2p == 0:
        dh = 0.0
    else:
        dh = h2p - h1p
        if dh > 180:
            dh -= 360
        elif dh < -180:
            dh += 360
    dH = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dh / 2))
    Lb = (L1 + L2) / 2
    Cbp = (C1p + C2p) / 2
    if C1p * C2p == 0:
        hb = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hb = (h1p + h2p) / 2
    else:
        hb = (h1p + h2p + 360) / 2 if h1p + h2p < 360 else (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hb - 30)) + 0.24 * math.cos(math.radians(2 * hb))
         + 0.32 * math.cos(math.radians(3 * hb + 6)) - 0.20 * math.cos(math.radians(4 * hb - 63)))
    dtheta = 30 * math.exp(-(((hb - 275) / 25) ** 2))
    Rc = 2 * math.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lb - 50) ** 2 / math.sqrt(20 + (Lb - 50) ** 2)
    Sc = 1 + 0.045 * Cbp
    Sh = 1 + 0.015 * Cbp * T
    Rt = -math.sin(math.radians(2 * dtheta)) * Rc
    return math.sqrt((dL / Sl) ** 2 + (dC / Sc) ** 2 + (dH / Sh) ** 2
                     + Rt * (dC / Sc) * (dH / Sh))


def dist(h1, h2, vision):
    return ciede2000(lab_of(h1, vision), lab_of(h2, vision))


# Sharma, Wu, Dalal 2005 supplementary test data. (Lab1, Lab2, expected dE00).
SHARMA = [
    ((50.0000, 2.6772, -79.7751), (50.0000, 0.0000, -82.7485), 2.0425),
    ((50.0000, 3.1571, -77.2803), (50.0000, 0.0000, -82.7485), 2.8615),
    ((50.0000, 2.8361, -74.0200), (50.0000, 0.0000, -82.7485), 3.4412),
    ((50.0000, -1.3802, -84.2814), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, -1.1848, -84.8006), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, -0.9009, -85.5211), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, 0.0000, 0.0000), (50.0000, -1.0000, 2.0000), 2.3669),
    ((50.0000, -1.0000, 2.0000), (50.0000, 0.0000, 0.0000), 2.3669),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0009), 7.1792),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0010), 7.1792),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0011), 7.2195),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0012), 7.2195),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0009, -2.4900), 4.8045),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0010, -2.4900), 4.8045),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0011, -2.4900), 4.7461),
    ((50.0000, 2.5000, 0.0000), (50.0000, 0.0000, -2.5000), 4.3065),
    ((50.0000, 2.5000, 0.0000), (73.0000, 25.0000, -18.0000), 27.1492),
    ((50.0000, 2.5000, 0.0000), (61.0000, -5.0000, 29.0000), 22.8977),
    ((50.0000, 2.5000, 0.0000), (56.0000, -27.0000, -3.0000), 31.9030),
    ((50.0000, 2.5000, 0.0000), (58.0000, 24.0000, 15.0000), 19.4535),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.1736, 0.5854), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.2972, 0.0000), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 1.8634, 0.5757), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.2592, 0.3350), 1.0000),
    ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
    ((63.0109, -31.0961, -5.8663), (62.8187, -29.7946, -4.0864), 1.2630),
    ((61.2901, 3.7196, -5.3901), (61.4292, 2.2480, -4.9620), 1.8731),
    ((35.0831, -44.1164, 3.7933), (35.0232, -40.0716, 1.5901), 1.8645),
    ((22.7233, 20.0904, -46.6940), (23.0331, 14.9730, -42.5619), 2.0373),
    ((36.4612, 47.8580, 18.3852), (36.2715, 50.5065, 21.2231), 1.4146),
    ((90.8027, -2.0831, 1.4410), (91.1528, -1.6435, 0.0447), 1.4441),
    ((90.9257, -0.5406, -0.9208), (88.6381, -0.8985, -0.7239), 1.5381),
    ((6.7747, -0.2908, -2.4247), (5.8714, -0.0985, -2.2286), 0.6377),
    ((2.0776, 0.0795, -1.1350), (0.9033, -0.0636, -0.5514), 0.9082),
]


def selftest():
    bad = 0
    for i, (l1, l2, exp) in enumerate(SHARMA, 1):
        got = ciede2000(l1, l2)
        if abs(got - exp) >= 1e-4:
            bad += 1
            print(f"selftest pair {i}: expected {exp:.4f} got {got:.4f} FAIL")
    lw = lab_of("#FFFFFF", "normal")
    if abs(lw[0] - 100) > 0.05 or abs(lw[1]) > 0.05 or abs(lw[2]) > 0.05:
        print("selftest white point FAIL", lw)
        bad += 1
    for v in CVDS:
        lg = lab_of("#808080", v)
        if math.hypot(lg[1], lg[2]) > 1.5:
            print("selftest grey under", v, "FAIL", lg)
            bad += 1
    print(f"selftest: {len(SHARMA)} Sharma 2005 pairs + white/grey checks: "
          + ("FAIL" if bad else "OK"))
    return 1 if bad else 0


def pairs(names):
    return [(names[i], names[j]) for i in range(len(names)) for j in range(i + 1, len(names))]


def check(pal):
    teams = sorted(pal["team"], key=lambda t: t["slot"])
    team = [t["hex"] for t in teams]
    tname = [t["name"] for t in teams]
    if len(team) != 8:
        raise ValueError("palette must define exactly 8 team colours")
    sw = pal["swatches"]
    rel = pal["relation"]
    plate = pal["ui"]["ui_bg_1"]
    failures = []
    rows = []

    def run(test, items, vision_list, thr):
        for v in vision_list:
            best = None
            for la, ha, lb, hb in items:
                d = dist(ha, hb, v)
                if best is None or d < best[0]:
                    best = (d, f"{la}/{lb}")
            ok = best[0] >= thr
            rows.append((test, v, best[0], best[1], thr, ok))
            if not ok:
                failures.append(f"{test} [{v}]: {best[1]} = {best[0]:.2f} < {thr}")

    def tp(idx):
        return [(tname[a], team[a], tname[b], team[b]) for a, b in pairs(list(idx))]

    run("team vs team", tp(range(8)), ["normal"], T_TEAM_NORMAL)
    run("team vs team", tp(range(8)), CVDS, T_TEAM_CVD)
    run("slots 0-3 (2v2)", tp(range(4)), VISIONS, T_2V2)
    run("slots 0-1 (1v1)", tp(range(2)), ["normal"], T_1V1)
    run("team vs hull_700", [(n, h, "hull_700", sw["hull_700"]["hex"]) for n, h in zip(tname, team)],
        VISIONS, T_TEAM_VS_DARK)
    run("team vs UI plate", [(n, h, "ui_bg_1", plate) for n, h in zip(tname, team)],
        VISIONS, T_TEAM_VS_DARK)
    rnames = ["ally", "enemy", "self"]
    run("relation vs relation", [(a, rel[a], b, rel[b]) for a, b in pairs(rnames)],
        VISIONS, T_RELATION)
    ritems = [(r, rel[r], h, sw[h]["hex"]) for r in rnames for h in HULL_ZONE]
    ritems += [(r, rel[r], "ui_bg_1", plate) for r in rnames]
    run("relation vs hull_500-800/plate", ritems, VISIONS, T_RELATION)
    return rows, failures


def main(argv):
    if "--selftest" in argv:
        return selftest()
    paths = [a for a in argv if not a.startswith("-")]
    if len(paths) != 1:
        print(__doc__)
        return 2
    try:
        with open(paths[0], encoding="utf-8") as f:
            pal = json.load(f)
        rows, failures = check(pal)
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"cvd_check: cannot evaluate {paths[0]}: {type(e).__name__}: {e}")
        return 1
    print(f"{'test':<32}{'vision':<8}{'min dE00':>9}  {'threshold':>9}  worst pair")
    for test, v, d, pair, thr, ok in rows:
        print(f"{test:<32}{v:<8}{d:>9.2f}  {'>= ' + format(thr, '.1f'):>9}  {pair}{'' if ok else '  FAIL'}")
    if failures:
        print(f"\nFAILED ({len(failures)}):")
        for f in failures:
            print("  " + f)
        return 1
    print("\nAll palette colour-blind checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
