#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
wav_to_speech_rom.py —— 角色 C：把讲解音频转成 FPGA 片内 ROM 的初始化文件（MIF）

用途
----
给 `audio_rom_player.v` + `AUDIO_SPEECH_ROM`（8bit × 49152 = 48KB）准备素材。
EG4S20 片上 RAM 只有约 136KB，装不下整首音乐或长时间语音，所以本工程采用
"每张展品配一段短讲解"的做法：

    4 段 × 12288 样点 @ 8kHz = 1.536 秒/段，共 49152 样点 = 48KB
    段偏移：0 / 12288 / 24576 / 36864

处理链路：读 WAV -> 混单声道 -> 简单抗混叠 -> 重采样到 8kHz -> 归一化
          -> 量化成 signed 8bit -> 定长截断/补零 -> 拼成 MIF

用法
----
    # 1) 用自己的讲解录音（每个展品一个文件，按 1/2/3/4 顺序）
    python wav_to_speech_rom.py seg1.wav seg2.wav seg3.wav seg4.wav \
        -o ..\lab_ex5_i2s\src\user_source\hdl_source\team\audio_speech_rom.mif

    # 2) 整个目录（按文件名排序取排序后的前 4 个）
    python wav_to_speech_rom.py .\my_speech --out <mif 路径>

    # 3) 演示音：不需要任何素材，直接合成 4 段可区分的测试音
    python wav_to_speech_rom.py --demo --out <mif 路径>

