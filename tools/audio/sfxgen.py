#!/usr/bin/env python3
"""Offline SFX synth (docs/07 s8.4, ART-22). Stdlib only; own PRNG, so an identical recipe gives
identical WAV bytes (mono, 22.05 kHz, PCM16).

    python tools/audio/sfxgen.py tools/audio/recipes/foo.json --out build/audio
    python tools/audio/sfxgen.py --validate tools/audio/recipes/*.json

Writes <id>.wav and <id>.json (metadata: seed, sha256 of the WAV, analyzer metrics).
Exit 0 ok, 1 recipe invalid.

Note: math.sin/pow are libm calls; a last-ulp difference between platforms is removed by the
PCM16 rounding in practice. A cross-platform hash pin in CI is deferred to ART-23.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from schemalite import SchemaStore, Validator  # noqa: E402

SCHEMA_DIR = HERE.parent / "schemas"
SAMPLE_RATE = 22050
MASK64 = (1 << 64) - 1


class Rng:
    """splitmix64: pure integer arithmetic, identical on every platform."""

    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next_u64(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return z ^ (z >> 31)

    def uniform(self) -> float:
        """[-1, 1) with 53 bits."""
        return (self.next_u64() >> 11) / float(1 << 52) - 1.0


def _layer_len(layer: dict) -> float:
    return layer.get("delay", 0.0) + layer.get("attack", 0.0) + layer.get("sustain", 0.0) + layer.get("decay", 0.0)


def _length(recipe: dict) -> float:
    return max(_layer_len(layer) for layer in recipe["layers"])


def validate_recipe(recipe: object) -> list[str]:
    store = SchemaStore(SCHEMA_DIR)
    schema = store.load("sfx_recipe.schema.json")
    errs = [f"{p or '/'}: {m}" for p, m in Validator(store).validate(recipe, schema, "sfx_recipe.schema.json")]
    if not errs and isinstance(recipe, dict):
        for n, layer in enumerate(recipe["layers"]):
            if layer["wave"] != "noise" and "f0" not in layer:
                errs.append(f"/layers/{n}: wave '{layer['wave']}' needs f0")
        if recipe.get("loop") and _length(recipe) < 2 * recipe.get("loop_crossfade_ms", 50) / 1000.0:
            errs.append("/loop_crossfade_ms: longer than half the sound")
    return errs


def _render_layer(layer: dict, n_total: int, sr: int, rng: Rng) -> list[float]:
    out = [0.0] * n_total
    start = int(round(layer.get("delay", 0.0) * sr))
    att, sus, dec = layer.get("attack", 0.0), layer.get("sustain", 0.0), layer.get("decay", 0.0)
    n = max(0, min(int(round((att + sus + dec) * sr)), n_total - start))
    kind = layer["wave"]
    f0 = layer.get("f0", 440.0)
    slope = layer.get("f_slope", 0.0)
    vib_hz, vib_d = layer.get("vibrato_hz", 0.0), layer.get("vibrato_depth", 0.0)
    gain = layer.get("gain", 1.0)
    bits = layer.get("bitcrush")
    levels = float(1 << (bits - 1)) if bits else 0.0
    na, nd = att * sr, dec * sr
    lp, hp = layer.get("lowpass"), layer.get("highpass")
    a_lp = 1.0 - math.exp(-2.0 * math.pi * lp / sr) if lp else 1.0
    a_hp = math.exp(-2.0 * math.pi * hp / sr) if hp else 0.0
    lp1 = lp2 = hp_y = hp_x = phase = 0.0
    for i in range(n):
        t = i / sr
        if kind == "noise":
            s = rng.uniform()
        else:
            f = f0 * math.pow(2.0, slope * t)
            if vib_hz > 0.0:
                f *= 1.0 + vib_d * math.sin(2.0 * math.pi * vib_hz * t)
            phase += f / sr
            phase -= math.floor(phase)
            if kind == "sine":
                s = math.sin(2.0 * math.pi * phase)
            elif kind == "square":
                s = 1.0 if phase < 0.5 else -1.0
            else:
                s = 2.0 * phase - 1.0
        if lp:
            lp1 += a_lp * (s - lp1)
            lp2 += a_lp * (lp1 - lp2)
            s = lp2
        if hp:
            hp_y = a_hp * (hp_y + s - hp_x)
            hp_x = s
            s = hp_y
        if levels:
            s = math.floor(s * levels + 0.5) / levels
        env = 1.0
        if na > 0 and i < na:
            env = i / na
        if nd > 0 and i > n - nd:
            env = min(env, max(0.0, (n - i) / nd))
        out[start + i] = s * env * gain
    return out


def render(recipe: dict) -> list[float]:
    """Float samples before PCM16 quantisation."""
    sr = recipe.get("sample_rate", SAMPLE_RATE)
    fade = int(round(recipe.get("loop_crossfade_ms", 50) / 1000.0 * sr)) if recipe.get("loop") else 0
    n_main = int(round(_length(recipe) * sr))
    n_total = n_main + fade
    mix = [0.0] * n_total
    for idx, layer in enumerate(recipe["layers"]):
        rng = Rng(recipe["seed"] * 1000003 + idx)
        if fade:  # let the layer run on past the loop point to supply the cross-fade continuation
            layer = dict(layer, sustain=layer.get("sustain", 0.0) + fade / sr)
        for i, v in enumerate(_render_layer(layer, n_total, sr, rng)):
            mix[i] += v
    if fade:
        # The extra `fade` tail samples continue the signal past the loop point; blending them
        # into the head makes the last sample lead smoothly into the first.
        for i in range(fade):
            w = (i + 1) / (fade + 1)
            mix[i] = mix[i] * w + mix[n_main + i] * (1.0 - w)
        mix = mix[:n_main]
    target = recipe.get("normalize_peak_db")
    if target is not None:
        peak = max((abs(v) for v in mix), default=0.0)
        if peak > 0.0:
            k = math.pow(10.0, target / 20.0) / peak
            mix = [v * k for v in mix]
    return mix


def to_pcm16(samples: list[float]) -> bytes:
    ints = [max(-32768, min(32767, int(math.floor(v * 32768.0 + 0.5)))) for v in samples]
    return struct.pack(f"<{len(ints)}h", *ints)


def write_wav(path: Path, pcm: bytes, sr: int = SAMPLE_RATE) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm)


def render_file(recipe: dict, out_dir: Path) -> tuple[Path, str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    wav = out_dir / f"{recipe['id']}.wav"
    write_wav(wav, to_pcm16(render(recipe)), recipe.get("sample_rate", SAMPLE_RATE))
    return wav, hashlib.sha256(wav.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Render SFX recipes to WAV (07 s8.4).")
    ap.add_argument("recipes", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, default=Path("build/audio"))
    ap.add_argument("--validate", action="store_true", help="schema-check only")
    args = ap.parse_args(argv)
    import analyze

    bad = 0
    for path in args.recipes:
        try:
            recipe = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"{path}:1: {exc}")
            bad += 1
            continue
        errs = validate_recipe(recipe)
        if errs:
            bad += 1
            print("\n".join(f"{path}:1: {e}" for e in errs))
            continue
        if args.validate:
            continue
        wav, digest = render_file(recipe, args.out)
        meta = {"id": recipe["id"], "seed": recipe["seed"], "sha256": digest, "metrics": analyze.analyze_wav(wav)}
        (args.out / f"{recipe['id']}.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"{wav} sha256={digest[:12]}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
