# assets_src/ — 原始素材

存放未经转换的原始素材，生成物统一放到 `assets_out/`（已被 .gitignore 排除）。

| 子目录 | 用途 |
| --- | --- |
| `images/` | 展品原始图片（PNG/JPG/WebP 等） |
| `audio/` | 解说音频源文件（WAV/MP3 等） |
| `fonts/` | 字幕字库源文件或字库生成脚本的输入 |

命名建议：`<展品编号>_<名称>_<用途>.<扩展名>`，例如 `E01_青花瓷_主图.png`、`E01_青花瓷_解说.mp3`。

图片最终需要转换成 640×480、24 位、非压缩 BMP，使用 `scripts/convert_images_to_bmp.py` 批量处理。
