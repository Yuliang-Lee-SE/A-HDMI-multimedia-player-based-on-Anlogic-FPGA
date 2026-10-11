# KEY3 2×持续条纹修复候选（2026-10-11）

状态：可交付的待上板验证候选，未完成硬件验收。基线integrate/stage1 `635888dee5e81f0f0f9711929515f69581ea684e`，交付分支 `fix/zoom-sdram-write-pacing`。本次只修复KEY3路径，保留集成版音频/波形，不接入冻结功能；上传不代表下载或Flash烧写授权。

## 修改与证据

正式设计仅修改 `src/user_source/hdl_source/team/bmp_center_zoom_2x.v`，默认PACE_ZOOM_OUTPUT=1，每接受一个2×像素后留一源时钟间隔，降低写FIFO集中输入密度。1×路径沿用原节奏。下游阻塞时保持有效像素，帧开始/复位清间隔状态。没有修改PLL/时钟约束、FIFO、SDRAM控制器或音频顶层。

- 三组既有回归PASS；完整640×480、真实加密SDRAM控制器+自建命令模型，新1×/2×各307200字读回全部正确，显示空读0。
- 同一测试台关闭修复，640×48新2×图再现8428字错误，退出1是预期失败对照。
- 开启修复640×48主动刷新压力PASS。默认完整尺寸没有观察到刷新，不能宣称完整尺寸刷新覆盖。
- 标准工程流程本地综合/布线完成，Routed，setup+0.149ns、hold+0.003ns，TNS均0，coverage96.14%。已知SDRAM clk未驱动及硬宏位置调整警告仍存在，不声称零警告或完整板级时序签核。
- 以上仿真使用合成像素/视频节奏、自建引脚命令模型；不是官方时序模型或SD卡/HDMI整机上板验证。读新图前等待100拍隔离排空，不宣称已解决自动帧提交排空问题。

旧失败包与C构建差异另行调查。已在本机复现C原635888d bit，除日期注释5字节外相同；现在可以在本地构建。旧脚本漏载FIFO跨域IP约束已纠正，但旧花屏确切根因尚未关闭。

## 本目录文件

- `key3_pacing_635888d_candidate.bit`：本地新候选，690152字节，SHA256 `DDFD916482742FB7D2728C646F489CFED30744736FDCAAECA647E8244E72773E`。
- `final_timing.rpt`：该候选最终时序报告。
- `zoom_pacing_full_validation_20261010.log`：回归及完整尺寸仿真。
- `zoom_pacing_disabled_control_20261010.log`：关闭修复的预期失败对照。
- `zoom_pacing_refresh_validation_20261010.log`：开启修复的刷新压力验证。

修复模块SHA256 `5D862AF6DF579941925A745E7DE68310D74626A54FC228AC0C305625AFB28FFC`。源码提交身份以交付分支Git记录为准。bit含生成日期，重建后文件哈希可不同，应保存每次build_result.json。

## 获取与重建

从本交付分支获取工程；若A/C已有后续修改，只合并上述模块，不覆盖其他改动。相对于lab_ex5_i2s，重建入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_verified_project_build.ps1 -RunName key3_verify
```

TD默认路径适用于小一本机，可用-TdExecutable传入实际路径。模板来自C的635888d标准工程流程，保留FIFO IP约束；源清单/属性、顶层和器件不匹配时停止，其他运行策略变化需重新导出审查模板。脚本拒绝覆盖旧输出，保存输入/模板/工具哈希、完整日志和最终报告；负WNS/TNS或错误时不生成bit。输出位于src/td_project/key3_verify_Runs，仍需检查关键警告和覆盖率。不要将tb、模型或delivery目录加入TD设计源。

## 后续验收

由持板者按已有授权范围进行RAM验证，记录实际bit SHA256：默认1×，按一次KEY3等待加载完成后观察2×稳定画面，回1×；往返十次，再复测切图、轮播、音频/波形和复位。记录是否仍有横纹/块错位、是否出现状态F，以及构建版本/bit哈希。验证失败保留日志/照片，恢复已保存的正常工程或bit；不要覆盖唯一可回退版本。

未完成：修复候选板上效果、旧默认花屏确切根因、Flash及掉电启动。取得明确板上反馈后才能标记KEY3硬件验收通过。
