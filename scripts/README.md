# scripts/ — 工程脚本

| 脚本 | 用途 |
| --- | --- |
| `convert_images_to_bmp.py` | 把常见图片批量转换为 640×480、24 位非压缩 BMP |
| `gen_test_patterns.py` | 生成彩条/渐变/棋盘格/网格/纯色测试图（Bring-up 与对色用） |
| `check_tf_card_images.py` | 只读检查 TF 卡里的 BMP 是否符合工程要求（分辨率/位深/压缩/翻转） |
| `sync_to_sd.py` | 安全同步图片到 TF 卡，清理旧扇区数据，避免 FPGA 读到残留图片 |
| `wav_to_speech_rom.py` | 把讲解 WAV 转成片内音频 ROM 的 MIF（4 段 × 12288 样点 @ 8kHz/8bit） |
| `run_regression.ps1` | 一键编译并运行 S1~S7 全部 testbench（需要 ModelSim/Questa） |
| `sync_rtl.bat` | 从 TD 工程源码单向同步 RTL 到仓库根目录 `rtl/` |

## 使用说明

- Python 脚本依赖：`pip install pillow numpy`
- 图片转换与 TF 卡同步的详细说明见 `lab_ex5_i2s/doc/convert/README.md`
- 修改完 `lab_ex5_i2s/src/user_source/hdl_source/` 里的 RTL 后，运行 `sync_rtl.bat` 刷新 `rtl/` 镜像

## 常用命令

```powershell
# 生成测试图（默认输出 assets_out\test_patterns）
python scripts\gen_test_patterns.py

# 上板前检查卡里的图片能不能被工程读（只读，不改卡）
python scripts\check_tf_card_images.py E:
python scripts\check_tf_card_images.py E:\ --all-dirs

# 生成/更新片内音频素材；没有录音时先用 --demo 合成 4 段测试音
python scripts\wav_to_speech_rom.py --demo `
    -o lab_ex5_i2s\src\user_source\hdl_source\team\audio_speech_rom.mif
python scripts\wav_to_speech_rom.py seg1.wav seg2.wav seg3.wav seg4.wav `
    -o lab_ex5_i2s\src\user_source\hdl_source\team\audio_speech_rom.mif

# 回归（找不到 vsim.exe 会明确报错，不会假装通过）
powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1 -Only s6,s7
powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1 `
    -ModelSimDir 'D:\Modelsim\modelsim_ase\win32aloem'
```
