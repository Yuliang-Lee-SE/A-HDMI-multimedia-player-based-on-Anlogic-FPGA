#!/usr/bin/env python3
"""Convert exhibit images to 640x480 RGB24 uncompressed BMP files."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageOps


EXTS = {".bmp", ".png", ".jpg", ".jpeg", ".webp", ".gif"}


def convert_one(source: Path, destination: Path) -> None:
    with Image.open(source) as image:
        fitted = ImageOps.fit(
            image.convert("RGB"),
            (640, 480),
            method=Image.Resampling.LANCZOS,
        )
        fitted.save(destination, "BMP")


def convert_batch(source: Path, destination: Path, start_index: int, limit: int) -> None:
    files = sorted(
        (p for p in source.iterdir() if p.is_file() and p.suffix.lower() in EXTS),
        key=lambda p: p.name.casefold(),
    )[:limit]
    if not files:
        raise SystemExit(f"{source} 中没有找到支持的图片")
    destination.mkdir(parents=True, exist_ok=True)
    for offset, item in enumerate(files):
        output = destination / f"{start_index + offset:04d}.BMP"
        convert_one(item, output)
        print(f"{item.name} -> {output.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="转换为 640x480、24-bit、非压缩 BMP")
    parser.add_argument("input", nargs="?", type=Path, help="单张源图片或批量源目录")
    parser.add_argument("output", nargs="?", type=Path, help="单张输出路径或批量输出目录")
    parser.add_argument("--start-index", type=int, default=101, help="批量首个编号，默认 101")
    parser.add_argument("--limit", type=int, default=32, help="批量最多转换张数")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    source = args.input or (repo / "input_images")
    destination = args.output or (repo / "assets_out" / "tf_card")
    if source.is_file():
        target = destination
        if target.suffix.lower() != ".bmp":
            target = target.with_suffix(".BMP")
        target.parent.mkdir(parents=True, exist_ok=True)
        convert_one(source, target)
        print(f"{source} -> {target}")
        return
    if not source.is_dir():
        if args.input is None:
            source.mkdir(parents=True, exist_ok=True)
            print(f"已创建 {source}，请放入展品图片后重试。")
            return
        raise SystemExit(f"输入路径不存在：{source}")
    convert_batch(source, destination, args.start_index, args.limit)


if __name__ == "__main__":
    main()
