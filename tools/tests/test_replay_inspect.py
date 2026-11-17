"""NET-25: tools/replay_inspect.py agrees with the GDScript reader on the committed fixture, and handles truncation,
redaction and bad input like ReplayReader / ReplayRedactor do."""

from __future__ import annotations

import gzip
import json
import unittest

from helpers import TOOLS

import replay_inspect as ri

FIX = TOOLS.parent / "godot" / "test" / "fixtures" / "replay"
GRAVITY_DEFS = {3}


class ReplayInspectTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data = (FIX / "net25_small.pwr").read_bytes()
        cls.want = json.loads((FIX / "net25_small.json").read_text(encoding="utf-8"))

    def decode(self, data: bytes) -> dict:
        return ri.decode_all(ri.open_replay(data), 6.0, 30, GRAVITY_DEFS)

    def test_agrees_with_gdscript_reader(self) -> None:
        got = self.decode(self.data)
        for key, val in self.want.items():
            self.assertEqual(got[key], val, key)
        self.assertEqual(len(got["state"]), 20)

    def test_projectile_frames_decoded(self) -> None:
        got = self.decode(self.data)
        self.assertEqual(got["frames"]["PROJECTILES"], 4)
        self.assertEqual(got["shots"], 8)
        rp = ri.open_replay(self.data)
        items = [it for t, tick, body in ri.iter_frames(rp) if t == ri.PROJECTILES
                 for p in ri.split_packets(body) for it in ri.decode_shots(p, tick)]
        self.assertEqual([it["tick"] for it in items], [20, 20, 61, 61, 100, 100, 101, 101])
        self.assertEqual([it["fuse"] for it in items[:2]], [-1, 40])
        self.assertEqual((items[0]["shooter"], items[0]["yaw"], items[0]["pitch"]), (3, 5, -3))

    def test_batch_with_wrong_tick_is_rejected(self) -> None:
        rp = ri.open_replay(self.data)
        for t, tick, body in ri.iter_frames(rp):
            if t == ri.PROJECTILES:
                with self.assertRaises(ri.ReplayError):
                    ri.decode_shots(ri.split_packets(body)[0], tick + 1)
                break

    def test_footer_and_index(self) -> None:
        rp = ri.open_replay(self.data)
        self.assertTrue(rp.has_footer)
        self.assertFalse(rp.recovered)
        self.assertEqual([t for t, _ in rp.index], self.want["keyframe_ticks"])
        self.assertEqual(rp.ended_tick, 150)
        self.assertEqual(rp.result_hash[:2], b"\xee\xee")

    def test_truncated_file_recovers_frames(self) -> None:
        rp = ri.open_replay(self.data[: len(self.data) * 6 // 10])
        self.assertTrue(rp.recovered)
        got = ri.decode_all(rp, 6.0, 30, GRAVITY_DEFS)
        self.assertGreater(got["frames"]["DELTA"], 5)
        self.assertLess(got["last_tick"], 150)

    def test_missing_footer_recovers(self) -> None:
        raw = gzip.decompress(self.data)
        rp = ri.open_replay(raw[:-10], gzipped=False)
        self.assertTrue(rp.recovered)
        self.assertEqual(ri.decode_all(rp, 6.0, 30, GRAVITY_DEFS)["frames"]["KEYFRAME"], 1)

    def test_redaction_keeps_length_and_validity(self) -> None:
        raw = gzip.decompress(self.data)
        rp = ri.open_replay(raw, gzipped=False)
        red = ri.redact(raw, rp)
        self.assertEqual(len(red), len(raw))
        got = ri.decode_all(ri.open_replay(red, gzipped=False), 6.0, 30, GRAVITY_DEFS)
        self.assertEqual(got["players"], ["*****", "************"])
        self.assertEqual(got["chat"], ["************"])
        self.assertEqual(got["state"], self.want["state"])

    def test_bad_input_raises_replay_error(self) -> None:
        raw = gzip.decompress(self.data)
        with self.assertRaises(ri.ReplayError):
            ri.open_replay(b"NOPE" + raw[4:], gzipped=False)
        bumped = bytearray(raw)
        bumped[4] = 9
        with self.assertRaises(ri.ReplayError):
            ri.open_replay(bytes(bumped), gzipped=False)

    def test_mutations_never_raise_anything_but_replay_error(self) -> None:
        raw = bytearray(gzip.decompress(self.data))
        seed = 12345
        for _ in range(400):
            m = bytearray(raw)
            for _k in range(3):
                seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
                m[seed % len(m)] = (seed >> 8) & 0xFF
            try:
                ri.decode_all(ri.open_replay(bytes(m), gzipped=False), 6.0, 30, GRAVITY_DEFS)
            except ri.READ_ERRORS:
                pass


if __name__ == "__main__":
    unittest.main()
