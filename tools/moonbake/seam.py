"""Edge seaming (docs/03 s8.5): texel columns on a cube edge are written bit-identically into both faces."""

from __future__ import annotations

from functools import lru_cache

import numpy as np

from . import sphere

EDGE_NAMES = ("u0", "u1", "v0", "v1")
_NUDGE = 1e-7  # step past the edge, in uv, so the inverse mapping picks the neighbour face


def _edge_texels(edge: int, n: int):
    t = np.arange(n)
    z = np.zeros(n, dtype=np.int64)
    full = np.full(n, n - 1, dtype=np.int64)
    return [(z, t), (full, t), (t, z), (t, full)][edge]  # (x, y)


@lru_cache(maxsize=8)
def edge_pairs(n: int):
    """[(face_a, flat_idx_a, face_b, flat_idx_b, edge_a, edge_b)] with face_a < face_b; flat = y * n + x.
    Corner texels appear in three faces and therefore in three pairs."""
    out = []
    for fa in range(6):
        for edge in range(4):
            x, y = _edge_texels(edge, n)
            u = x / (n - 1.0)
            v = y / (n - 1.0)
            if edge == 0:
                u = u - _NUDGE
            elif edge == 1:
                u = u + _NUDGE
            elif edge == 2:
                v = v - _NUDGE
            else:
                v = v + _NUDGE
            # stepping past an edge: the mapping is valid beyond [0, 1] (tan keeps going)
            d = sphere.face_uv_to_dir(fa, u, v)
            fb, ub, vb = sphere.dir_to_face_uv(d)
            if np.any(fb == fa):
                raise RuntimeError("seam: nudge did not leave the face")
            if len(set(fb.tolist())) != 1:
                # corner texels step into one of two neighbours; pair each texel with whichever it landed on
                pass
            xb = np.rint(ub * (n - 1.0)).astype(np.int64)
            yb = np.rint(vb * (n - 1.0)).astype(np.int64)
            for fb_val in sorted(set(fb.tolist())):
                m = fb == fb_val
                if fb_val <= fa:
                    continue
                err = max(np.abs(ub[m] * (n - 1.0) - xb[m]).max(), np.abs(vb[m] * (n - 1.0) - yb[m]).max())
                if err > 0.01:
                    raise RuntimeError(f"seam: face {fa} edge {edge} does not land on texel centres ({err})")
                eb = _which_edge(xb[m], yb[m], n)
                out.append((fa, (y[m] * n + x[m]), fb_val, (yb[m] * n + xb[m]), edge, eb))
    return out


def _which_edge(xb: np.ndarray, yb: np.ndarray, n: int) -> int:
    if np.all(xb == 0):
        return 0
    if np.all(xb == n - 1):
        return 1
    if np.all(yb == 0):
        return 2
    if np.all(yb == n - 1):
        return 3
    return -1  # corner texel group, spans two edges of the neighbour


def seam(arrs: list[np.ndarray]) -> None:
    """In place: `arrs` is 6 arrays (n, n) of any dtype; the lower face index wins on every shared texel."""
    n = arrs[0].shape[0]
    flat = [a.reshape(-1) for a in arrs]
    for fa, ia, fb, ib, _, _ in sorted(edge_pairs(n), key=lambda p: (p[0], p[2])):
        flat[fb][ib] = flat[fa][ia]


def edge_table(n: int):
    """The 12 shared edges as (face_a, edge_a, face_b, edge_b) for a < b (whole-edge pairs only)."""
    rows = set()
    for fa, ia, fb, ib, ea, eb in edge_pairs(n):
        if eb >= 0 and len(ia) == n:
            rows.add((fa, ea, fb, eb))
    return sorted(rows)
