#!/usr/bin/env python3
"""Generate deterministic pentatonic plucked-string background music loops."""

from __future__ import annotations

import argparse
import wave
from pathlib import Path

import numpy as np


RATE = 8000
SECONDS = 3.0
SAMPLES = int(RATE * SECONDS)
PENTATONIC = np.array([1.0, 9.0 / 8.0, 5.0 / 4.0, 3.0 / 2.0, 5.0 / 3.0, 2.0])


def pluck(freq: float, duration: float, amplitude: float) -> np.ndarray:
    count = max(1, int(duration * RATE))
    t = np.arange(count, dtype=np.float64) / RATE
    attack = np.minimum(1.0, t / 0.006)
    decay = np.exp(-t * 3.8)
    phase = 2.0 * np.pi * freq * t
    tone = (
        0.72 * np.sin(phase)
        + 0.20 * np.sin(phase * 2.01)
        + 0.08 * np.sin(phase * 3.02)
    )
    return amplitude * attack * decay * tone


def make_track(index: int) -> np.ndarray:
    roots = [220.0, 246.94, 261.63, 293.66, 329.63, 349.23, 392.0, 440.0, 196.0, 233.08, 277.18]
    root = roots[index % len(roots)]
    out = np.zeros(SAMPLES + RATE, dtype=np.float64)
    rng = np.random.default_rng(20261101 + index)
    pattern = [0, 2, 4, 3, 1, 5, 4, 2, 0, 3, 5, 1]
    position = 0
    for step in range(16):
        degree = pattern[(step + index * 2) % len(pattern)]
        freq = root * PENTATONIC[degree]
        duration = 0.42 + 0.08 * ((step + index) % 3)
        amp = 0.20 if step % 4 else 0.27
        note = pluck(freq, duration, amp)
        start = position
        out[start : start + len(note)] += note
        if step % 4 == 0:
            drone = pluck(root / 2.0, min(1.2, SECONDS - start / RATE), 0.06)
            out[start : start + len(drone)] += drone
        position += int((0.24 + 0.025 * ((step + index) % 4)) * RATE)
        if position >= SAMPLES - 200:
            break
    # A few quiet plucks create a small-room sense without external assets.
    for delay, gain in ((0.09, 0.16), (0.17, 0.09), (0.29, 0.045)):
        offset = int(delay * RATE)
        out[offset:] += gain * out[:-offset].copy()
    out = out[:SAMPLES]
    fade = int(0.025 * RATE)
    out[:fade] *= np.linspace(0.0, 1.0, fade)
    out[-fade:] *= np.linspace(1.0, 0.0, fade)
    out += rng.normal(0.0, 3.0, size=out.size)
    peak = float(np.max(np.abs(out)))
    if peak > 0:
        out *= 0.72 * 32767.0 / peak
    return np.clip(np.rint(out), -32768, 32767).astype("<i2")


def write_wave(path: Path, samples: np.ndarray) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(samples.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description="生成 11 段五声音阶古典背景音乐")
    parser.add_argument("-o", "--out", type=Path, required=True)
    parser.add_argument("--slots", type=int, default=32)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    tracks = [make_track(index) for index in range(11)]
    for slot in range(1, args.slots + 1):
        track = tracks[min(slot - 1, len(tracks) - 1)]
        write_wave(args.out / f"{slot:02d}.wav", track)
    print(f"生成 11 段古典背景音乐，扩展到 {args.slots} 个卡槽：{args.out.resolve()}")


if __name__ == "__main__":
    main()
