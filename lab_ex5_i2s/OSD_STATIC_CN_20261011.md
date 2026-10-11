# 三档缩放＋中文字幕

在底部增加四组中文测试标题和简介，保留原来的切图、轮播、1×/2×/0.5×缩放、PLAY/AUTO及音频波形。切图成功后字幕一起更新，加载失败保留旧图旧字幕，缩放时字幕位置和字号固定。

整合版已通过本地仿真、综合布线和bit构建，待上板。直接使用 [交付目录中的bit和测试说明](delivery/osd_three_zoom_20261011/README.md)，布局见 [预览](osd_assets/preview_1.png)。这版将已上板正常的三档倍率 `8f50462` 与中文字幕整合，KEY3按1×→2×→0.5×循环。整合版需重新上板验证。

## 改文案和重建

文案在 `osd_assets/captions_test.json`，按图片1～4排列。标题最多16字形，简介最多64字形，屏幕只显示前35字形，暂不滚动。当前为16×16黑体测试资源，正式文案和字体后续再定。

在 `lab_ex5_i2s` 下执行，Python需安装Pillow：

```powershell
python tools/generate_osd_resources.py
powershell -NoProfile -ExecutionPolicy Bypass -File ./run_osd_three_validation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./run_verified_project_build.ps1 -RunName osd_rebuild_unique
```

每次构建换一个新的RunName。新增源文件时同步更新工程模板和输入采集，保留FIFO IP约束。

字幕模块在 `src/user_source/hdl_source/team/`：`osd_text_renderer.v`负责显示，`osd_resources.v`由脚本生成，`osd_display_commit.v`负责图片和字幕共同切换。修改提交逻辑时注意：显示应答回来之前不能复用旧图片bank。

完整存储仿真耗时较长；`-ModulesOnly`只跑模块组合回归，不代表存储验证。最终数据和模型范围见交付目录的 `RESULTS.json`，ROM审计入口为 `audit_osd_three_rom.tcl`、`check_osd_three_bram_init.py`。
