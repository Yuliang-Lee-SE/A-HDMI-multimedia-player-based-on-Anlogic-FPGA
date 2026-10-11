#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
gen_test_patterns.py —— 角色 C：生成上板 Bring-up 用的标准测试图

为什么需要它
------------
分工计划阶段 1 要求"用彩条、渐变、棋盘格测试图确认颜色、行列对齐与显示范围"。
手工在画图软件里凑这些图既慢又容易出错（分辨率/位深/翻转方向），
所以统一用脚本生成 640×480、24 位、非压缩 BMP，与工程的 TF 卡读取格式完全一致。

生成的图
--------
    colorbar.bmp      8 级彩条（白黄青绿品红红蓝黑），查颜色通道接反/丢色
    gradient.bmp      横向 R/G/B 渐变 + 纵向灰阶，查位深截断与非线性
    checker.bmp       16px 棋盘格，查行列对齐、像素时钟、是否有丢行
    grid.bmp          带 1px 边框与中线，查显示范围（overscan 是否切断边缘）
    solid_red/green/blue/white/black.bmp   纯色，查单通道与灰度

用法
----
    python gen_test_patterns.py                       # 输出到 assets_out/test_patterns
    python gen_test_patterns.py --out D:\tmp\pattern  # 指定输出目录

依赖：Pillow
"""

import argparse
import os

from PIL import Image, ImageDraw

W, H = 640, 480


def _new():
    return Image.new("RGB", (W, H), (0, 0, 0))


def make_colorbar():
    """8 级彩条 + 底部 1/4 灰阶条"""
    img = _new()
    d = ImageDraw.Draw(img)
    bars = [
        (255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
        (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0),
    ]
    bw = W // len(bars)
    for i, c in enumerate(bars):
        x0 = i * bw
        x1 = W if i == len(bars) - 1 else (i + 1) * bw
        d.rectangle([x0, 0, x1 - 1, H * 3 // 4 - 1], fill=c)

    g0 = H * 3 // 4
    steps = 16
    sw = W // steps
    for i in range(steps):
        g = int(round(i * 255.0 / (steps - 1)))
        x0 = i * sw
        x1 = W if i == steps - 1 else (i + 1) * sw
        d.rectangle([x0, g0, x1 - 1, H - 1], fill=(g, g, g))
    return img


def make_gradient():
    """上半：R/G/B 三段横向渐变；下半：纵向灰阶"""
    img = _new()
    px = img.load()
    half = H // 2
    third = W // 3
    for y in range(half):
        for x in range(W):
            if x < third:
                px[x, y] = (int(x * 255 / (third - 1)), 0, 0)
            elif x < 2 * third:
                px[x, y] = (0, int((x - third) * 255 / (third - 1)), 0)
            else:
                px[x, y] = (0, 0, int((x - 2 * third) * 255 / (W - 2 * third - 1)))
    for y in range(half, H):
        v = int((y - half) * 255 / (H - half - 1))
        for x in range(W):
            px[x, y] = (v, v, v)
    return img


def make_checker(cell=16):
    """棋盘格：默认 16px 一格，640/16=40 列、480/16=30 行，格数整除便于数格子"""
    img = _new()
    px = img.load()
    for y in range(H):
        row = (y // cell) % 2
        for x in range(W):
            col = (x // cell) % 2
            v = 255 if (row ^ col) else 0
            px[x, y] = (v, v, v)
    return img


def make_grid():
    """1px 白色边框 + 中线 + 四角方块：查显示范围与对齐"""
    img = _new()
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(255, 255, 255), width=1)
    d.line([W // 2, 0, W // 2, H - 1], fill=(255, 255, 255))
    d.line([0, H // 2, W - 1, H // 2], fill=(255, 255, 255))
    s = 24
    for (x, y) in [(0, 0), (W - s, 0), (0, H - s), (W - s, H - s)]:
        d.rectangle([x, y, x + s - 1, y + s - 1], fill=(255, 255, 255))
    d.rectangle([W // 2 - 8, H // 2 - 8, W // 2 + 7, H // 2 + 7], fill=(255, 0, 0))
    return img


def main():
    ap = argparse.ArgumentParser(description="生成 640x480 24bit 非压缩 BMP 测试图")
    ap.add_argument("--out", default=os.path.join("assets_out", "test_patterns"),
                    help="输出目录（默认 assets_out/test_patterns）")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)

    images = {
        "colorbar.bmp": make_colorbar(),
        "gradient.bmp": make_gradient(),
        "checker.bmp": make_checker(),
        "grid.bmp": make_grid(),
        "solid_red.bmp": Image.new("RGB", (W, H), (255, 0, 0)),
        "solid_green.bmp": Image.new("RGB", (W, H), (0, 255, 0)),
        "solid_blue.bmp": Image.new("RGB", (W, H), (0, 0, 255)),
        "solid_white.bmp": Image.new("RGB", (W, H), (255, 255, 255)),
        "solid_black.bmp": Image.new("RGB", (W, H), (0, 0, 0)),
    }

    for name, img in images.items():
        path = os.path.join(args.out, name)
        # BMP 默认就是 24bit 非压缩；每行 1920 字节已是 4 字节对齐，无额外填充
        img.save(path, "BMP")
        print(f"[生成] {path}  {img.size[0]}x{img.size[1]} 24bit")

    print("")
    print(f"[完成] 共 {len(images)} 张，目录：{os.path.abspath(args.out)}")
    print("       拷到 TF 卡前记得先用 scripts/sync_to_sd.py 清残留")


if __name__ == "__main__":
    main()
