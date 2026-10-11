# 三档缩放＋中文字幕

本分支的上板文件和操作说明见 [当前交付](delivery/README.md)。源码工程在 `src/td_project/`，改文案和重建见 [说明](OSD_STATIC_CN_20261011.md)。

---

以下为原有子系统仿真记录；本次整机验证请使用上面的入口。

# lab_ex5_i2s 纯 RTL 子系统仿真（ModelSim）

> **工作目录 / 建库位置：`D:\FPGA\lab_ex5_i2s`**
> ModelSim 的 `work` 库就建在这个目录下（`D:\FPGA\lab_ex5_i2s\work`）。
> 之所以不放在工程目录（`...\全国大学生嵌入式芯片与系统设计竞赛'2026选题指南_康芯\lab_ex5_i2s\sim`），
> 是因为 **ModelSim 2020.1 在含中文的路径下建库会直接失败**：
> `init_dbinfo() DATABASE ERROR: sqlite3_open ... unable to open database file`。
> 实测结论：纯英文路径 ✅、只含单引号（'）✅、含中文 ❌。
> 所以本目录是"英文路径下的仿真工作区"，RTL 源文件是工程源码的副本（见 `rtl/`）。

### 保持 RTL 副本与工程同步

`compile.do` 找源码的顺序是：

