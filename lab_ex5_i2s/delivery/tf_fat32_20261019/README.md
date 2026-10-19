# TF卡多图片：A的RAM上板候选

先用本目录 `tf_fat32_32_candidate.bit` 做 **RAM加载**，不要先写Flash。默认32张，尚未取得上板反馈。

SHA256：`cb1948f2d151a5379022edbcdab7d62b2e1d61b906585656c7c27c5a75a95570`

1. 留好正常P2 bit和原正常卡/镜像，另用测试卡。卡为512B逻辑扇区的FAT32（MBR普通主分区或LBA0卷），不用exFAT/GPT。
2. 图片普通复制到根目录，短名 `0001.BMP`～`9999.BMP`，允许缺号，按编号排序，最多32张。格式为640×480、24位BI_RGB、正高度bottom-up、40B BITMAPINFOHEADER；不支持其他格式/尺寸。
3. 可在源码的lab_ex5_i2s目录运行 `python tf_player/stage3/prepare_test_assets.py --out <新目录> --count 32 --case normal` 生成1～32；`missing_ids`含缺号/9999，`bad_bmp`损坏第二张。复制后核对生成清单的大小/SHA256，安全弹出；连续和碎片卡应另查实际簇链，普通复制不能保证碎片。
4. 原按键：KEY1(A2)复位，KEY2(B2)下一张，KEY3(B1)循环1×→2×→0.5×，KEY4(C1)开关约3秒轮播。
5. 连续/碎片布局分别检查首图、三档、快速切图/缩放/轮播、4→5、31→32、末项回绕和缺号。加载期间旧图保持，成功后图像/序号/字幕共同切换。
6. ID1～4使用原字幕/ROM音轨，其他图片无中文且静音；同图缩放不重启滚动或音轨。坏BMP和中途读卡失败应保持旧图及声音，恢复卡后原下一张可重试；显示F为失败，锁定时用复位恢复。

异常反馈：bit SHA256、板卡/TF卡型号容量、簇大小、文件清单、按键顺序、素材ID/序号/倍率、出现耗时、是否复现及照片/视频（含状态与声音）。实卡速度、多卡、长时、RAM、Flash和掉电结果分别记录。

回退用已正常P2：`../osd_scroll_20261011/osd_scroll_candidate.bit`，并恢复配套旧卡/素材布局；旧裸扫描bit不保证读取新碎片卡。P3未并入。

验证范围与限制见 [RESULTS](RESULTS.md)，身份见 [manifest](manifest.json)。
