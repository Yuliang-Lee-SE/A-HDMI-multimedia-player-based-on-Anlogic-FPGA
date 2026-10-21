# TF卡多图片播放器

**当前排查 SD 初始化失败。最新复位版 `1e4f3111` 也已板测失败，请使用[初始化诊断版与三步测试](delivery/tf_init_diag_20261021/TESTING.md)取得完整错误码。**

[诊断bit与用卡说明](delivery/tf_init_diag_20261021/README.md) · [验证结果/资源时序](delivery/tf_init_diag_20261021/RESULTS.md)

两份旧 TF 候选均保留作失败历史；诊断版只增加错误读出，尚未确认初始化根因，没有宣称修复成功。继续使用已核对的同一卡和图片，先RAM加载后拍整排数码管。

工程入口：`src/td_project/HDMI1.4b_Transmitter_v1.0.al`。P2正常回退保留，P3未并入；当前候选待A先RAM上板，Flash/掉电另测。
