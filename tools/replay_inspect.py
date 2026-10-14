#!/usr/bin/env python3
"""replay_inspect: a Python decoder for PLANEWAR `.pwr` replays (NET-25; 04 s13.1, ADR-10).

Mirrors godot/src/net/replay/*.gd and the SNAPSHOT codec (04 s3.4) for what a replay contains: A-tier FULL and
DELTA records against the previous written frame, ENTITY_META / ROSTER_REMOVE, EVENTS, CHAT and INPUT_SUMMARY frames.
Positions stay as quantised levels (cell, e, n, u); it does not need the moon's cell geometry. Used by moderators
(CHAT text, NET-43) and perf scripts. Standard library only.

    python tools/replay_inspect.py match.pwr [--json] [--gravity 6.0 --hz 30 --gravity-def 3 ...] [--chat] [--redact OUT]

Gravity-bearing entity defs (bomb, siege shell) are content data, so pass their def ids with --gravity-def.
Exit code: 0 ok, 1 file unreadable or unsupported, 2 recovered from a truncated file (frames up to the cut printed).
"""
from __future__ import annotations

import argparse
import gzip
import json
import math
import struct
import sys
import zlib
from dataclasses import dataclass, field

MAGIC = b"PWR1"
END_MAGIC = b"PWRE"
PROTOCOL_VERSION = 1
FRAME_HEADER = 9
FOOTER = 44
KEYFRAME, DELTA, EVENTS, CHAT, INPUT_SUMMARY = 1, 2, 3, 4, 5
FRAME_NAMES = {1: "KEYFRAME", 2: "DELTA", 3: "EVENTS", 4: "CHAT", 5: "INPUT_SUMMARY"}
ID_SNAPSHOT, ID_EVENTS, ID_ENTITY_META, ID_ROSTER_REMOVE = 0x84, 0x87, 0x88, 0x90
POS_EN_HALF = 1280.0
POS_U_MIN = -768.0
POS_EN_QUANTUM = 2.0 * POS_EN_HALF / 65536
POS_U_QUANTUM = 4096.0 / 65536
PLANET_RADIUS = 6000.0
FINE_PER_MPS = 1024
FINE_MASK = 0x1FFFFF
FINE_MAX = 0xFFFFF
FLAG_DYING = 0x80
MASK_POS_SMALL, MASK_POS_LARGE, MASK_ORI, MASK_VEL, MASK_HP, MASK_FLAGS = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
HEADER_BYTES = 10


class ReplayError(Exception):
    pass


# Everything a corrupt file can raise from the decoder; the CLI turns these into exit code 1.
READ_ERRORS = (ReplayError, struct.error, IndexError, ValueError, KeyError, OverflowError)


def _sext(v: int, bits: int) -> int:
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def floori(x: float) -> int:
    return math.floor(x)


def pack_fine(e: int, n: int, u: int) -> int:
    def c(v: int) -> int:
        return max(-FINE_MAX, min(FINE_MAX, v)) & FINE_MASK
    return c(e) | (c(n) << 21) | (c(u) << 42)


def fine_axis(fine: int, axis: int) -> int:
    return _sext((fine >> (21 * axis)) & FINE_MASK, 21)


def fine_from_bits(bits: int) -> int:
    step = round(2.0 * FINE_PER_MPS)
    return pack_fine(_sext(bits, 8) * step, _sext(bits >> 8, 8) * step, _sext(bits >> 16, 8) * step)


def _godot_round(x: float) -> int:
    # GDScript roundi / floori(x + 0.5): half away from zero for roundi
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def dr_levels(pos: tuple, fine: int, dticks: int, grav: bool, g: float, dt: float) -> tuple:
    _cell, e0, n0, u0 = pos
    if fine == 0 and not grav:
        return (e0, n0, u0)
    t = dticks * dt
    inv = 1.0 / FINE_PER_MPS
    de = fine_axis(fine, 0) * inv * t
    dn = fine_axis(fine, 1) * inv * t
    du = fine_axis(fine, 2) * inv * t
    if grav and dticks != 0:
        em = e0 * POS_EN_QUANTUM - POS_EN_HALF
        nm = n0 * POS_EN_QUANTUM - POS_EN_HALF
        rz = PLANET_RADIUS + u0 * POS_U_QUANTUM + POS_U_MIN
        k = 0.5 * g * t * t / math.sqrt(em * em + nm * nm + rz * rz)
        de -= k * em
        dn -= k * nm
        du -= k * rz
    return (e0 + floori(de / POS_EN_QUANTUM + 0.5), n0 + floori(dn / POS_EN_QUANTUM + 0.5),
            u0 + floori(du / POS_U_QUANTUM + 0.5))