依赖：numpy（Pillow 之外本项目额外需要的唯一库）
"""

import argparse
import math
import os
import sys
import wave

import numpy as np

# ----------------------------------------------------------------------
# 与 RTL 对齐的常量：改这里必须同步改 audio_rom_player 的 SEG_SAMPLES /
# AUDIO_SPEECH_ROM.ipc 的 depth_a，以及 top 里的 TRACK*_ADDR
# ----------------------------------------------------------------------
SRC_HZ = 8000
SEG_SAMPLES = 12288
SEG_COUNT = 4
ROM_DEPTH = SEG_SAMPLES * SEG_COUNT


def read_wav_mono(path):
    """读 WAV -> float64 单声道波形（幅度与原始位深同量纲），返回 (data, sr)"""
    with wave.open(path, "rb") as wf:
        nch = wf.getnchannels()
        sw = wf.getsampwidth()
        sr = wf.getframerate()
        nfr = wf.getnframes()
        raw = wf.readframes(nfr)

    if sw == 1:                                  # 8bit 无符号
        a = np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0
        a *= 256.0
    elif sw == 2:                                # 16bit
        a = np.frombuffer(raw, dtype="<i2").astype(np.float64)
    elif sw == 3:                                # 24bit
        b = np.frombuffer(raw, dtype=np.uint8)
        b = b[: (len(b) // 3) * 3].reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v & 0x800000, v - (1 << 24), v)
        a = v.astype(np.float64)
    elif sw == 4:                                # 32bit
        a = np.frombuffer(raw, dtype="<i4").astype(np.float64)
    else:
        raise ValueError(f"{path}: 不支持的位宽 {sw * 8}bit")

    if nch > 1:
        a = a[: (len(a) // nch) * nch].reshape(-1, nch).mean(axis=1)
    elif nch < 1:
        raise ValueError(f"{path}: 声道数异常")

    return a, sr


def resample_to_8k(a, sr):
    """重采样到 8kHz。先用移动平均做粗略抗混叠（降采样倍数较大时），再线性插值。"""
    if sr == SRC_HZ or len(a) == 0:
        return a.copy()

    if sr > SRC_HZ:
        k = max(1, int(round(sr / SRC_HZ)))
        if k > 1:
            kernel = np.ones(k) / k
            a = np.convolve(a, kernel, mode="same")

    n_out = int(round(len(a) * SRC_HZ / float(sr)))
    if n_out <= 0:
        return np.zeros(0, dtype=np.float64)
    t_in = np.arange(len(a), dtype=np.float64)
    t_out = np.arange(n_out, dtype=np.float64) * (sr / float(SRC_HZ))
    return np.interp(t_out, t_in, a)


def fit_segment(a, fade_ms=10, normalize=0.90):
    """定长到 SEG_SAMPLES：超长从头部截断，不足补零；边缘加淡入淡出；归一化后量化。"""
    seg = np.zeros(SEG_SAMPLES, dtype=np.float64)
    n = min(len(a), SEG_SAMPLES)
    if n > 0:
        seg[:n] = a[:n]

    # 归一化到指定峰值，保证 8bit 量化后音量一致、可闻
    peak = float(np.max(np.abs(seg))) if n > 0 else 0.0
    full = float(1 << 15)                        # 以 16bit 满量程为参考
    if peak > 0:
        seg *= (normalize * full) / peak

    # 10ms 淡入淡出，避免切段时的爆音与边界突变
    fade = int(SRC_HZ * fade_ms / 1000.0)
    if fade > 1 and n > 0:
        r = np.linspace(0.0, 1.0, fade)
        seg[:fade] = seg[:fade] * r
        seg[-fade:] = seg[-fade:] * r[::-1]

    q = np.clip(np.round(seg / 256.0), -128, 127).astype(np.int8)
    return q


# ----------------------------------------------------------------------
# --demo：合成 4 段音色差别明显的测试音，用于没有素材时先打通全链路
# ----------------------------------------------------------------------
def demo_segments():
    t = np.arange(SEG_SAMPLES, dtype=np.float64) / SRC_HZ
    segs = []

    segs.append(np.sin(2 * math.pi * 440.0 * t))                       # 1: 单音 A4
    segs.append(0.6 * np.sin(2 * math.pi * 523.25 * t)
                + 0.6 * np.sin(2 * math.pi * 659.25 * t))              # 2: 三度和音
    f = np.linspace(300.0, 1200.0, SEG_SAMPLES)                        # 3: 上扫频
    segs.append(np.sin(2 * math.pi * np.cumsum(f) / SRC_HZ))
    segs.append(np.sin(2 * math.pi * 1000.0 * t)
                * (0.5 + 0.5 * np.sin(2 * math.pi * 4.0 * t)))         # 4: 颤音

    return [np.asarray(s, dtype=np.float64) for s in segs]


def to_s8_hex(v):
    return f"{(int(v) & 0xFF):02X}"


def write_mif(path, samples_i8):
    out_dir = os.path.dirname(os.path.abspath(path))
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    lines = [
        f"WIDTH=8;",
        f"DEPTH={ROM_DEPTH};",
        "",
        "ADDRESS_RADIX=UNS;",
        "DATA_RADIX=HEX;",
        "",
        "CONTENT BEGIN",
    ]
    for addr, v in enumerate(samples_i8):
        lines.append(f"{addr} : {to_s8_hex(v)};")
    lines.append("END;")
    lines.append("")

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def collect_inputs(args):
    """把命令行给的文件/目录整理成最多 4 个 WAV 路径"""
    paths = []
    for item in args.inputs:
        if os.path.isdir(item):
            for name in sorted(os.listdir(item)):
                if name.lower().endswith((".wav", ".wave")):
                    paths.append(os.path.join(item, name))
        else:
            paths.append(item)
    return paths


def main():
    ap = argparse.ArgumentParser(
        description="WAV -> FPGA 片内语音 ROM 的 MIF（4 段 × 12288 样点 @ 8kHz signed 8bit）"
    )
    ap.add_argument("inputs", nargs="*", help="WAV 文件或包含 WAV 的目录（按顺序对应第 1~4 张展品）")
    ap.add_argument("-o", "--out", required=True, help="输出 MIF 路径")
    ap.add_argument("--demo", action="store_true", help="不用素材，合成 4 段测试音")
    ap.add_argument("--no-normalize", action="store_true", help="关闭逐段归一化（保留原始相对音量）")
    args = ap.parse_args()

    normalize = 0.0 if args.no_normalize else 0.90

    if args.demo:
        print("== demo 模式：合成 4 段测试音（440Hz / 和音 / 扫频 / 颤音）==")
        raw = demo_segments()
    else:
        paths = collect_inputs(args)
        if not paths:
            ap.error("没有输入素材；要么给 WAV 文件/目录，要么用 --demo")
        if len(paths) > SEG_COUNT:
            print(f"[提示] 提供了 {len(paths)} 个素材，只使用前 {SEG_COUNT} 个")
            paths = paths[:SEG_COUNT]

        raw = []
        for p in paths:
            a, sr = read_wav_mono(p)
            dur = len(a) / float(sr) if sr else 0.0
            a = resample_to_8k(a, sr)
            print(f"[读入] {os.path.basename(p)}: {sr}Hz/{dur:.2f}s -> 8kHz/{len(a)} 样点")
            raw.append(a)

    while len(raw) < SEG_COUNT:
        print(f"[补零] 第 {len(raw) + 1} 段没有素材，写静音")
        raw.append(np.zeros(SEG_SAMPLES, dtype=np.float64))

    samples = np.concatenate([fit_segment(a, normalize=normalize) for a in raw[:SEG_COUNT]])
    write_mif(args.out, samples)

    print("")
    print(f"[完成] {args.out}")
    print(f"       WIDTH=8, DEPTH={ROM_DEPTH}, 每段 {SEG_SAMPLES} 样点（{SEG_SAMPLES / SRC_HZ:.3f}s @ {SRC_HZ}Hz）")
    print("       段偏移表（top 里的 TRACK*_ADDR 必须与之一致）：")
    for i in range(SEG_COUNT):
        print(f"         TRACK{i}_ADDR = {i * SEG_SAMPLES}")


if __name__ == "__main__":
    main()
