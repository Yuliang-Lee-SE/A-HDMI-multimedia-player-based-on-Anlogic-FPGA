# 本地标准工程复现与单变量对照

2026-10-11，用户授权本地构建。没有上传、合并、下载、烧写或Flash操作；历史产物和2×源码修复均保留。

## 结论

本地标准工程流程已复现C的635888d配置内容：690152字节bit与C原bit逐字节对比，仅偏移133、135、136、138、139五处不同，全部位于ASCII头部日期注释。其余字节完全一致，头部CRC相同。最终时序报告正文完全一致，只差生成日期与约束绝对路径。因此已证明本机/命令行能够复现C此包的结果，后续不需要把编译长期交给A/C。

这不等于定位旧325391...失败包根因：旧源码输入没有完整快照，且旧与新包含的功能不同，不能用复现新包代替旧包同源实验。板上1×正常、2×持续条纹的反馈尚未以实际下载bit哈希严格绑定。所有新产物仍须分层验证。

## 实验对象与结果

隔离目录 `C:/Users/j1573/Documents/ChatGPT/PLD/repo-build-audit`，detached HEAD 635888dee5e81f0f0f9711929515f69581ea684e；没有正式源码修改。最初尝试D盘创建工作树因权限失败，改用可写PLD目录成功，未清理或覆盖旧目录。

三个case均在例程src/td_project下，使用C原生成.prj/.tcl/settings.cfg，目录深度与原Runs一致，源码/已生成IP及初始化文件来自635888d。TD版本均6.2.168116。各阶段退出0，完成标记/报告与日志核对；同样保留供应商警告。

| Case | 唯一变化 | Setup WNS/TNS(ns) | Hold WNS/TNS(ns) | coverage |
| --- | --- | --- | --- | --- |
| audit_standard | 无，复现C流程 | -0.001/-0.001 | +0.003/0 | 96.21% |
| audit_no_ip_sdc | IpSDCList清空，保留主SDC及packarea | +0.083/0 | +0.011/0 | 96.14% |
| audit_no_packarea | area_option清空，保留IP约束 | -0.001/-0.001 | +0.003/0 | 96.21% |

standard生成bit仅用于复现C：SHA256=9FE5A28E6E1A31C8A58B5BD98B3587033D4EDA7B9E348724AEF55BAF7DCE0745；C原bitSHA256=31A299CBFBC69D31D2DB29AAFD5D5411DD7B6EEEABAFA7B64515401B782F0B7A。其建立时间违例仍存在，不能作为时序验收通过。两个单变量case止于布线，不生成bit、不上板。no_packarea最终时序正文与standard一致（忽略日期/约束路径）；该选项在本例未产生可见最终时序/路径差异，不能断言所有工程都无影响。该case未生成同名gate.area，不据缺失报告宣称资源逐字一致。

去掉FIFO约束会改变布局和时序，但全局WNS仍可变得更正，不能把正WNS当缓存跨域安全保证。FIFO约束遗漏是已确认旧脚本缺陷，是否解释旧板上花屏仍需同源/硬件对照。相同SDRAM clk未驱动警告在standard、C和旧候选均存在，不是区分原因。

基线输入清单build_inputs_baseline_clean_20261011.json记录91文件；早期build_inputs_baseline_635888d_20261011.json收录202文件，混入audit输出，仅保留历史，不能当纯输入清单。采集脚本已排除audit_*及*_Runs输出。

## 当前2×修复构建结果

repo-zoom-fix保留635888d集成基线和单正式模块改动，使用同一标准模板及新的run_verified_project_build.ps1运行：

- 输出：`src/td_project/audit_pacing_20261011_Runs/`，输入前后91文件哈希一致，模板6文件与工具哈希留档。
- 正式模块SHA256仍为5D862AF6DF579941925A745E7DE68310D74626A54FC228AC0C305625AFB28FFC。
- Routed，setup+0.149ns/TNS0，hold+0.003ns/TNS0，coverage96.14%；5217 LUT、4105寄存器、24 BRAM9K、12 BRAM32K、1 DSP、3 PLL。
- bit=690152字节，SHA256=DDFD916482742FB7D2728C646F489CFED30744736FDCAAECA647E8244E72773E。完整日志/前后清单/build_result.json与报告在输出目录。
- 保留SDRAM读寄存器clk未驱动、PHY-7002硬宏位置调整等警告，不称无警告；硬宏/外部接口与未约束路径不能由正WNS覆盖。板上未验证，不宣称2×花屏已修好。

已有完整尺寸仿真与失败对照见KEY3_2x_pacing_fix.md，本阶段未重复仿真；当前源码未再次修改。

## 可重复入口

例程根执行（每次新RunName，不覆盖已有输出）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_verified_project_build.ps1 -RunName next_build
```

默认TD路径可用-TdExecutable指定。脚本保留C标准模板，先比对当前.al与模板的源清单/属性、顶层和器件；不一致时停止，防止新增源被静默漏编。可用-ValidateOnly只检查。当前模板专用于该工程，修改其他工程运行策略/宏/配置后应重新导出并审查，不能视为通用TD封装。

入口创建新目录，采集输入与模板/工具哈希，依次综合和布线，检查完成标记/ERROR/最终Routed报告及输入未变；任一负WNS/TNS停止，不生成bit。通过后单独bitgen并记录哈希。关键警告和约束覆盖仍需人工审查，流程不替代硬件验收。完整构建成功后增加的源清单防陈旧检查已用-ValidateOnly验证通过；没有为此重跑整机。

下一步将当前候选与A实际下载记录绑定，由A按授权范围验证1→2→1、切图、音频/波形和复位。旧花屏包根因仍保留未关闭，已解决的是“本地不能复现C构建”的疑点，并修正今后漏载FIFO约束的流程。
