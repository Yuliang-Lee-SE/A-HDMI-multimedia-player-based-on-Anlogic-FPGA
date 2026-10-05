# scripts/ — 工程脚本

| 脚本 | 用途 |
| --- | --- |
| `convert_images_to_bmp.py` | 把常见图片批量转换为 640×480、24 位非压缩 BMP |
| `sync_to_sd.py` | 安全同步图片到 TF 卡，清理旧扇区数据，避免 FPGA 读到残留图片 |
| `sync_rtl.bat` | 从 TD 工程源码单向同步 RTL 到仓库根目录 `rtl/` |

## 使用说明

- Python 脚本需要 Pillow：`pip install pillow`
- 两个 Python 脚本的详细说明见 `lab_ex5_i2s/doc/convert/README.md`
- 修改完 `lab_ex5_i2s/src/user_source/hdl_source/` 里的 RTL 后，运行 `sync_rtl.bat` 刷新 `rtl/` 镜像
