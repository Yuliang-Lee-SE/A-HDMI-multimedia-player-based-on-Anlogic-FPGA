"""Reproduce the RTL FFT over the checked-in audio ROM."""

from __future__ import annotations

import re
from pathlib import Path


N = 32
COS = [32767, 32138, 30274, 27246, 23170, 18205, 12540, 6393,
       0, -6393, -12540, -18205, -23170, -27246, -30274, -32138]
SIN = [0, 6393, 12540, 18205, 23170, 27246, 30274, 32138,
       32767, 32138, 30274, 27246, 23170, 18205, 12540, 6393]


def signed16(value: int) -> int:
    value &= 0xFFFF
    return value - 65536 if value & 0x8000 else value


def bit_reverse5(value: int) -> int:
    return int(f"{value:05b}"[::-1], 2)


def fft_magnitudes(samples: list[int]) -> list[int]:
    real = [0] * N
    imag = [0] * N
    for index, sample in enumerate(samples):
        real[bit_reverse5(index)] = sample * 256

    half_len = 1
    tw_step = 8
    for stage in range(1, 6):
        for group_base in range(0, N, 2 * half_len):
            for j in range(half_len):
                tw_index = j if stage == 5 else j * tw_step
                tw_index &= 15
                ar, ai = real[group_base + j], imag[group_base + j]
                br = real[group_base + j + half_len]
                bi = imag[group_base + j + half_len]
                tr = ((br * COS[tw_index]) >> 15) + (
                    (bi * SIN[tw_index]) >> 15
                )
                ti = ((bi * COS[tw_index]) >> 15) - (
                    (br * SIN[tw_index]) >> 15
                )
                real[group_base + j] = signed16((ar + tr) >> 1)
                imag[group_base + j] = signed16((ai + ti) >> 1)
                real[group_base + j + half_len] = signed16((ar - tr) >> 1)
                imag[group_base + j + half_len] = signed16((ai - ti) >> 1)
        half_len *= 2
        if stage != 1:
            tw_step //= 2
    return [abs(re) + abs(im) for re, im in zip(real[:16], imag[:16])]


def spectrum_bars_rtl(samples: list[int]) -> list[int]:
    """Q1.15 model of the current sequential 16-bin DFT implementation."""
    bars = []
    for bin_index in range(16):
        acc_re = 0
        acc_im = 0
        for point_index, sample in enumerate(samples):
            phase = point_index * bin_index & 31
            cos_value = COS[phase] if phase < 16 else -COS[phase - 16]
            sin_value = SIN[phase] if phase < 16 else -SIN[phase - 16]
            sample_q = sample * 256
            acc_re += (sample_q * cos_value) >> 15
            acc_im -= (sample_q * sin_value) >> 15
        magnitude = (abs(acc_re) + abs(acc_im)) >> 5
        target = 255 if magnitude >= 32768 else (magnitude >> 7) & 0xFF
        bars.append(target)
    return bars


def load_rom(path: Path) -> list[int]:
    values: list[int] = []
    for line in path.read_text(errors="ignore").splitlines():
        match = re.match(r"\s*(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;", line)
        if match:
            value = int(match.group(2), 16)
            values.append(value - 256 if value >= 128 else value)
    return values


def main() -> None:
    rom_path = Path(__file__).parent / "src/user_source/hdl_source/team/audio_speech_rom.mif"
    values = load_rom(rom_path)
    print(f"ROM samples: {len(values)}")
    for segment in range(4):
        offset = segment * 12288
        print(f"segment {segment}")
        for frame in range(0, 12288 * 6 - 512, 60000):
            source = [
                offset + min(12287, frame // 6 + (16 * n) // 6)
                for n in range(32)
            ]
            samples = [values[index] for index in source]
            magnitudes = fft_magnitudes(samples)
            targets = [min(255, magnitude // 128) for magnitude in magnitudes]
            rtl_bars = spectrum_bars_rtl(samples)
            peaks = sorted(range(16), key=targets.__getitem__, reverse=True)[:4]
            print(
                f"  frame={frame:6d} dc={sum(samples) / 32:7.1f} "
                f"peaks={peaks} targets={[targets[i] for i in peaks]} "
                f"bars={[targets[i] // 2 for i in peaks]} "
                f"rtl_nonzero={sum(value != 0 for value in rtl_bars)}"
            )
            print(f"    rtl_bars={rtl_bars}")


if __name__ == "__main__":
    main()
