# 两缓冲水平滑动转场

基线为 `origin/main` 的 `tf_file_player` 乒乓帧缓冲。物理帧缓存仍然只有两块：

```text
BUF0 = 0
BUF1 = 307200
```

不存在 BUF2/BUF3/BUF4 scratch。缩放结果只写当前非显示 bank，完整帧结束后才在视频 VS 请求边界提交 bank/item。

## 所有权与切换规则

1. `tf_file_player` 只写非显示 bank。
2. 首图和同 item 缩放重载直接切换。
3. 不同 item 的切换保留 A=旧 bank、B=新 bank。
4. `display_commit_ack` 由 `transition_frame_owner` 在滑动结束并安全释放两块 bank 后返回。
5. 滑动期间，同步到 SD 时钟域的 `transition_busy` 禁止下一次帧写入。
6. 所有 bank 切换都在视频帧请求边界完成。

## 最终数据通路

```text
tf_file_player
  -> 完整写入非显示 bank
  -> VS 提交 bank/item
  -> transition_frame_owner
  -> frame_compose_read
       normal: 顺序读取 A
       slide : 每行读取 A 的可见尾部，再读取 B 的可见头部
  -> 单个 512×32 异步读 FIFO
  -> video_delay
  -> OSD / waveform / HDMI
```

滑动帧在 SDRAM 地址生成侧直接合成为正常扫描顺序的 640×480 流。因此视频侧始终只消费一个连续帧 FIFO，不再存在单/双读 FSM 切换、双行缓存、A/B 混合器运行中交接或跨域 bank 号竞争。

地址和滑动宽度在请求边界寄存。每个有效像素只推进已寄存的 A/B 地址，避免 125 MHz 路径中出现乘法器和多级加法器。

## 验证

- `tb_compose_read_sequence.v`：普通帧、128/256 滑动帧、普通帧连续执行，并模拟 10 拍 SDRAM 读延迟；逐字检查 A/B 地址映射。
- `tb_transition_owner.v`：首图硬切、同 item 硬切、不同 item 滑动、完成前不释放写回 ACK。
- `tb_commit_release_v2.v`：提交桥与 owner 释放握手。
- `tb_top_commit_readback.v`：真实视频请求、异步 FIFO 和内存读路径持续产生帧请求。
- `tb_transition_v2_e2e.v`：7 个完整 640×480 帧，逐像素检查滑动画面的 A/B 合成；结果为 `TRANSITION_V2_E2E_PASS`。

## 板级结果

`phy_19` 已完成 Program Flash 写入、`verify_spi` 和最终 100% 编程验证。上板确认：

- 首图、字幕和缩放正常；
- 按键后水平滑动转场正常；
- 转场完成，数码管不再进入 `F`；
- 普通显示和转场后的显示均已通过板级测试。

实现结果：

- SWNS `+0.146 ns`，STNS `0`；
- HWNS `+0.011 ns`，HTNS `0`；
- LUT `58.66%`，REG `42.57%`；
- 9K BRAM `54/64`，32K BRAM `12/16`。

已测试 bit：

`src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_19/HDMI1.4b_Transmitter_v1.0.bit`

SHA256：`352D5D9B7E6AD43D387830D86BBC201A19F2A57C408973CE2BC211F7C1E70C4F`
