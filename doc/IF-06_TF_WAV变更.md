# IF-06 增补：TF 卡 WAV 音频（v0.3）

本文替代《接口约束文档》中 IF-06 v0.2 的“片内 ROM 音频”描述。原 I2S 与
HDMI 音频接口保持不变。

## 跨模块信号

| 信号 | 方向 | 位宽 | 源时钟 | 说明 |
|---|---|---:|---|---|
| `audio_track_idx[4:0]` | `tf_file_player` 到 `audio_pcm_player` | 5 | `sd_card_clk` | 当前 0 到 31 项，作为诊断信息 |
| `audio_track_toggle` | `tf_file_player` 到 `audio_pcm_player` | 1 | `sd_card_clk` | 新 WAV 加载完成后翻转 |
| `audio_track_len[15:0]` | `tf_file_player` 到 `audio_pcm_player` | 16 | `sd_card_clk` | 当前 WAV 有效样点数 |
| `audio_track_ready` | `tf_file_player` 到 `audio_pcm_player` | 1 | `sd_card_clk` | WAV 数据完整且可播放 |
| `audio_enabled` | `tf_file_player` 到播放器 | 1 | `sd_card_clk` | 当前音轨启用/静音 |
| `audio_ram_we` | `wav_pcm_loader` 到双口 RAM 写口 | 1 | `sd_card_clk` | 一次写入一个 16-bit 样点 |
| `audio_ram_addr[14:0]` | `wav_pcm_loader` 到双口 RAM 写口 | 15 | `sd_card_clk` | 0 到 24575 |
| `audio_ram_data[15:0]` | `wav_pcm_loader` 到双口 RAM 写口 | 16 | `sd_card_clk` | signed PCM |
| `audio_pcm_addr[14:0]` | 播放器到双口 RAM 读口 | 15 | `audio_mclk` | 当前读取样点 |
| `audio_pcm_data[15:0]` | 双口 RAM 读口到播放器 | 16 | `audio_mclk` | signed PCM |

## 时序约定

1. `audio_track_len`、`audio_track_ready` 和 `audio_enabled` 使用两级同步。
2. `audio_track_toggle` 使用三级同步后取边沿。
3. RAM 写口必须在 toggle 翻转前完成；播放器收到 toggle 后才更新长度并重播。
4. `I2S_BCLK`、`I2S_LRCK`、`I2S_DOUT`、`I2S_receiver`、`audio_arc_calculate`
   和 `ACR_N=6144` 均不改变。
5. `audio_mclk` 与其他时钟保持异步约束。

## 文件索引

- BMP：`0101.BMP` 到 `0132.BMP`，FAT 索引 ID 为 101 到 132。
- WAV：`0201.WAV` 到 `0232.WAV`，FAT 索引 ID 为 201 到 232。
- 最大索引条目：64。
- 图片队列只使用 BMP 条目，WAV 通过固定数值 ID 单独打开。

## 状态

- 实现：张淦森
- 仿真代码：`lab_ex5_i2s/tb/tb_wav_pcm_loader.sv`
- 已通过 TD 种子 2 布线：SWNS=+0.101 ns，HWNS=+0.004 ns
- A 确认：待上板验证后签字
