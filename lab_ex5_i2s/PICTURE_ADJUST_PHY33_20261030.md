# phy33 画面参数调整与音量共存

本功能基于用户已上板确认可用的 `phy33`/`feature/video-transition-v2`
源码，保留原有 FAT32 播放、转场、OSD、音量和缩放功能。

## 按键

| 实体按键 | 正常模式 | 参数菜单内 |
| --- | --- | --- |
| KEY4 / C1 | 短按 AUTO/PLAY；长按进入菜单 | 短按切参数；长按退出 |
| KEY3 / B1 | 短按缩放；长按调音量 | 增加当前参数 |
| KEY2 / B2 | 短按下一张；长按转场设置 | 减小当前参数 |

## 参数

- 亮度：`-64..+64`，步进 8，默认 0。
- 对比度：`50%..150%`，步进 10%，默认 100%。
- 清晰度：`0..8`，默认 0。
- 默认值逐像素直通。右侧菜单同时显示三项参数，当前行用黄色 `>` 标记。

## 实现

- `picture_adjust_pipeline.v`：RGB 亮度、对比度和三抽头锐化，时序与像素
  同延迟。
- `picture_adjust_controller.v`：实体按键映射、长短按互斥及参数状态。
- `picture_adjust_osd.v`：右侧参数面板。
- `top_tf_hdmi_audio.v`：在 phy33 原有图层的底图位置插入处理，并在音量
  OSD 之后叠加参数菜单。
- `HDMI1.4b_Transmitter_v1.0.al`：注册三个新源文件。

## 验证

- ModelSim 定向测试：`cmd /c verify_picture_adjust_phy33.bat`。
- TD 6.2 最终 Routed：setup `+0.120 ns`，hold `+0.004 ns`，TNS 和
  违例端点均为 0。
- 候选 bit SHA256：
  `B53EFD4C0E56328D25CCB5EAF8E020CCB9594F171E8E52B8F4AF2008859F136E`。
- 用户已确认该候选 SRAM 版本上板正常。
