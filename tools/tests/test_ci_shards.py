"""TA-71/TA-73: every gdUnit4 test file under test/unit and test/sim is selected by exactly one CI shard (TA-67 coverage guard)."""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CI = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
ENTRY = re.compile(r'- \{ name: (\S+), layer: (\w+), shard: ("[^"]*"|[^,\s]+)(?:, dirs: "([^"]*)")? \}')


def selected(name, layer, shard, dirs):
    env = dict(os.environ, GODOT_BIN="godot", GDUNIT_DRY_RUN="1", RUNNER_TEMP=tempfile.mkdtemp(), SHARD_DIRS=dirs or "")
    out = subprocess.run(["bash", ".github/scripts/gdunit_shard.sh", layer, shard, name], cwd=ROOT, env=env,
                         capture_output=True, text=True, check=True).stdout
    files = set()
    for m in re.finditer(r"-a res://(\S+)", out):
        p = ROOT / "godot" / m.group(1)
        files.update(p.rglob("test_*.gd") if p.is_dir() else [p])
    return files


@unittest.skipUnless(shutil.which("bash"), "bash required")
class CiShardCoverage(unittest.TestCase):
    def _partition(self, layer, minimum):
        entries = [(n, l, s.strip('"'), d) for n, l, s, d in ENTRY.findall(CI) if l == layer]
        self.assertGreaterEqual(len(entries), minimum)
        seen = {}
        for n, l, s, d in entries:
            sel = selected(n, l, s, d)
            self.assertTrue(sel, f"shard {n} selects no test files")
            for f in sel:
                self.assertTrue(f.exists(), f"{n} selects a missing path {f}")
                self.assertNotIn(f, seen, f"{f} is in both {seen.get(f)} and {n}")
                seen[f] = n
        every = set((ROOT / "godot/test" / layer).rglob("test_*.gd"))
        self.assertEqual(every - set(seen), set(), f"test files covered by no {layer} shard")

    def test_unit_shards_partition_the_layer(self):
        self._partition("unit", 3)

    def test_sim_shards_partition_the_layer(self):
        self._partition("sim", 2)


if __name__ == "__main__":
    unittest.main()
