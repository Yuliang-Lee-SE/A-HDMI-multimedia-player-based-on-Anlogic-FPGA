# rtl/ — 团队 testbench 使用的 RTL 镜像

- 本目录由 `scripts\sync_rtl.bat` 从 `lab_ex5_i2s/src/user_source/hdl_source/` 单向同步生成；
- 禁止直接修改本目录，改动会在下次同步时被覆盖；
- 需要修改 RTL 时，改 `lab_ex5_i2s/src/user_source/hdl_source/`，然后运行同步脚本；
- 官方例程自带的 `lab_ex5_i2s/rtl/` 是厂商 testbench 使用的镜像，两套互不干扰。
