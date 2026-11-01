#!/usr/bin/env python3
"""Copy a validated 0101-0132.BMP / 0201-0232.WAV package to a FAT32 TF card."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path


MEDIA_RE = re.compile(
    r"^(?:010[1-9]|01[12][0-9]|013[0-2])\.BMP$|"
    r"^(?:020[1-9]|02[12][0-9]|023[0-2])\.WAV$",
    re.IGNORECASE,
)


def normalize_drive(value: str) -> Path:
    text = value.strip()
    if re.fullmatch(r"[A-Za-z]:", text):
        text += "\\"
    return Path(text)


def main() -> None:
    parser = argparse.ArgumentParser(description="同步 32 图 + 32 WAV 到 TF 卡根目录")
    parser.add_argument("drive", help="TF 卡盘符，例如 E: 或 E:\\")
    parser.add_argument(
        "-s",
        "--source",
        type=Path,
        help="prepare_tf_media.py 的输出目录",
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="只校验源媒体包，不向 TF 卡写入文件",
    )
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    source = (args.source or (repo / "assets_out" / "tf_card")).resolve()
    if not source.is_dir():
        raise SystemExit(f"媒体包目录不存在：{source}")
    if not (source / "media_manifest.json").is_file():
        raise SystemExit("媒体包缺少 media_manifest.json，请先运行 prepare_tf_media.py")

    media = sorted(p for p in source.iterdir() if p.is_file() and MEDIA_RE.fullmatch(p.name))
    print(f"校验媒体包：{source}")
    check = subprocess.run(
        [sys.executable, str(repo / "scripts" / "check_tf_card_images.py"), str(source)],
        check=False,
    )
    if check.returncode != 0:
        raise SystemExit("媒体包校验失败，未向 TF 卡写入任何文件")
    if len(media) != 64:
        raise SystemExit(f"媒体包应有 64 个文件，实际识别到 {len(media)} 个")
    if args.verify_only:
        print("只校验模式完成。")
        return

    target = normalize_drive(args.drive)
    if not target.is_dir():
        raise SystemExit(f"TF 卡盘符不存在：{target}")
    if target.drive.upper().startswith("C:"):
        raise SystemExit("拒绝向系统盘 C: 写入 FPGA 媒体包")

    for item in media:
        destination = target / item.name
        shutil.copy2(item, destination)
        print(f"{item.name} -> {destination}")
    manifest = source / "media_manifest.json"
    shutil.copy2(manifest, target / manifest.name)
    print(f"写入完成：64 个媒体文件。请安全弹出 {target.drive}。")


if __name__ == "__main__":
    main()
