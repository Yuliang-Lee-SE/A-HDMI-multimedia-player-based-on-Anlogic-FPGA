# 滚动简介字幕

标题固定；超过35字形的简介在560像素窗口内向左滚动，短文静止。每2帧移动1像素，开头和最后一屏各停45帧，尾部移出后留32像素空白，再回到开头。按约60Hz计算，速度约30像素/秒、停顿约0.75秒。

位置只在视频VS结束的消隐期更新。展品ID取已提交的显示ID：新展品从头开始，同图缩放、加载失败不重置。文字、RGB、HS、VS、DE沿用三级延迟。`scroll_pause`是同视频时钟域接口，按帧生效、暂停时保留速度和停顿进度；整机固定接0，不新增按键。未来跨域控制需另加可靠同步。

图片1、3为长测试文案，2、4为短文。轮播仍每3秒切图，查看完整长文请使用手动模式。字体保留标点修正；文案仍在 `osd_assets/captions_test.json`，最多4组、标题16字形、简介64字形。

在 `lab_ex5_i2s` 下运行：

```powershell
python tools/generate_osd_resources.py
powershell -NoProfile -ExecutionPolicy Bypass -File ./run_osd_scroll_validation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./run_verified_project_build.ps1 -RunName osd_scroll_20261011
```

重复构建请换新的RunName及测试Label，不覆盖证据。ROM审计用 `audit_osd_scroll_rom.tcl`、`check_osd_scroll_bram_init.py`；它们和 `package_osd_scroll.py` 的RUN路径需与重建目录一致。GIF由 `tools/prepare_osd_scroll.py` 生成，图像与生成脚本均纳入输入哈希。

滚动控制与显示同在 `team/osd_text_renderer.v`，长度表由生成器追加到 `team/osd_resources.v`，因此工程源列表无需新增文件；标准模板一致性检查仍执行。未改图片提交、BMP、缩放、存储、音频、FIFO IP或约束。

验证分层：控制器覆盖2228帧（空/短/临界/64字、停顿、暂停恢复、循环、连续ID变化、使能和帧内稳定）；14帧4300800像素用Python独立屏幕坐标模型逐像素对比，覆盖1/15/16/17像素偏移、最后一屏、尾字符、空白间隔与窗口边缘。像素测试固定控制器输出以单独核对寻址，真实VS/提交测试再验证控制器与渲染器连接、新ID重置和同ID换bank继续。原静态、ROM、状态/波形、三档画布、BMP控制、FIFO模块一并回归。

完整SDRAM回归引用上一版，存储与提交RTL没有改动，本次未重跑。模型和本地构建通过不代替上板；本轮P2候选、真实声音/HDMI、长时、Flash及掉电启动均待持板者验证。
