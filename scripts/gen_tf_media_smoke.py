#!/usr/bin/env python3
"""Generate a 32-pair board-smoke package for the image/WAV scheduler."""

from __future__ import annotations

import argparse
import json
import math
import struct
import wave
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def color(index: int) -> tuple[int, int, int]:
    palette = [
        (242, 87, 87), (242, 154, 74), (224, 196, 56), (114, 196, 73),
        (72, 187, 150), (66, 168, 220), (83, 113, 220), (151, 91, 210),
    ]
    return palette[(index - 1) % len(palette)]


def make_image(path: Path, index: int, font_path: Path | None) -> None:
    image = Image.new("RGB", (640, 480), color(index))
    draw = ImageDraw.Draw(image)
    for y in range(0, 480, 32):
        shade = 24 if (y // 32 + index) % 2 else 0
        draw.rectangle((0, y, 639, y + 31), fill=tuple(min(255, c + shade) for c in color(index)))
    draw.rectangle((24, 24, 616, 456), outline=(255, 255, 255), width=4)
    if font_path and font_path.exists():
        font = ImageFont.truetype(str(font_path), 160)
        label_font = ImageFont.truetype(str(font_path), 32)
    else:
        font = ImageFont.load_default()
        label_font = font
    text = f"{index:02d}"
    box = draw.textbbox((0, 0), text, font=font)
    draw.text(
        ((640 - (box[2] - box[0])) // 2, (480 - (box[3] - box[1])) // 2 - 20),
        text,
        font=font,
        fill=(255, 255, 255),
        stroke_width=4,
        stroke_fill=(20, 24, 32),
    )
    draw.text((40, 400), f"IMAGE {index:02d}", fill=(255, 255, 255), font=label_font)
    image.save(path, "BMP")


def make_wave(path: Path, index: int) -> None:
    rate = 8000
    samples = 7200
    frequency = 280 + index * 48
    frames = bytearray()
    for n in range(samples):
        envelope = min(1.0, n / 80.0, (samples - 1 - n) / 80.0)
        value = int(0.35 * 32767 * envelope * math.sin(2 * math.pi * frequency * n / rate))
        frames += struct.pack("<h", value)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(frames)


def main() -> None:
    parser = argparse.ArgumentParser(description="生成 32 图 + 32 WAV 上板烟雾测试包")
    parser.add_argument("-o", "--out", type=Path, required=True)
    parser.add_argument("--font", type=Path, default=Path("C:/Windows/Fonts/simhei.ttf"))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    items = []
    for slot in range(1, 33):
        bmp_name = f"{100 + slot:04d}.BMP"
        wav_name = f"{200 + slot:04d}.WAV"
        make_image(args.out / bmp_name, slot, args.font)
        make_wave(args.out / wav_name, slot)
        items.append({"slot": slot, "bmp": bmp_name, "wav": wav_name, "tone_hz": 280 + slot * 48})
    manifest = {
        "format": "FPGA TF media smoke package",
        "count": 32,
        "warning": "Synthetic test images and tones only; replace with formal exhibit media.",
        "items": items,
    }
    (args.out / "media_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"生成 32 组烟雾测试素材：{args.out.resolve()}")


if __name__ == "__main__":
    main()
