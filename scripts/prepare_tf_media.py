#!/usr/bin/env python3
"""Prepare the 32-image BMP + 32-narration WAV package for the FPGA TF card."""

from __future__ import annotations

import argparse
import hashlib
import json
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps


SAMPLE_RATE = 8000
MAX_SAMPLES = 24576
IMAGE_EXTS = {".bmp", ".png", ".jpg", ".jpeg", ".webp"}
WAV_EXTS = {".wav", ".wave"}


def sorted_media(folder: Path, extensions: set[str]) -> list[Path]:
    return sorted(
        (p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in extensions),
        key=lambda p: p.name.casefold(),
    )


def read_wave(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as src:
        if src.getcomptype() != "NONE":
            raise ValueError(f"{path.name}: compressed WAV is not supported")
        channels = src.getnchannels()
        width = src.getsampwidth()
        rate = src.getframerate()
        raw = src.readframes(src.getnframes())

    if width == 1:
        samples = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) * 256.0
    elif width == 2:
        samples = np.frombuffer(raw, dtype="<i2").astype(np.float64)
    elif width == 3:
        packed = np.frombuffer(raw, dtype=np.uint8)
        packed = packed[: len(packed) // 3 * 3].reshape(-1, 3).astype(np.int32)
        values = packed[:, 0] | (packed[:, 1] << 8) | (packed[:, 2] << 16)
        samples = np.where(values & 0x800000, values - (1 << 24), values).astype(np.float64)
    elif width == 4:
        samples = np.frombuffer(raw, dtype="<i4").astype(np.float64)
    else:
        raise ValueError(f"{path.name}: unsupported sample width {width * 8} bit")

    if channels > 1:
        samples = samples[: len(samples) // channels * channels].reshape(-1, channels).mean(axis=1)
    elif channels != 1:
        raise ValueError(f"{path.name}: invalid channel count {channels}")
    return samples, rate


def resample_to_8k(samples: np.ndarray, source_rate: int) -> np.ndarray:
    if source_rate == SAMPLE_RATE or samples.size == 0:
        return samples.copy()
    if source_rate > SAMPLE_RATE:
        width = max(1, int(round(source_rate / SAMPLE_RATE)))
        if width > 1:
            samples = np.convolve(samples, np.ones(width) / width, mode="same")
    output_len = max(1, int(round(samples.size * SAMPLE_RATE / source_rate)))
    source_axis = np.arange(samples.size, dtype=np.float64)
    output_axis = np.arange(output_len, dtype=np.float64) * (source_rate / SAMPLE_RATE)
    return np.interp(output_axis, source_axis, samples)


def normalize_narration(samples: np.ndarray, truncate: bool) -> np.ndarray:
    if samples.size > MAX_SAMPLES:
        if not truncate:
            seconds = samples.size / SAMPLE_RATE
            raise ValueError(
                f"narration is {seconds:.3f}s; hardware buffer allows at most "
                f"{MAX_SAMPLES / SAMPLE_RATE:.3f}s (use --truncate only if content loss is acceptable)"
            )
        samples = samples[:MAX_SAMPLES].copy()
    else:
        samples = samples.copy()

    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak > 0:
        samples *= 0.90 * 32767.0 / peak
    fade = min(samples.size // 2, int(SAMPLE_RATE * 0.010))
    if fade > 1:
        samples[:fade] *= np.linspace(0.0, 1.0, fade)
        samples[-fade:] *= np.linspace(1.0, 0.0, fade)
    return np.clip(np.rint(samples), -32768, 32767).astype("<i2")


def write_wave(path: Path, samples: np.ndarray) -> None:
    with wave.open(str(path), "wb") as dst:
        dst.setnchannels(1)
        dst.setsampwidth(2)
        dst.setframerate(SAMPLE_RATE)
        dst.writeframes(samples.tobytes())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="生成 FPGA 使用的 0101-0132.BMP 和 0201-0232.WAV 媒体包"
    )
    parser.add_argument("images", type=Path, help="展品图片目录")
    parser.add_argument("audio", type=Path, help="讲解 WAV 目录，按文件名排序与图片配对")
    parser.add_argument("-o", "--out", required=True, type=Path, help="输出目录")
    parser.add_argument("--limit", type=int, default=32, choices=range(1, 33))
    parser.add_argument(
        "--truncate",
        action="store_true",
        help="超过 3.072 秒时截断；默认报错，避免静默丢失讲解内容",
    )
    args = parser.parse_args()

    images = sorted_media(args.images, IMAGE_EXTS)[: args.limit]
    audio = sorted_media(args.audio, WAV_EXTS)[: args.limit]
    if not images:
        raise SystemExit("没有找到展品图片")
    if len(audio) != len(images):
        raise SystemExit(
            f"图片与音频数量不一致：{len(images)} 张图，{len(audio)} 个 WAV；"
            "请按相同顺序整理后再生成"
        )

    args.out.mkdir(parents=True, exist_ok=True)
    records = []
    for offset, (image_path, audio_path) in enumerate(zip(images, audio)):
        slot = offset + 1
        bmp_name = f"{100 + slot:04d}.BMP"
        wav_name = f"{200 + slot:04d}.WAV"
        bmp_path = args.out / bmp_name
        wav_path = args.out / wav_name

        with Image.open(image_path) as image:
            fitted = ImageOps.fit(
                image.convert("RGB"),
                (640, 480),
                method=Image.Resampling.LANCZOS,
            )
            fitted.save(bmp_path, "BMP")

        samples, source_rate = read_wave(audio_path)
        samples = normalize_narration(resample_to_8k(samples, source_rate), args.truncate)
        write_wave(wav_path, samples)
        records.append(
            {
                "slot": slot,
                "bmp": bmp_name,
                "wav": wav_name,
                "image_source": image_path.name,
                "audio_source": audio_path.name,
                "audio_source_rate": source_rate,
                "audio_samples": int(samples.size),
                "bmp_sha256": sha256(bmp_path),
                "wav_sha256": sha256(wav_path),
            }
        )

    manifest = {
        "format": "FPGA TF media package v1",
        "count": len(records),
        "bmp_contract": "0101.BMP..0132.BMP, 640x480, RGB24, BI_RGB",
        "wav_contract": "0201.WAV..0232.WAV, canonical PCM, 8000 Hz mono s16le, <=24576 samples",
        "items": records,
    }
    (args.out / "media_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"生成完成：{len(records)} 组 BMP/WAV -> {args.out.resolve()}")
    print("上卡前请运行 scripts/check_tf_card_images.py 校验。")


if __name__ == "__main__":
    main()