1. `..\src\user_source\hdl_source`（工程 `sim` 目录下运行时用）
2. `src\user_source\hdl_source`（**本目录 `D:\FPGA\lab_ex5_i2s` 用的就是这份**）
3. `rtl\`（本目录自带的 17 个源码副本，单独拷走这个文件夹时用）

改代码后让仿真用上最新源码，两种做法都行：

* **直接改 `D:\FPGA\lab_ex5_i2s\src\user_source\hdl_source\` 里的文件**，改完直接 `run_all.bat`（推荐，最省事）；
* 或者改原工程（中文路径那份）的源码，然后双击 `sync_rtl.bat` —— 它会把 17 个文件同时刷新到
  `rtl\` 和 `src\user_source\hdl_source\`（会覆盖同名文件，注意别把自己在这两处的改动冲掉）。

这 5 个 testbench 全部只依赖**工程里可见的 RTL 源码**：
不需要安路器件仿真库、不需要 TD、不需要解密加密核，模型自己写。
最快几十毫秒就能出结果，适合用来验证「读懂代码」和「改代码」这两件事。

```
D:\FPGA\lab_ex5_i2s\           <- 工作目录，work/ 库建在这里
├─ compile.do          建库 + 编译全部源文件与 TB（从此目录执行）
├─ run_all.bat         一键编译并依次跑 5 个 TB（run_all.bat s1 只跑 S1）
├─ sync_rtl.bat        从工程源码重新拷一份 RTL 到 rtl\
├─ src\user_source\hdl_source\   实际参与编译的源码（本目录自带的一份工程副本）
├─ rtl\                17 个 RTL 源文件副本（兜底用；sim 目录单独拷到别处时用它）
├─ fake_sd_card.v      SPI 模式的简易 SD 卡从机模型（CMD0/8/55/41/16/17）
├─ sdram_model.v       SDRAM 行为模型（替代加密的 sdr_*.enc.v）
├─ tb_bmp_read.v       S1  BMP 扫描/解析
├─ tb_sd_card.v        S2  SD 卡 SPI 协议栈
├─ tb_frame_fifo.v     S3  帧缓存读写通路（双 FIFO + 突发 + 垂直翻转）
├─ tb_audio_i2s.v      S4  I2S 发送 → 解串 → ACR
├─ tb_video_axis.v     S5  视频时序 + 延迟对齐 + AXIS 打包
└─ work\               编译产物（第一次运行后自动生成）
```

---

## 一、两种跑法

### A. 命令行 / 批处理（推荐先用这个确认环境是通的）

双击 `run_all.bat`，或在命令行：

```bat
cd /d D:\FPGA\lab_ex5_i2s
run_all.bat            :: 全部跑一遍
run_all.bat s4         :: 只跑 S4
```

脚本会先 `vsim -c -do compile.do` 编译，再逐个 `vsim -c work.tb_xxx -do "run -all; quit -f"`，
每个 TB 的结果写到同目录 `tb_xxx.log`。ModelSim 不在 PATH 里的话，改 `run_all.bat` 第 8 行的 `set MS=...`。

单独跑一个（不用批处理）：

```bat
cd /d D:\FPGA\lab_ex5_i2s
vsim -c -do compile.do
vsim -c work.tb_audio_i2s -do "run -all; quit -f"
```

### B. ModelSim GUI（看波形）

1. `File → Change Directory` 选到 `D:\FPGA\lab_ex5_i2s`（很重要，`compile.do` 用的是相对路径）。
2. 在下方 Transcript 里输入 `do compile.do`，一次性建库并编译（含 `+incdir`，不用手工配）。
3. `Simulate → Start Simulation`，`work` 库下选 `tb_audio_i2s` 之类的 TB，点 OK。
4. 在 `Objects` 窗口里选中要看的信号 → 右键 `Add Wave`，然后 `run -all`。
   想看 DUT 内部信号（推荐加 `-voptargs="+acc"`，否则有些内部线会被优化掉）：
   命令行等价写法 `vsim -c -voptargs="+acc" work.tb_audio_i2s -do "run -all"`。
5. 想改参数重跑：直接改 TB 顶部的 `parameter`/`localparam` 再 `do compile.do`。

---

## 二、每个 TB 验证什么、波形该看谁

**S1 `tb_bmp_read`** — BMP 扫描与解析
假卡把「扇区 3 放一张合法 640×480/24bit 小 BMP，其余扇区是垃圾」，检查：命中扇区号/张数、
`write_req` 握手、3 字节拼像素的顺序（`[7:0]→[15:8]→[23:16]`）、读完回 IDLE。
看：`scan_state`、`rd_cnt`、`u_dut.header_0/1`、`width/height/bit_count/compression`、`bmp_data_wr_en`。
改：把扇区 3 的 `bit_count` 改成 8、或把 `compression` 改成 1，看扫描是否跳过（任务清单里的练习）。

**S2 `tb_sd_card`** — SD 卡 SPI 协议栈（`sd_card_top` → `sd_card_sec_read_write` → `sd_card_cmd` → `spi_master`）
检查：CMD0/CMD8/CMD55/CMD41/CMD16 初始化流程走通（`sd_init_done` 拉高，实测 4901 个时钟）、
CMD17 读回的 512 字节与卡内数据一致、`sd_sec_read_end` 脉冲。
看：`SD_nCS/SD_DCLK/SD_MOSI/SD_MISO`（SPI 波形）、`u_dut.sd_card_sec_read_write_m0.state`、`u_card.st`。
说明：TB 把 `SPI_LOW_SPEED_DIV` 从 248 改成 4 只为加速，真机参数不用改。

**S3 `tb_frame_fifo`** — 帧缓存读写通路（32×8 = 256 字/帧，正好一个 256 字突发）
检查：写握手 → 突发写 256 字 → `write_finish` → 读握手 → 整帧读回 256 字 → 与预期逐字比对，
并验证**垂直翻转地址映射**（读出第 0 个字应等于写入的第 `(FH-1)*FW = 224` 个像素）。
看：`App_wr_en/App_wr_addr/App_wr_din`、`App_rd_en/App_rd_addr`、`wfifo_rdusedw`、`rfifo_wrusedw`。

**S4 `tb_audio_i2s`** — I2S 发送 → 解串 → ACR
实测通过：BCLK 周期 163000ps（12.288MHz 二分频）、每声道 64 个 BCLK、LRCK 周期 20.833us →
fs = 48.001kHz、2ms 内 96 个样本、ACR 每 48 个样本一次、`acr_cts` = 25000~25007、`acr_n` = 6144。
看：`i2s_bclk/i2s_lrck/i2s_dout`、`u_rx.S_left_shift_data/S_right_shift_data`、`acr_valid/acr_cts/acr_n`。
实验：把 TB 里的 `mclk` 周期从 `#40.69` 改成 `#40.69*12.295/12.288`（即用工程真实的 12.295MHz），
看 `acr_cts` 和测量出来的 fs 怎么变 —— 这就是学习页里「待确认」那条的量化验证。

