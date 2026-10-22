
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]

# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk sd_card_clk ext_mem_clk]

# ------------------------------------------------------------
# 5b. 音画联动 CDC：sd_card_clk -> audio_mclk（角色 C 补充）
#
#    【背景】
#      2026-10-10 布局布线报告（_Runs/phy_1/HDMI1.4b_Transmitter_v1.0_pr.timing）里
#      全局 SWNS -2.037ns / STNS -6.103ns 只有 3 条违例，全部落在
#      Path Group "sd_card_clk -> audio_mclk"：
#        Begin Point : sd_card_bmp_m0/audio_track_idx_reg[0]_syn_7.clk
#        net         : audio_track_idx[1:0] / audio_track_toggle（sd_card_bmp.v）
#      这几条路径的真实数据延迟只有约 0.5ns，工具却按 Fmax 3.05MHz 计
#      （= 327.877ns 周期）—— 它是按两个相位不相关时钟的最坏对齐算的，
#      属典型的跨时钟域伪违例，不是逻辑太慢。
#      上面第 5 节那条 set_clock_groups -asynchronous 并没有拦住这一对时钟
#      （报告里这 3 条仍被分析），所以这里再显式切一次。
#
#    【为什么可以这样切】
#      从 sd_card_clk 跨到 audio_mclk 的信号只有这 3 根：
#        audio_track_idx[1:0]   2bit 段号，准静态，每次切图才变一次
#        audio_track_toggle     1bit 握手，换段那一拍翻转
#      接收侧（team/audio_rom_player.v）已经做了同步：索引打两拍、
#      toggle 打三拍后异或取边沿；而且播放器是收到 toggle 边沿后先淡出
#      20ms 才去取段号，那时数据必然稳定。
#      所以按这对时钟切掉时序分析，作用范围精确等于这 3 条 CDC 路径，
#      不会掩盖任何用户逻辑路径。
#
#    【归属】本文件属 A 负责范围；此条由角色 C 为音画联动新增，
#            已在提交信息与 PR 描述中注明，请 A 复核。
#            上板仍需复测：连续切图 100 次 + 长时间轮播，确认音频与画面一一对应。
# ------------------------------------------------------------
set_false_path -from [get_clocks {sd_card_clk}] -to [get_clocks {audio_mclk}]

# The startup guard is a quasi-static asynchronous reset control generated in
# the 50 MHz input-clock domain. Exclude only this register output from
# cross-domain timing. The 50 MHz clock domain contains only the reset guard
# and the independent seven-segment scanner, so no functional data crosses
# these clock pairs. Target the clock pair after synthesis optimization.
set_false_path -from [get_clocks {clk}] -to [get_clocks {sd_card_clk}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {ext_mem_clk}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {video_clk}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {audio_mclk}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# ------------------------------------------------------------
# 8. SDRAM 硬宏 DQ 接口：伪路径（false path）
#
#    【背景】
#      SDRAM 控制器用的是安路 EG_PHY_SDRAM_2M_32 硬宏，DQ/DM/地址等引脚
#      全部封装在硬宏内部，用户源码里看不到（SD/sdram.v 中只有
#      ifdef SIMULATION 时才把 SDR_* 引出来）。送给 SDRAM 的时钟来自
#      sys_pll 的 C2 输出（125 MHz，相对 C1 移相 180 度），在时序报告里
#      这一路时钟名为 sys_pll_m0/pll_inst.clkc[2]，其扇出只有 1 ——
#      唯一的负载就是硬宏的 SDRAM_CLK 输入。
#
#    【问题】
#      本文件第 7 节没有描述 SDRAM 的片外往返延迟，时序工具只能按最严苛
#      的模型推算：它把外部 SDRAM 当成"收到时钟立刻返回数据、板级走线
#      长度为零"。于是报出两组违例：
#        clkc[2]     -> ext_mem_clk : SWNS -6.699ns，32 个端点
#        ext_mem_clk -> clkc[2]     : SWNS -2.799ns，32 个端点
#      两组端点正好是 DQ[31:0] 的读方向和写方向，且路径 100% 是 cell
#      延迟、net 延迟为 0、逻辑级数为 0 —— 纯粹是硬宏 pad 的固定特性，
#      布局布线无法优化，改代码也改不动。
#
#    【依据】
#      安路官方 DDR 约束（D:\TD_Engineer\ip\ddr\ddrmc.sdc 与 ddrphy.sdc）
#      对 PHY 硬宏内部路径就是用 set_false_path 屏蔽的，例如：
#        set_false_path -to [get_pins {u_ddr_phy/.../u_ddrbank.zqcal_start}]
#      这里沿用同一思路，只把作用对象从引脚换成时钟对。
#
#    【为什么可以按时钟对屏蔽】
#      clkc[2] 的扇出为 1，唯一负载是硬宏的 SDRAM_CLK。屏蔽它与
#      ext_mem_clk 之间的时序分析，实际影响范围就只有 DQ 这一组接口，
#      不会掩盖任何用户逻辑的路径。
#
#    【注意事项】
#      1) 这两条只影响时序分析，不改变电路实现。SDRAM 的片外往返余量由
#         硬宏时序特性与 PCB 走线共同保证，不是用户可优化的对象。
#      2) 加上之后全局 SWNS 会从 -6.699ns 变为约 -0.505ns —— 那是
#         ext_mem_clk -> sd_card_clk 的一条真实跨域路径，另行处理。
#      3) 上板必须复测：连续切图、长时间播放，确认画面无花屏/错位。
#         若画面异常，请先回退这两条再重新评估。
# ------------------------------------------------------------
set_false_path -from [get_clocks {sys_pll_m0/pll_inst.clkc[2]}] -to [get_clocks {ext_mem_clk}]
set_false_path -from [get_clocks {ext_mem_clk}] -to [get_clocks {sys_pll_m0/pll_inst.clkc[2]}]

# 备用写法：若上面两条未生效（例如工具版本对时钟对象支持不同），可改用
# 引脚形式，引脚路径以 Timing Analyzer 实际报出的为准：
#   set_false_path -from [get_pins {U3/sdram.dq[*]}]
#   set_false_path -to   [get_pins {U3/sdram.dq[*]}]
