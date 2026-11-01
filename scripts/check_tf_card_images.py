#!/usr/bin/env python3
"""Validate the FPGA TF-card media package without modifying it."""

from __future__ import annotations

import argparse
import re
import struct
import wave
from pathlib import Path


BMP_RE = re.compile(r"^01(0[1-9]|[12][0-9]|3[0-2])\.BMP$", re.IGNORECASE)
WAV_RE = re.compile(r"^02(0[1-9]|[12][0-9]|3[0-2])\.WAV$", re.IGNORECASE)


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def i32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<i", data, offset)[0]


def check_bmp(path: Path) -> list[str]:
    problems = []
    head = path.read_bytes()[:54]
    if len(head) < 54:
        return ["文件不足 54 字节"]
    if head[:2] != b"BM":
        return ["文件头不是 BM"]
    declared_size = u32(head, 2)
    data_offset = u32(head, 10)
    width = i32(head, 18)
    height = i32(head, 22)
    planes = u16(head, 26)
    bits = u16(head, 28)
    compression = u32(head, 30)
    actual_size = path.stat().st_size
    if width != 640 or height != 480:
        problems.append(f"尺寸 {width}x{height}，要求 640x480")
    if planes != 1:
        problems.append(f"planes={planes}")
    if bits != 24:
        problems.append(f"位深 {bits}，要求 24")
    if compression != 0:
        problems.append(f"压缩方式 {compression}，要求 BI_RGB")
    if data_offset < 54:
        problems.append(f"像素偏移异常 {data_offset}")
    row_bytes = (640 * 3 + 3) // 4 * 4
    required = data_offset + row_bytes * abs(height) if height else 0
    if actual_size < required:
        problems.append(f"文件截断：{actual_size} < {required}")
    if declared_size != actual_size:
        problems.append(f"头部长度 {declared_size} != 实际 {actual_size}")
    return problems


def check_wav(path: Path) -> list[str]:
    problems = []
    size = path.stat().st_size
    header = path.read_bytes()[:44]
    if len(header) != 44:
        return ["文件不足 44 字节"]
    if header[:4] != b"RIFF" or header[8:12] != b"WAVE":
        problems.append("不是 RIFF/WAVE")
    if header[12:16] != b"fmt " or header[36:40] != b"data":
        problems.append("不是规范 44 字节 PCM WAV")
    if u32(header, 4) + 8 != size:
        problems.append("RIFF 长度与文件大小不一致")
    if u16(header, 20) != 1:
        problems.append("编码不是 PCM")
    if u16(header, 22) != 1:
        problems.append("不是单声道")
    if u32(header, 24) != 8000:
        problems.append("采样率不是 8000 Hz")
    if u32(header, 28) != 16000:
        problems.append("byte rate 不是 16000")
    if u16(header, 32) != 2 or u16(header, 34) != 16:
        problems.append("不是 16-bit / block-align 2")
    if u32(header, 40) != size - 44:
        problems.append("data 长度与文件大小不一致")
    if u32(header, 40) > 24576 * 2:
        problems.append("音频超过 24576 个样点（3.072 秒）")
    if size >= 44:
        try:
            with wave.open(str(path), "rb") as wav:
                if wav.getnframes() > 24576:
                    problems.append("wave 帧数超过硬件缓冲")
        except Exception as exc:
            problems.append(f"wave 解析失败：{exc}")
    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description="只读校验 32 图 + 32 WAV 媒体包")
    parser.add_argument("target", type=Path, help="TF 卡根目录或包含媒体包的目录")
    parser.add_argument("--allow-partial", action="store_true", help="允许少于 32 组素材")
    args = parser.parse_args()
    root = args.target.resolve()
    if not root.is_dir():
        raise SystemExit(f"目录不存在：{root}")

    all_files = {p.name.upper(): p for p in root.iterdir() if p.is_file()}
    bmp_names = sorted(name for name in all_files if BMP_RE.fullmatch(name))
    wav_names = sorted(name for name in all_files if WAV_RE.fullmatch(name))
    expected_bmp = {f"{101 + i:04d}.BMP" for i in range(32)}
    expected_wav = {f"{201 + i:04d}.WAV" for i in range(32)}
    missing_bmp = sorted(expected_bmp - set(bmp_names))
    missing_wav = sorted(expected_wav - set(wav_names))

    failures = 0
    print(f"目录：{root}")
    print(f"BMP：{len(bmp_names)}；WAV：{len(wav_names)}")
    if not args.allow_partial and (missing_bmp or missing_wav):
        print(f"缺少 BMP：{', '.join(missing_bmp) or '无'}")
        print(f"缺少 WAV：{', '.join(missing_wav) or '无'}")
        failures += 1
    if bmp_names != sorted(expected_bmp & set(bmp_names)):
        print("发现不在 0101-0132 范围内的 BMP 命名")
        failures += 1
    if wav_names != sorted(expected_wav & set(wav_names)):
        print("发现不在 0201-0232 范围内的 WAV 命名")
        failures += 1

    for name in bmp_names:
        problems = check_bmp(all_files[name])
        print(f"[{'OK' if not problems else 'BAD'}] {name}")
        for problem in problems:
            print(f"      {problem}")
        failures += bool(problems)
    for name in wav_names:
        problems = check_wav(all_files[name])
        print(f"[{'OK' if not problems else 'BAD'}] {name}")
        for problem in problems:
            print(f"      {problem}")
        failures += bool(problems)

    if failures:
        print(f"校验失败，共 {failures} 项问题。")
        raise SystemExit(1)
    print("校验通过。可以把 TF 卡插入开发板。")


if __name__ == "__main__":
    main()
