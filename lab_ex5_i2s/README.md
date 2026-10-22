# TF卡多图片播放器

当前使用[CRC修复版 bit 与用卡说明](delivery/tf_crc_fix_20261021/README.md)，默认最多32张。

2026-10-22板测反馈：用户确认正常读卡，并确认首图与声音、KEY2切到第5张及后续、KEY3三档缩放均正常。完整32张逐项、字幕/轮播/异常恢复/碎片/多卡/长时和Flash掉电启动尚未分别验收；实际加载模式未另确认。

基于正常P2/FAT32分支，包含复位、CMD8字段及CMD59 CRC协商修复，保留全部校验；未合入main后续集成功能。bit SHA256开头791da91d，与本次板测推荐文件一致。

[完整板测清单](delivery/tf_crc_fix_20261021/TESTING.md) · [技术结果及源码身份](delivery/tf_crc_fix_20261021/RESULTS.md) · [正常P2回退](delivery/osd_scroll_20261011/README.md)

工程入口：src/td_project/HDMI1.4b_Transmitter_v1.0.al。只上传最终修复和必要交付；旧失败与中间bit继续保留在原本地树。
