#!/usr/bin/env python3
"""Extract stable 3-second background-music windows from an audio file."""

from __future__ import annotations

import argparse
import subprocess
import wave
from pathlib import Path

import numpy as np


RATE = 8000
DURATION = 3.0
WINDOW = int(RATE * DURATION)


def decode_mono(path: Path, ffmpeg: Path) -> np.ndarray:
    result = subprocess.run(
        [
            str(ffmpeg),
            "-v",
            "error",
            "-i",
            str(path),
            "-ac",
            "1",
            "-ar",
            str(RATE),
            "-f",
            "f32le",
            "pipe:1",
        ],
        check=True,
        stdout=subprocess.PIPE,
    )
    return np.frombuffer(result.stdout, dtype="<f4").astype(np.float64)


def choose_windows(samples: np.ndarray, count: int) -> list[int]:
    usable_end = len(samples) - WINDOW - RATE * 5
    if usable_end <= RATE * 5:
        raise RuntimeError("audio is too short for 3-second background loops")
    candidates = list(range(RATE * 5, usable_end, RATE // 2))
    scores = []
    for start in candidates:
        window = samples[start : start + WINDOW]
        rms = float(np.sqrt(np.mean(window * window)))
        blocks = window[: WINDOW // 8 * 8].reshape(8, -1)
        block_rms = np.sqrt(np.mean(blocks * blocks, axis=1))
        stability = float(np.std(block_rms))
        edges = abs(float(window[0])) + abs(float(window[-1]))
        scores.append(rms - 0.9 * stability - 0.2 * edges)
    scores = np.asarray(scores)
    chosen = []
    span = len(samples) - 2 * RATE * 5 - WINDOW
    for index in range(count):
        target = RATE * 5 + int((index + 0.5) * span / count)
        local = [
            (position, candidates[position], scores[position])
            for position in range(len(candidates))
            if abs(candidates[position] - target) <= RATE * 12
            and all(abs(candidates[position] - value) > WINDOW * 2 for value in chosen)
        ]
        if not local:
            local = [
                (position, candidates[position], scores[position])
                for position in range(len(candidates))
                if all(abs(candidates[position] - value) > WINDOW * 2 for value in chosen)
            ]
        if not local:
            raise RuntimeError("unable to choose non-overlapping music windows")
        chosen.append(max(local, key=lambda item: item[2])[1])
    return sorted(chosen)


def prepare_window(samples: np.ndarray, start: int) -> np.ndarray:
    window = samples[start : start + WINDOW].copy()
    window -= float(np.mean(window))
    fade = int(0.025 * RATE)
    window[:fade] *= np.linspace(0.0, 1.0, fade)
    window[-fade:] *= np.linspace(1.0, 0.0, fade)
    peak = float(np.max(np.abs(window)))
    if peak > 0:
        window *= 0.62 * 32767.0 / peak
    return np.clip(np.rint(window), -32768, 32767).astype("<i2")


def write_wave(path: Path, samples: np.ndarray) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(samples.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description="从 M4A/MP3 提取 3 秒背景音乐循环")
    parser.add_argument("input", type=Path)
    parser.add_argument("-o", "--out", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--segments", type=int, default=11)
    parser.add_argument("--slots", type=int, default=32)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    samples = decode_mono(args.input, args.ffmpeg)
    starts = choose_windows(samples, args.segments)
    tracks = [prepare_window(samples, start) for start in starts]
    for slot in range(1, args.slots + 1):
        track = tracks[(slot - 1) % len(tracks)]
        write_wave(args.out / f"{slot:02d}.wav", track)
    print("Music windows (seconds):", ", ".join(f"{start / RATE:.2f}" for start in starts))
    print(f"Wrote {args.slots} 8 kHz mono s16 files to {args.out.resolve()}")


if __name__ == "__main__":
    main()
