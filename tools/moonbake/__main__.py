"""Entry point: `python -I tools/moonbake <bake|validate|preview|ramp> ...`.

`python -I -m moonbake` (docs/03 s8) needs the package on sys.path, which -I forbids; running the directory
works with -I because Python puts the directory itself on the path, so this file adds its parent.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from moonbake.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
