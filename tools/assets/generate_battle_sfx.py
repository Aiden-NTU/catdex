#!/usr/bin/env python3
"""Generate Catdex's CC0-style synthesized battle cues.

These sounds are mathematical waveforms authored for this project; no samples or
third-party recordings are used.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44_100
ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "audio" / "battle"


def write(name: str, duration: float, sample) -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT / name), "wb") as wav:
        wav.setparams((1, 2, RATE, int(duration * RATE), "NONE", "not compressed"))
        frames = bytearray()
        for index in range(int(duration * RATE)):
            time = index / RATE
            envelope = max(0.0, 1.0 - time / duration) ** 2
            value = max(-1.0, min(1.0, sample(time, envelope)))
            frames.extend(struct.pack("<h", int(value * 32767)))
        wav.writeframes(frames)


def main() -> None:
    rng = random.Random(5)
    write(
        "hit.wav",
        0.18,
        lambda t, e: e
        * (0.52 * math.sin(2 * math.pi * (150 - 75 * t) * t) + 0.25 * rng.uniform(-1, 1)),
    )
    write(
        "ability.wav",
        0.48,
        lambda t, e: e
        * (
            0.42 * math.sin(2 * math.pi * (280 + 900 * t) * t)
            + 0.2 * math.sin(2 * math.pi * 560 * t)
        ),
    )
    write(
        "guard.wav",
        0.28,
        lambda t, e: e
        * (0.38 * math.sin(2 * math.pi * 190 * t) + 0.25 * math.sin(2 * math.pi * 380 * t)),
    )
    write(
        "victory.wav",
        0.9,
        lambda t, e: (0.65 + 0.35 * e)
        * 0.28
        * math.sin(2 * math.pi * (523 if t < 0.3 else 659 if t < 0.6 else 784) * t),
    )


if __name__ == "__main__":
    main()
