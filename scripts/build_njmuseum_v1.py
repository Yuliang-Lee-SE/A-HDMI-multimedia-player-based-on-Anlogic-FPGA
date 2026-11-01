#!/usr/bin/env python3
"""Build the initial 32-item Nanjing Museum media source package."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps


API = "https://www.njmuseum.com/api/collection/info/desc"
IMAGE_ROOT = "https://www.njmuseum.com"
PAGE = "https://www.njmuseum.com/zh/collectionDetails?id={id}"
CAPTION_TAILS = {
    "object": "，造型与纹饰自成一格，体现古代工匠技艺与生活审美。",
    "textile": "，织绣针法与色彩层次相映，呈现细腻含蓄的东方审美。",
    "painting": "，笔墨章法与意境各具面貌，展现传统艺术的悠远气韵。",
    "document": "，文字版式承载时代记忆，具有珍贵史料与民俗价值。",
}

# Titles are limited to 16 glyphs and captions to 64 glyphs by the FPGA OSD.
ITEMS = [
    (171, "西汉金兽", "西汉黄金铸器，重九千克。", "西汉金兽，通体斑纹，重达九千克。"),
    (172, "战国郢爰", "楚国黄金货币。", "战国郢爰，楚国黄金货币，钤有郢爰印记。"),
    (14883, "铜牛灯", "东汉错银灯具，烟尘入水。", "东汉错银铜牛灯，烟尘经烟管进入腹腔水中。"),
    (465, "砖画", "南朝名士画像砖。", "南朝砖画，描绘竹林七贤与荣启期。"),
    (405, "梅瓶", "明代釉里红瓷。", "洪武釉里红梅瓶，腹部绘岁寒三友。"),
    (105, "香炉", "明代官窑寿山福海纹。", "明代青花香炉，仿青铜鼎，寿山福海纹浓重。"),
    (979, "天球瓶", "清乾隆蓝釉瓷。", "清乾隆祭蓝天球瓶，器形圆浑，蓝釉深沉。"),
    (1054, "赏瓶", "清乾隆缠枝花卉瓷。", "清乾隆青花赏瓶，通体缠枝花卉，端庄雅致。"),
    (20482, "玉璧", "史前草鞋山玉礼器。", "新石器玉璧，出土于苏州草鞋山遗址。"),
    (20480, "玉琮", "史前文化玉器。", "良渚六节玉琮，体现成熟的史前玉礼制度。"),
    (2549, "石刀", "北阴阳营文化石器。", "七孔石刀，孔可穿绳缚柄，展现史前工艺。"),
    (2550, "猪头", "大墩子遗址史前雕刻。", "史前石雕猪头，造型概括，富有原始艺术趣味。"),
    (14816, "漆奁", "战国人物纹漆器。", "战国彩绘黑漆奁，器表人物纹饰色彩鲜明。"),
    (14815, "漆案", "战国宴饮陈设漆器。", "战国朱绘漆长方案，是古代宴饮陈设用具。"),
    (263, "缂丝鹌鹑", "南宋花鸟缂丝。", "南宋缂丝月季鹌鹑图，织工精细，具院画风韵。"),
    (257, "刺绣观音", "元代发绣与丝绣。", "元代观音绣像，发绣与丝绣结合，衣纹清雅。"),
    (18432, "风雪", "南宋夏珪山水画。", "南宋夏珪灞桥风雪图，笔墨简劲，寒意逼人。"),
    (2492, "四季牧牛", "南宋阎次平画卷。", "南宋四季牧牛图，牛形生动，景物浑融。"),
    (2434, "花鸟图", "宋徽宗花鸟画。", "宋徽宗鸜鹆图，三鸟相斗，羽毛刻画细腻。"),
    (20405, "富春大岭", "元黄公望山水。", "元黄公望富春大岭图，山势冷峻，气象苍茫。"),
    (18433, "水阁清幽", "元黄公望水墨。", "元黄公望水阁清幽图，溪流云气，笔意疏朗。"),
    (20436, "捣衣图", "明仇英人物画。", "明仇英捣衣图，庭院清雅，寄托思念。"),
    (20435, "仕女图", "明文从简临唐寅画。", "明文从简临唐寅仕女画，姿态婉约，笔墨秀润。"),
    (20434, "草书诗轴", "明祝允明书法。", "明祝允明草书诗轴，行笔跌宕，气势连贯。"),
    (20433, "水亭诗思", "明文徵明设色山水。", "明文徵明水亭诗思图，水亭清幽，富有诗意。"),
    (20432, "古木苍烟", "明文徵明水墨山水。", "明文徵明古木苍烟图，笔墨沉静，气韵雅正。"),
    (9730, "商代铜鼎", "商代青铜礼器。", "商代青铜鼎，器形厚重，是礼制的重要见证。"),
    (9704, "双羊铜尊", "商代羊首青铜礼器。", "商代双羊铜尊，羊首装饰雄奇，铸造精工。"),
    (9275, "西周甬钟", "先秦礼乐青铜钟。", "西周青铜甬钟，用于礼乐演奏，体现先秦乐制。"),
    (9148, "鱼纹铜盘", "西周礼仪青铜盘。", "西周青铜鱼纹双耳盘，饰鱼纹，为礼仪用器。"),
    (5, "雷波人口册", "清代土司人口赋役账册。", "清代雷波夷人人口册，记录土司辖区人口赋役。"),
    (4, "婚书", "民国回汉文结婚证书。", "民国回族结婚证书，木板印制，兼用回汉文字。"),
]

CAPTION_DESCRIPTIONS = [
    "西汉黄金铸器，重九千克，斑纹细密。",
    "楚国黄金货币，钤有郢爰印记。",
    "东汉错银灯具，烟尘经管入水。",
    "南朝名士画像砖，人物清雅。",
    "明代釉里红瓷，腹部绘花卉。",
    "明代官窑寿山福海纹，仿青铜鼎。",
    "清乾隆蓝釉瓷，祭天用器。",
    "清乾隆缠枝花卉瓷，瓶身修长。",
    "史前草鞋山玉礼器，圆孔规整。",
    "史前文化玉器，内圆外方。",
    "北阴阳营文化石器，七孔磨制。",
    "大墩子遗址史前雕刻，古朴概括。",
    "战国人物纹漆器，红黑分明。",
    "战国宴饮陈设漆器，长案。",
    "南宋花鸟缂丝，丝理细密。",
    "元代发绣与丝绣，衣纹清雅。",
    "南宋夏珪山水画，笔墨简劲。",
    "南宋阎次平画卷，牛形生动。",
    "宋徽宗花鸟画，三鸟相斗。",
    "元黄公望山水，山势冷峻。",
    "元黄公望水墨，山势清幽。",
    "明仇英人物画，庭院秋思。",
    "明文从简临唐寅画，衣纹清雅。",
    "明祝允明书法，行笔简劲。",
    "明文徵明设色山水，水亭清幽。",
    "明文徵明水墨山水，笔墨沉静。",
    "商代青铜礼器，器形厚重。",
    "商代羊首青铜礼器，铸造精工。",
    "先秦礼乐青铜钟，礼乐演奏。",
    "西周礼仪青铜盘，双耳鱼纹。",
    "清代土司人口赋役账册，记录辖区。",
    "民国回汉文结婚证书，木板印制。",
]


def request_bytes(url: str, data: bytes | None = None) -> bytes:
    headers = {"User-Agent": "Mozilla/5.0 FPGA-Contest-Media-Builder"}
    if data is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        headers["X-Requested-With"] = "XMLHttpRequest"
    last_error = None
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, data=data, headers=headers)
            with urllib.request.urlopen(request, timeout=45) as response:
                return response.read()
        except Exception as exc:
            last_error = exc
            time.sleep(1 + attempt)
    raise RuntimeError(f"download failed: {url}: {last_error}")


def official_record(item_id: int) -> dict:
    payload = urllib.parse.urlencode({"id": item_id}).encode("ascii")
    body = json.loads(request_bytes(API, payload).decode("utf-8"))
    if body.get("code") != 0 or not body.get("data", {}).get("list"):
        raise RuntimeError(f"official record missing for id={item_id}")
    return body["data"]["list"][0]


def image_url(path: str) -> str:
    normalized = path.replace("\\", "/")
    return IMAGE_ROOT + urllib.parse.quote(normalized, safe="/:%-._~")


def fit_image(raw: bytes, destination: Path) -> None:
    image = Image.open(io.BytesIO(raw)).convert("RGBA")
    alpha = image.getchannel("A")
    if alpha.getextrema()[0] < 255:
        opaque_box = alpha.getbbox()
        if opaque_box:
            image = image.crop(opaque_box)
    pixels = np.asarray(image)
    border = np.concatenate(
        [
            pixels[:4].reshape(-1, 4),
            pixels[-4:].reshape(-1, 4),
            pixels[:, :4].reshape(-1, 4),
            pixels[:, -4:].reshape(-1, 4),
        ]
    )
    fill_color = tuple(int(value) for value in np.median(border[:, :3], axis=0))
    background = Image.new("RGBA", (640, 480), (*fill_color, 255))
    foreground = ImageOps.contain(image, (600, 440), Image.Resampling.LANCZOS)
    background.alpha_composite(
        foreground,
        ((640 - foreground.width) // 2, (480 - foreground.height) // 2),
    )
    background.convert("RGB").save(destination, "BMP")


def main() -> None:
    parser = argparse.ArgumentParser(description="构建南京博物院 32 项初版素材")
    parser.add_argument("-o", "--out", type=Path, required=True)
    parser.add_argument("--captions-out", type=Path)
    args = parser.parse_args()
    if len(ITEMS) != 32 or len({item[0] for item in ITEMS}) != 32:
        raise RuntimeError("curated exhibit list must contain 32 unique IDs")

    out = args.out.resolve()
    images_dir = out / "source_images"
    audio_dir = out / "source_audio"
    images_dir.mkdir(parents=True, exist_ok=True)
    audio_dir.mkdir(parents=True, exist_ok=True)
    captions = {"status": "南京博物院官方馆藏初版，文物权利归原机构", "items": []}
    sources = []

    for slot, (item_id, title, description, narration) in enumerate(ITEMS, 1):
        if slot in (15, 16):
            category = "textile"
        elif 17 <= slot <= 26:
            category = "painting"
        elif slot in (31, 32):
            category = "document"
        else:
            category = "object"
        display_description = description.rstrip("。") + CAPTION_TAILS[category]
        # Keep each exhibit description specific to the object. A shared
        # category tail made the whole sequence read as one repeated sentence.
        display_description = CAPTION_DESCRIPTIONS[slot - 1]
        if len(title) > 16 or len(display_description) > 64:
            raise RuntimeError(f"slot {slot} exceeds OSD text limits")
        record = official_record(item_id)
        images = record.get("imgSrc") or []
        if not images:
            raise RuntimeError(f"slot {slot} has no official image")
        raw = request_bytes(image_url(images[0]))
        image_name = f"{slot:02d}.bmp"
        fit_image(raw, images_dir / image_name)
        captions["items"].append(
            {"id": slot - 1, "title": title, "description": display_description}
        )
        sources.append(
            {
                "slot": slot,
                "collection_id": item_id,
                "official_title": record.get("title"),
                "display_title": title,
                "category": record.get("categoryName"),
                "size": record.get("size"),
                "official_description": record.get("describe"),
                "official_page": PAGE.format(id=item_id),
                "image_url": image_url(images[0]),
                "image_sha256": hashlib.sha256(raw).hexdigest(),
                "rights": "图片和馆藏信息来自南京博物院公开网页；权利归原机构，仅用于课程/竞赛展示。",
            }
        )
        print(f"[{slot:02d}/32] {title} <- {record.get('title')}")

    (out / "captions.json").write_text(
        json.dumps(captions, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if args.captions_out:
        args.captions_out.parent.mkdir(parents=True, exist_ok=True)
        args.captions_out.write_text(
            json.dumps(captions, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    (out / "sources.json").write_text(
        json.dumps(sources, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"官方媒体源已生成：{out}")


if __name__ == "__main__":
    main()