def dr_fine(pos: tuple, fine: int, dticks: int, grav: bool, g: float, dt: float) -> int:
    if not grav or dticks == 0:
        return fine
    _c, e0, n0, u0 = pos
    em = e0 * POS_EN_QUANTUM - POS_EN_HALF
    nm = n0 * POS_EN_QUANTUM - POS_EN_HALF
    rz = PLANET_RADIUS + u0 * POS_U_QUANTUM + POS_U_MIN
    k = g * dticks * dt * FINE_PER_MPS / math.sqrt(em * em + nm * nm + rz * rz)
    return pack_fine(fine_axis(fine, 0) - _godot_round(k * em), fine_axis(fine, 1) - _godot_round(k * nm),
                     fine_axis(fine, 2) - _godot_round(k * rz))


def _levels_ok(lv: tuple) -> bool:
    return all(0 <= v < 65536 for v in lv)


@dataclass
class Entry:
    pos: tuple = (0, 0, 0, 0)       # cell, e, n, u levels at etick
    ori: int = 0                    # quat_s3 u32
    vel: int = 0                    # fine velocity
    hp: int = 0
    flags: int = 0
    etick: int = 0


@dataclass
class Header:
    protocol_version: int = 0
    content_hash: bytes = b""
    map_hash: bytes = b""
    map_id: str = ""
    match_id: bytes = b""
    config: bytes = b""
    seed: int = 0
    started_unix: int = 0
    tick_rate: int = 0
    players: list = field(default_factory=list)
    length: int = 0
    uid_at: list = field(default_factory=list)
    name_at: list = field(default_factory=list)


@dataclass
class Replay:
    header: Header
    raw: bytes
    frames_begin: int
    frames_end: int
    has_footer: bool = False
    result_hash: bytes = b""
    ended_tick: int = 0
    index: list = field(default_factory=list)   # (tick, byte_offset)
    recovered: bool = False


def gunzip_partial(data: bytes) -> tuple[bytes, bool]:
    """Inflate as much of a (possibly truncated) gzip stream as possible. Returns (bytes, complete)."""
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    out = bytearray()
    try:
        for i in range(0, len(data), 65536):
            out += d.decompress(data[i:i + 65536])
        out += d.flush()
    except zlib.error:
        return bytes(out), False
    return bytes(out), d.eof


def parse_header(raw: bytes) -> Header:
    if raw[:4] != MAGIC:
        raise ReplayError("bad magic")
    if len(raw) < 6:
        raise ReplayError("short header")
    h = Header()
    h.protocol_version = struct.unpack_from("<H", raw, 4)[0]
    if h.protocol_version != PROTOCOL_VERSION:
        raise ReplayError(f"unsupported protocol version {h.protocol_version}")
    try:
        at = 6
        h.content_hash, h.map_hash = raw[at:at + 32], raw[at + 32:at + 64]
        at += 64
        n = raw[at]
        h.map_id = raw[at + 1:at + 1 + n].decode("utf-8", "replace")
        at += 1 + n
        h.match_id = raw[at:at + 16]
        cfg = struct.unpack_from("<H", raw, at + 16)[0]
        at += 18
        h.config = raw[at:at + cfg]
        at += cfg
        h.seed = struct.unpack_from("<q", raw, at)[0]
        h.started_unix = struct.unpack_from("<I", raw, at + 8)[0]
        h.tick_rate = raw[at + 12]
        count = raw[at + 13]
        at += 14
        for _ in range(count):
            slot, team, kind, doctrine, iclass = raw[at:at + 5]
            uid_at, name_at = at + 5, at + 21
            n = raw[name_at]
            name = raw[name_at + 1:name_at + 1 + n].decode("utf-8", "replace")
            h.players.append({"slot": slot, "team": team, "kind": kind, "doctrine": doctrine,
                              "input_class": iclass, "user_id": raw[uid_at:uid_at + 16].hex(), "name": name})
            h.uid_at.append(uid_at)
            h.name_at.append(name_at)
            at = name_at + 1 + n
        if struct.unpack_from("<I", raw, at)[0] != at + 4:
            raise ReplayError("header_len mismatch")
    except (struct.error, IndexError, ValueError) as e:
        raise ReplayError(f"corrupt header: {e}") from e
    h.length = at + 4
    return h


