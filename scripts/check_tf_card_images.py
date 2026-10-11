#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
check_tf_card_images.py —— 上板前检查 TF 卡里的图片能不能被工程正确读取

为什么需要它
------------
FPGA 端 bmp_read 对 BMP 的要求很死：640×480、24 位、非压缩，而且它不认扩展名、
只认文件头。图片"能打开"不等于"FPGA 能读"。这个脚本只读不改，几秒就能告诉你
哪张图有问题、问题在哪，避免上板后黑屏/花屏再回头找。

检查内容
--------
1) 文件头是不是 "BM"（PNG/JPG 改名成 .bmp 的，这里就会露馅）
2) 位深是不是 24 位、压缩方式是不是 0（非压缩）
3) 分辨率是不是 640×480（工程的 bmp_width/bmp_height 写死 640/480）
4) 像素数据偏移、文件长度声明值与实际长度是否一致
5) 高度是正还是负：负数代表"自上而下"存储，上板会**上下翻转**
6) 文件数量：工程只扫描前 4 张，多于 4 张的会被忽略

用法
----
    python check_tf_card_images.py E:                  # 检查 E 盘根目录
    python check_tf_card_images.py E:\ --all-dirs      # 连子目录一起查
    python check_tf_card_images.py D:\some\folder      # 也可以直接给文件夹
"""

import argparse
import glob
import os
import struct
import sys

WANT_W, WANT_H = 640, 480

# 防止在中文 Windows 的 GBK 控制台下因为个别字符编码不了而直接崩掉
try:
    sys.stdout.reconfigure(errors="replace")
except Exception:
    pass


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def i32(b, o):
    return struct.unpack_from("<i", b, o)[0]


def check_one(path):
    """返回 (状态, 说明)。状态: OK / WARN / BAD"""
    with open(path, "rb") as f:
        head = f.read(64)
    if len(head) < 54:
        return "BAD", "文件太小，连 54 字节的 BMP 头都不够"
    if head[0:2] != b"BM":
        return "BAD", f"文件头不是 'BM'（是 {head[0:2]!r}），不是标准 BMP"

    file_len_decl = u32(head, 2)
    data_off = u32(head, 10)
    w = i32(head, 18)
    h = i32(head, 22)
    bpp = u16(head, 28)
    comp = u32(head, 30)
    actual = os.path.getsize(path)

    notes = []
    status = "OK"

    if w != WANT_W or abs(h) != WANT_H:
        status = "BAD"
        notes.append(f"分辨率 {w}×{abs(h)}，工程要 {WANT_W}×{WANT_H}")
    if bpp != 24:
        status = "BAD"
        notes.append(f"{bpp} 位，工程要 24 位")
    if comp != 0:
        status = "BAD"
        notes.append(f"压缩方式 {comp}，工程要 0（非压缩）")

    need = data_off + ((w * 3 + 3) // 4) * 4 * abs(h) if w > 0 and h else 0
    if need and actual < need:
        status = "BAD"
        notes.append(f"文件只有 {actual} 字节，按头信息至少需要 {need} 字节（像素数据缺）")
    if file_len_decl and file_len_decl != actual:
        if status == "OK":
            status = "WARN"
        notes.append(f"头部声明长度 {file_len_decl} 与实际 {actual} 不一致")
    if w < 0:
        status = "BAD"
        notes.append("宽度为负，异常")
    if h < 0:
        if status == "OK":
            status = "WARN"
        notes.append("高度为负（自上而下存储），上板可能上下翻转")

    info = f"{w}×{abs(h)}, {bpp}bit, comp={comp}, {actual} 字节"
    return status, info + ("  ；" + "；".join(notes) if notes else "")


def main():
    ap = argparse.ArgumentParser(description="只读检查 TF 卡图片是否符合本工程要求")
    ap.add_argument("target", help="TF 卡盘符（如 E:）或图片文件夹")
    ap.add_argument("--all-dirs", action="store_true",
                    help="连子目录一起检查（FPGA 是按物理扇区扫描的，子目录里的图也会被扫到）")
    args = ap.parse_args()

    root = args.target
    if root.endswith(":") or root.endswith(":\\") or root.endswith(":/"):
        root = root.rstrip("\\/") + os.sep
    if not os.path.exists(root):
        print(f"[错误] 找不到路径：{root}")
        print("       请先确认 TF 卡已插好并在“此电脑”里能看到盘符。")
        sys.exit(1)

    pattern = os.path.join(root, "**", "*.bmp") if args.all_dirs else os.path.join(root, "*.bmp")
    files = sorted(glob.glob(pattern, recursive=args.all_dirs))

    print("=" * 72)
    print(f"目标：{os.path.abspath(root)}")
    print(f"找到 BMP：{len(files)} 个" + ("（含子目录）" if args.all_dirs else "（仅根目录）"))
    print("=" * 72)

    if not files:
        print("没有任何 .bmp 文件 —— FPGA 会一直找不到图片（数码管状态码停在扫描相关值）。")
        sys.exit(2)

    bad = warn = 0
    for i, p in enumerate(files):
        rel = os.path.relpath(p, root)
        try:
            status, info = check_one(p)
        except Exception as e:
            status, info = "BAD", f"读取失败：{e}"
        if status == "BAD":
            bad += 1
        elif status == "WARN":
            warn += 1
        mark = {"OK": "[可用]", "WARN": "[注意]", "BAD": "[不可用]"}[status]
        tag = f"[第 {i+1} 张]" if i < 4 else "[第 5 张起, 会被忽略]"
        print(f"{mark} {tag} {rel}")
        print(f"        {info}")

    print("-" * 72)
    if len(files) > 4:
        print(f"[提示] 共 {len(files)} 张，工程只扫描前 4 张，其余会被忽略。")
    print(f"结论：可用 {len(files) - bad - warn} 张，需注意 {warn} 张，不可用 {bad} 张")

    if bad:
        print("")
        print("不可用的图片请用 scripts/convert_images_to_bmp.py 转成 640×480、24 位、非压缩 BMP。")
    print("")
    print("顺序说明：FPGA 按物理扇区顺序扫描，扫描顺序不一定等于文件名顺序。")
    print("想保证“第 N 张图 ↔ 第 N 段音频”可复现，请用 scripts/sync_to_sd.py 重写一次卡。")
    print("另外：如果卡里以前删过图片，底层扇区可能残留旧图数据，会被误读。")
    print("      换图务必用 sync_to_sd.py（先破坏旧文件头再清空），不要手工删了再拷。")

    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
