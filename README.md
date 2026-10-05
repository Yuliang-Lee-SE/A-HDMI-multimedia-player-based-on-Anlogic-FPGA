# 基于安路 EG4S20 的 HDMI 多媒体播放系统

全国大学生嵌入式芯片与系统设计竞赛 · 安路赛道 · 选题一
应用场景：博物馆展品讲解屏

## 仓库结构

| 路径 | 用途 |
| --- | --- |
| `lab_ex5_i2s/` | 官方 lab_ex5 例程基线（完整 TD 工程，编译与下板以此为准） |
| `lab_ex5_i2s/src/user_source/hdl_source/` | RTL 唯一权威源码 |
| `lab_ex5_i2s/src/user_source/constraints_source/` | 引脚与时序约束 |
| `lab_ex5_i2s/src/td_project/HDMI1.4b_Transmitter_v1.0.al` | TD 工程文件 |
| `rtl/` | 团队 testbench 使用的 RTL 镜像（由脚本单向生成，禁止手改） |
| `tb/` | 团队 testbench |
| `scripts/` | 图片转换、TF 卡同步、RTL 同步脚本 |
| `assets_src/` | 原始素材（图片、音频、字库源） |
| `assets_out/` | 生成的 BMP/WAV（不提交） |
| `doc/` | 团队文档 |

## 快速开始

1. 安装安路 TD 与板载 USB 下载器驱动；
2. 用 TD 打开 `lab_ex5_i2s/src/td_project/HDMI1.4b_Transmitter_v1.0.al`；
3. HDMI 线接开发板 `HDMI_B`，TF 卡放入 640×480、24 位非压缩 BMP；
4. 综合、布局布线、生成比特流并下载；
5. 按 `doc/仓库结构与基线说明.md` 中的流程修改代码和提交。

## 文档

- `团队分工计划.md`
- `doc/仓库结构与基线说明.md`
- `doc/接口约束文档.md`
- `doc/顶层框图与时钟复位说明.md`

## 远程仓库

- `origin`：GitHub（主仓库）
- `gitee`：Gitee（镜像备份）