def open_replay(file_bytes: bytes, gzipped: bool = True) -> Replay:
    complete = True
    raw = file_bytes
    if gzipped:
        raw, complete = gunzip_partial(file_bytes)
    header = parse_header(raw)
    rp = Replay(header, raw, header.length, len(raw))
    size = len(raw)
    ok = False
    if size >= header.length + FOOTER and raw[-4:] == END_MAGIC:
        f = size - FOOTER
        idx = struct.unpack_from("<I", raw, f)[0]
        if header.length <= idx and idx + 4 <= f:
            count = struct.unpack_from("<I", raw, idx)[0]
            if idx + 4 + count * 8 == f:
                rp.index = [struct.unpack_from("<II", raw, idx + 4 + 8 * i) for i in range(count)]
                rp.result_hash = raw[f + 4:f + 36]
                rp.ended_tick = struct.unpack_from("<I", raw, f + 36)[0]
                rp.frames_end = idx
                ok = True
    rp.has_footer = ok
    if not ok:
        rp.recovered = True
        _scan(rp)
    elif not complete:
        rp.recovered = True
    return rp


def _scan(rp: Replay) -> None:
    at, size, raw = rp.frames_begin, len(rp.raw), rp.raw
    while at + FRAME_HEADER <= size:
        t = raw[at]
        n = struct.unpack_from("<I", raw, at + 5)[0]
        if t < 1 or t > 5 or at + FRAME_HEADER + n > size:
            break
        tick = struct.unpack_from("<I", raw, at + 1)[0]
        if t == KEYFRAME:
            rp.index.append((tick, at))
        rp.ended_tick = tick
        at += FRAME_HEADER + n
    rp.frames_end = at


def iter_frames(rp: Replay):
    """Yields (type, tick, payload) for every complete frame."""
    at = rp.frames_begin
    while at + FRAME_HEADER <= rp.frames_end:
        t = rp.raw[at]
        tick, n = struct.unpack_from("<II", rp.raw, at + 1)
        if t < 1 or t > 5 or at + FRAME_HEADER + n > rp.frames_end:
            raise ReplayError(f"bad frame at {at}")
        yield t, tick, rp.raw[at + FRAME_HEADER:at + FRAME_HEADER + n]
        at += FRAME_HEADER + n


def split_packets(payload: bytes) -> list[bytes]:
    if len(payload) < 2:
        raise ReplayError("short container")
    count = struct.unpack_from("<H", payload, 0)[0]
    at, out = 2, []
    for _ in range(count):
        n = struct.unpack_from("<H", payload, at)[0]
        at += 2
        if n == 0 or at + n > len(payload):
            raise ReplayError("bad packet length")
        out.append(payload[at:at + n])
        at += n
    if at != len(payload):
        raise ReplayError("container length")
    return out


