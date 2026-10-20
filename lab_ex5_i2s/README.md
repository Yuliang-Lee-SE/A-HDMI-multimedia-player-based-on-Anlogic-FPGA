# TF卡多图片播放器

**当前为 TF 复位修复候选，待 A 做 RAM 测试。需要 TF 卡（microSD），请按[卡格式、图片与测试步骤](delivery/tf_fat32_reset_20261020/TESTING.md)操作。**

[新候选bit与交付入口](delivery/tf_fat32_reset_20261020/README.md) · [验证结果/资源时序](delivery/tf_fat32_reset_20261020/RESULTS.md)

原 TF 候选已反馈黑屏，保留作历史；本轮修复一个已复现的 TF/SPI 复位缺陷，板上黑屏根因仍未证实，不能视为已解决。

工程入口：`src/td_project/HDMI1.4b_Transmitter_v1.0.al`。P2正常回退保留，P3未并入；当前候选待A先RAM上板，Flash/掉电另测。