**S5 `tb_video_axis`** — 视频时序 + 延迟对齐 + AXIS
实测通过：一帧 480 个 de 行脉冲、307200 个有效像素、每行 640 像素、SOF 1 次、SOF 那一拍像素 = 0、
帧末像素 = 307199、valid 期间数据连续 +1。
看：`hs/vs/de`、`de_d[20:18]`、`read_en`、`vout_data`、`axis_user/valid/last/data`。

---

## 三、踩过的坑（照抄这些结论能省几小时）

1. **这 5 个 TB 不需要器件库**。只要 `src/user_source/hdl_source` 下的 RTL + 本目录的两个模型。
   需要器件库的是整机仿真（PLL/ODDR/SDRAM 原语），那是另一套配置。

2. **`frame_read_write.v` 里 used word 的位宽不匹配（重要）**：
   FIFO IP 的 `rdusedw/wrusedw` 只有 **9bit**，而 `frame_fifo_write/read` 的端口是 `input[9:0]`（10bit），
   中间那根 wire 也是 9bit。综合时高位补 0 掩盖了它，**RTL 仿真时高位悬空(Z)**，
   于是 `into_burst` / `wrusedw` 比较变成 X，写/读突发永远进不去（现象：写握手正常、`write_finish` 不来）。
   两条路：
   * 想直接仿真 `frame_read_write`：把两处 `wire[BURST_BITS-1:0] wrusedw/rdusedw` 改成 `wire[9:0]`，
     再加两根 9bit 中间线接 FIFO 输出、`assign wrusedw = {1'b0, wrusedw_fifo};` 补零扩展；
   * 或者像 `tb_frame_fifo.v` 这样**直接例化两个子模块**（本 TB 采用），不改工程源码。

3. **两个 FIFO 的 `SHOW_AHEAD_EN` 默认值不一样**：wfifo 是 1（`dout` 就是当前队首），
   rfifo 是 0（`dout` 比 `re` 晚一拍）。所以读数据要在 `read_en` 的下一个时钟沿采样。
   真机里 `video_delay` 把同步信号延迟 21 拍、`read_en` 取 `de_d[18]`，正是为了配这个时序。

4. **wfifo 的 almost-full 阈值是 509**（深度 512），一帧字数不要超过它，否则尾部会丢字；
   另外 `frame_fifo_write` 在 `S_ACK` 期间会 `fifo_aclr` 清 FIFO，
   所以送像素要等握手完成、aclr 落下之后再开始（S3 TB 里 `repeat(20)` 那几行就是这个原因）。

5. **`video_rgb_to_axis_640x480` 的 `O_video_last` 恒不拉高**：行首把 `S_x_cnt` 清 0 之后，
   第 640 个像素处计数是 **638**，而代码拿它和 639 比较，差一拍。真机上 HDMI 核不受影响，
   仿真里一眼可见。想修就是把判断改成 638（或让计数从 1 开始）。

6. `fake_sd_card.v` 只实现了工程用到的 6 条命令（CMD0/8/55/41/16/17），
   CMD41 直接回 0x00（模拟“已初始化好的卡”，让状态机一次通过）。要测更复杂的流程就按 CMD 索引扩 `case`。

7. FIFO IP 内部例化 RAM 时少接了 `doa/dib` 两个端口，`vlog/vsim` 会报 6 条
   `[TFMPC] Missing connection` 警告 —— 厂商代码自带的，不影响功能。

---

## 四、怎么扩展

* 加新 TB：把 `tb_xxx.v` 放进本目录，在 `compile.do` 的文件列表里加一行，`run_all.bat` 里加一条 `call :run tb_xxx`。
* 想验证「改代码」：直接改工程源码，重跑 `compile.do` 即可（TB 里已经写了期望值，改错会立刻报 ✗）。
* 想接到整机：`frame_read_write` 的位宽问题要先按第 2 条修掉，否则整机仿真的写通路同样会卡住。