class State:
    """The replicated state a reader holds: roster (slot -> meta dict) and the newest decoded frame's entries."""

    def __init__(self, gravity: float, hz: int, gravity_defs: set[int]):
        self.g, self.dt, self.grav_defs = gravity, 1.0 / hz, gravity_defs
        self.roster: dict[int, dict] = {}
        self.entries: dict[int, Entry] = {}
        self.tick = 0
        self.frames = 0

    def reset(self) -> None:
        self.roster.clear()
        self.entries.clear()

    def apply_meta(self, p: bytes) -> None:
        count, at = p[1], 2
        for _ in range(count):
            slot, gen, dfn = struct.unpack_from("<HHH", p, at)
            owner, team, tlen = p[at + 6], p[at + 7], p[at + 8]
            self.roster[slot] = {"gen": gen, "def": dfn, "owner": owner, "team": team,
                                 "tag": p[at + 9:at + 9 + tlen].decode("utf-8", "replace")}
            at += 9 + tlen

    def apply_remove(self, p: bytes) -> None:
        for i in range(p[1]):
            slot = struct.unpack_from("<H", p, 2 + 3 * i)[0]
            self.roster.pop(slot, None)

    def apply_snapshot(self, p: bytes, tick: int) -> None:
        fl = p[9]
        at = HEADER_BYTES
        prev, first = 0, True
        for tier in range(3):
            if not fl & (1 << tier):
                continue
            count = p[at]
            at += 1
            if tier != 0:
                raise ReplayError("replay snapshots are A-tier only")
            for _ in range(count):
                g = p[at]
                if g == 0xFF:
                    prev = struct.unpack_from("<H", p, at + 1)[0]
                    at += 3
                else:
                    prev = prev + g
                    at += 1
                first = False
                if prev not in self.roster:
                    raise ReplayError(f"record for slot {prev} without ENTITY_META")
                at = self._record(p, at, prev, tick)
        if at != len(p):
            raise ReplayError("trailing bytes in SNAPSHOT")
        self.tick = tick

    def _is_grav(self, slot: int, e: Entry) -> bool:
        return self.roster[slot]["def"] in self.grav_defs or bool(e.flags & FLAG_DYING)

    def _record(self, p: bytes, at: int, slot: int, tick: int) -> int:
        mask = p[at]
        if mask == 0xFF:
            cell, e, n, u = struct.unpack_from("<HHHH", p, at + 1)
            ori = struct.unpack_from("<I", p, at + 9)[0]
            vel = p[at + 13] | (p[at + 14] << 8) | (p[at + 15] << 16)
            self.entries[slot] = Entry((cell, e, n, u), ori, fine_from_bits(vel), p[at + 16], p[at + 17], tick)
            return at + 18
        src = self.entries.get(slot)
        if src is None or mask & 0xC0 or mask == 0 or (mask & 3) == 3:
            raise ReplayError("bad delta record")
        at += 1
        grav = self._is_grav(slot, src)
        dtk = tick - src.etick
        dr = dr_levels(src.pos, src.vel, dtk, grav, self.g, self.dt)
        res = (0, 0, 0)
        if mask & MASK_POS_SMALL:
            res = tuple(_sext(p[at + i], 8) * 4 for i in range(3))
            at += 3
        elif mask & MASK_POS_LARGE:
            res = struct.unpack_from("<hhh", p, at)
            at += 6
        lv = (dr[0] + res[0], dr[1] + res[1], dr[2] + res[2])
        if not _levels_ok(dr) or not _levels_ok(lv):
            raise ReplayError("levels out of range")
        new = Entry((src.pos[0],) + lv, src.ori, dr_fine(src.pos, src.vel, dtk, grav, self.g, self.dt), src.hp,
                    src.flags, tick)
        if mask & MASK_ORI:
            new.ori = struct.unpack_from("<I", p, at)[0]
            at += 4
        if mask & MASK_VEL:
            new.vel = fine_from_bits(p[at] | (p[at + 1] << 8) | (p[at + 2] << 16))
            at += 3
        if mask & MASK_HP:
            new.hp = p[at]
            at += 1
        if mask & MASK_FLAGS:
            new.flags = p[at]
            at += 1
        self.entries[slot] = new
        return at

    def snapshot(self) -> list[list[int]]:
        """[slot, cell, e, n, u, ori, str(fine_vel), hp, flags, etick] per roster slot with state, by slot (fine_vel is
        a 63-bit packed int, written as a string so JSON floats cannot round it)."""
        out = []
        for slot in sorted(self.roster):
            e = self.entries.get(slot)
            if e is not None:
                out.append([slot, *e.pos, e.ori, str(e.vel), e.hp, e.flags, e.etick])
        return out


def decode_events(p: bytes) -> list[dict]:
    """EVENTS (0x87): id, tick u32, count u8, events x (kind u8, size u8, payload)."""
    tick, count = struct.unpack_from("<IB", p, 1)
    at, out = 6, []
    for _ in range(count):
        kind, size = p[at], p[at + 1]
        out.append({"tick": tick, "kind": kind, "payload": p[at + 2:at + 2 + size].hex()})
        at += 2 + size
    return out


def decode_chat(body: bytes) -> dict:
    msg_id, sender, scope, tlen = struct.unpack_from("<QBBH", body, 0)
    return {"msg_id": msg_id, "sender": sender, "scope": scope, "text": body[12:12 + tlen].decode("utf-8", "replace")}


