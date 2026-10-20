"""Run a Blender recipe headless and fresh (ART-04, 07 s4.1): never touches a running Blender or its MCP.

    python tools/blender/run_headless.py <recipe.py> [out_dir]

Blender is found via $BLENDER_BIN, PATH, or the newest 'Blender Foundation' install (>= 4.2). Exit code is the
recipe's. The recipe's `import pw` resolves through a sys.path bootstrap; the out dir is passed as $PW_OUT.
"""
from __future__ import annotations

import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parent / "lib"


def find_blender() -> str | None:
    env = os.environ.get("BLENDER_BIN")
    if env and os.path.isfile(env):
        return env
    on_path = shutil.which("blender")
    if on_path:
        return on_path
    cands = glob.glob(r"C:\Program Files\Blender Foundation\Blender *\blender.exe")
    cands.sort(key=lambda p: [int(x) for x in Path(p).parent.name.split()[-1].split(".") if x.isdigit()])
    return cands[-1] if cands else None


def run(recipe: str, out_dir: str, timeout: int = 300) -> subprocess.CompletedProcess:
    blender = find_blender()
    if blender is None:
        raise FileNotFoundError("no Blender found (set BLENDER_BIN)")
    env = dict(os.environ, PW_OUT=out_dir, PYTHONPATH=str(LIB) + os.pathsep + os.environ.get("PYTHONPATH", ""))
    boot = f"import sys; sys.path.insert(0, {str(LIB)!r})"  # PYTHONPATH alone is not honoured on every build
    cmd = [blender, "-b", "--factory-startup", "--python-exit-code", "1", "--python-expr", boot, "--python", recipe]
    return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout)


def main(argv: list[str]) -> int:
    if not 1 <= len(argv) <= 2:
        print(__doc__)
        return 2
    out = argv[1] if len(argv) == 2 else str(Path(os.environ.get("TEMP", "/tmp")) / "pw_out")
    try:
        res = run(argv[0], out)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    sys.stdout.write(res.stdout)
    sys.stderr.write(res.stderr)
    return res.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
