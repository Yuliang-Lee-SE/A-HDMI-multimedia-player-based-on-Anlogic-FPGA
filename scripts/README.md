# scripts 脚本说明

| 脚本 | 用途 |
| --- | --- |
| `convert_images_to_bmp.py` | 把常见图片批量转换为 640×480、24 位非压缩 BMP |
| `gen_test_patterns.py` | 生成彩条、渐变、棋盘格、网格和纯色测试图 |
| `check_tf_card_images.py` | 只读检查 TF 卡中的 BMP 分辨率、位深、压缩和翻转方式 |
| `sync_to_sd.py` | 安全同步图片和 WAV 到 TF 卡，并清理旧媒体残留 |
| `prepare_tf_media.py` | 生成或整理 32 项展品对应的 TF 卡媒体 |
| `build_njmuseum_v1.py` | 构建南京博物院展品资源初版 |
| `gen_tf_media_smoke.py` | 生成短小的 TF 卡媒体冒烟测试素材 |
| `run_regression.ps1` | 编译并运行当前版本的 S1-S8 回归用例 |
| `sync_rtl.bat` | 把 TD 工程 RTL 单向同步到仓库根目录 `rtl/` |

## 验证

当前回归覆盖帧缓存、TF 卡 WAV/PCM、I2S/ACR、音频频谱、画面调节、转场控制和复位防护：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1 -Only s1,s2
```

脚本不会在缺少 ModelSim/Questa 时静默通过；没有仿真器时以上板记录作为验收证据。

## RTL 镜像

权威源码位于 `lab_ex5_i2s/src/user_source/hdl_source/`。修改后运行：

```powershell
scripts\sync_rtl.bat
```