def decode_all(rp: Replay, gravity: float = 6.0, hz: int = 30, gravity_defs: set[int] | None = None,
               stop_tick: int | None = None) -> dict:
    """Replays every frame; returns a summary dict (the shape godot/test/fixtures/replay/*.json pins)."""
    st = State(gravity, hz, gravity_defs or set())
    counts = {name: 0 for name in FRAME_NAMES.values()}
    events: list[dict] = []
    chat: list[dict] = []
    inputs = 0
    last = 0
    for t, tick, body in iter_frames(rp):
        if stop_tick is not None and tick > stop_tick:
            break
        counts[FRAME_NAMES[t]] += 1
        last = tick
        if t == CHAT:
            chat.append(decode_chat(body))
        elif t == INPUT_SUMMARY:
            inputs += body[0]
        else:
            if t == KEYFRAME:
                st.reset()
            for p in split_packets(body):
                if p[0] == ID_ENTITY_META:
                    st.apply_meta(p)
                elif p[0] == ID_ROSTER_REMOVE:
                    st.apply_remove(p)
                elif p[0] == ID_SNAPSHOT:
                    st.apply_snapshot(p, tick)
                elif p[0] == ID_EVENTS and t == EVENTS:
                    events.extend(decode_events(p))
                else:
                    raise ReplayError(f"unexpected packet {p[0]:#x}")
    return {"map_id": rp.header.map_id, "tick_rate": rp.header.tick_rate, "seed": rp.header.seed,
            "players": [pl["name"] for pl in rp.header.players], "frames": counts,
            "keyframe_ticks": [t for t, _ in rp.index], "ended_tick": rp.ended_tick, "last_tick": last,
            "roster_count": len(st.roster), "events": len(events), "chat": [c["text"] for c in chat],
            "input_players": inputs, "state": st.snapshot()}


def redact(raw: bytes, rp: Replay) -> bytes:
    """Same-length redaction (names and chat text become '*', user ids zero), like ReplayRedactor."""
    out = bytearray(raw)
    h = rp.header
    for i in range(len(h.players)):
        out[h.uid_at[i]:h.uid_at[i] + 16] = bytes(16)
        n = out[h.name_at[i]]
        out[h.name_at[i] + 1:h.name_at[i] + 1 + n] = b"*" * n
    at = rp.frames_begin
    while at + FRAME_HEADER <= rp.frames_end:
        n = struct.unpack_from("<I", raw, at + 5)[0]
        if raw[at] == CHAT:
            p = at + FRAME_HEADER
            tl = struct.unpack_from("<H", raw, p + 10)[0]
            out[p + 12:p + 12 + tl] = b"*" * tl
        at += FRAME_HEADER + n
    return bytes(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Inspect a PLANEWAR .pwr replay (NET-25).")
    ap.add_argument("file")
    ap.add_argument("--json", action="store_true", help="print the full summary as JSON")
    ap.add_argument("--chat", action="store_true", help="print CHAT frames (moderation)")
    ap.add_argument("--gravity", type=float, default=6.0, help="rules.json gravity (m/s^2)")
    ap.add_argument("--hz", type=int, default=30)
    ap.add_argument("--gravity-def", type=int, action="append", default=[], help="entity def id with gravity:true")
    ap.add_argument("--redact", metavar="OUT", help="write a same-length redacted copy (gzip) to OUT")
    ns = ap.parse_args(argv)
    try:
        with open(ns.file, "rb") as f:
            data = f.read()
        rp = open_replay(data)
        summary = decode_all(rp, ns.gravity, ns.hz, set(ns.gravity_def))
    except (OSError, *READ_ERRORS) as e:
        print(f"replay_inspect: {e}", file=sys.stderr)
        return 1
    if ns.redact:
        with open(ns.redact, "wb") as f:
            f.write(gzip.compress(redact(rp.raw, rp), mtime=0))
    if ns.chat:
        for _t, _tick, body in (x for x in iter_frames(rp) if x[0] == CHAT):
            print(json.dumps(decode_chat(body)))
    elif ns.json:
        print(json.dumps(summary))
    else:
        h = rp.header
        print(f"{ns.file}: map={h.map_id} seed={h.seed} players={[p['name'] for p in h.players]} ticks={summary['last_tick']}")
        print(f"  frames={summary['frames']} keyframes={summary['keyframe_ticks']} roster={summary['roster_count']}"
              f" events={summary['events']} chat={len(summary['chat'])}")
        print(f"  footer={'yes' if rp.has_footer else 'MISSING (recovered)'} result_hash={rp.result_hash.hex()[:16]}")
    return 2 if rp.recovered else 0


if __name__ == "__main__":
    sys.exit(main())
