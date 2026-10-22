# CRC模式协商：本地结果及限制

2026-10-22板测反馈：用户确认正常读卡，并确认首图与声音、KEY2切到第5张及后续、KEY3三档缩放均正常。完整32张逐项、字幕/轮播/异常恢复/碎片/多卡/长时和Flash掉电启动尚未分别验收；实际加载模式未另确认。

发布源码提交：`f00a48482cadedfb3ecd43f8854ffc6905c2ebcf`。136项实际构建输入/模板与该提交检出逐项核对；原本地源码79c98df和交付f6e2f0f保留，不上传中间失败bit。本次仅整理发布，未重新构建，bit及报告不变。以下为2026-10-21本地构建时记录，旧待板/不上传状态由此更新。


源码 `79c98df72325b5b3a62f1c78001ea3267dcafde0`，基于214abad/bit36e997f3。A反馈下载已能运行但黑屏，照片50900F：CMD9 CSD数据CRC16不匹配、末收到00。证明该次越过CMD8，不代表CSD内容正确；不能由00认定完整CRC0000。实际完整CSD/CRC未取得，当前加载方式未另复核，Flash校验失败与运行失败分开记录。

发现原程序未发CMD59，却要求数据CRC16。依据[SD Association规范7.2.2](https://www.sdcard.org/cms/wp-content/themes/sdcard-org/dl.php?f=Part1_Physical_Layer_Simplified_Specification_Ver5.10.pdf)关于SPI默认CRC OFF/ACMD41前启用CRC的说明，以及[Zephyr/NXP的sd_enable_crc](https://github.com/zephyrproject-rtos/zephyr/blob/main/subsys/sd/sd.c)。本次在CMD8正常或旧卡路径后、CMD55/ACMD41前发送CMD59(arg1)，只接受R1=01，复用低速字节接口与有界预算。没有关闭CRC或放宽容量/格式/超时。自有RTL，未导入第三方代码。

## 本次验证

16组真实SPI对照PASS：SDHC/SDSC/旧卡，关闭CRC时仍给有效CRC/给0000/给FFFF，CMD59拒绝/无响应/虚假应答、CSD CRC错误、扇区三次坏CRC零数据泄漏/首次失败重试成功、重新初始化再次协商。独立长除法CRC7已核对CMD0=95、CMD8=87、CMD59(arg1)=83，并校验CRC启用后的所有主机命令。旧214abad同台可复现50900，新协商后能初始化并正确读512B；坏CRC仍拒绝。0000/FFFF是模型反例输入，**不是A实卡内容或根因证明**。

当前R7字段34、SPI37、容量10、短8（含16/32/64参数）、实际top6复位/32项重新挂载、六位扫描/清除/恢复、31→32索引70检查均PASS。12诊断/恢复场景与716e816明确只增加CMD59的协议参考逐周期比较；不是与未修改716e816等价，原参考及变换后参考均有哈希。独立SD映射1组非零R7+CRC关闭反例PASS，使用厂商原语；只加速LOW_DIV/POWER，非整机候选网表/生产参数门级或实板。独立单元I/O/厂商未接端口与Starter容量警告留档，不用它宣称整机资源通过。

实际top `crc_rgb01` 在模型CRC关闭返回0000的条件下，经行为卡→真实SPI/FAT→完整BMP→原FIFO→真实加密SDRAM控制器/自建引脚模型→RGB/AXIS/共同提交及声音启用映射PASS。完整307200原RGB像素、OSD后172800图像像素逐点匹配且非零，并检查扇区读取前已协商CRC。同台换214abad旧SD `crc_rgb_negative01` 如预期50900。理想PLL/行为ROM采用真实MIF，HDMI在接收边界建模；不等于实体卡、物理声音/HDMI或板测。

当前源码 `crc_player01` 真实SPI五次整图提交＋一次失败恢复PASS，沿用原五次场景和像素/归属/元数据断言，仅增加CRC_OFF_POLICY=1和进度输出，覆盖忙时缩放、坏读保持旧图、ID4→5静音、0.5×重载；帧接收仍是理想模型，不能替代真实SDRAM。物理存储端到端只新跑默认1×首帧，未重跑三档含SPI完整存储矩阵。按全部输入哈希未变引用独立storage_v12三档640×480正常/主动刷新、0/307200双bank读回/持续视频/无欠载/完成后物理写，cancel_v12五取消边界、canvas_final15b三配置21场景、offline_final15 FAT76；旧含SD整套不冒称本版通过。字幕cmd8_captions01的2150400黄金像素只在全部实际输入仍一致范围引用，含ID1～4及无映射5/8193/9999。固定整帧镜像ID1～31及9999，不冒称实际32号图片；32号由独立真实索引台另验。64为参数仿真，无独立硬件构建。

## 标准构建与审查

原工程ValidateOnly→RouteOnly→最终门禁→原模板bitgen，130输入+6模板，共136项在route/bit前后和Git检出匹配，工具哈希绑定manifest。TD6.2.168116/EG4S20BG256/top，默认32张/MAX_CHAIN2048；.al清单/顺序/属性与模板一致，原PLL/FIFO IPC/厂商控制器/有效约束保留。

Routed setup+0.107ns/TNS0、hold+0.011ns/TNS0、period0，coverage98.82%。最终物理LUT10973/19600、REG8028/19600、BRAM9K53/64、BRAM32K12/16、DSP4/29、PLL3/4。读/写Gray datapath_only7.7ns各18条有效路径、0违例，WNS+6.388/+6.492ns。关键setup至FAT cached_lba使能，8级逻辑/9.600ns；裕量较小，只对绑定构建成立，没有削减集合/容量或放宽约束。

文本512、字形2048、音频49152 INIT及低地址映射PASS；FAT2048×28集合/128×28缓存/512×8扇区/32×78索引、SD扇区同步RAM映射PASS。诊断跨域保持payload＋两级valid＋额外两拍采样，只进数码管。时钟/约束/警告类别计数与既定基线一致：no_clock/invalid/组合环/忽略0；dummy3/PLL3、缺input6/output23、硬宏abnormal32。原PLL补偿/SDRAM初始位置/未驱动/HDMI FIFO INIT等警告保留。未实测外部PCB/SPI延迟，正WNS不是完整板级签核。

完整日志、源输入、旧失败/中止和首次误命名短测目录均保留；最终短8在独立crc_short01重新取证，没有覆盖旧证据。候选仅本地交付，不上传/PR/合并/烧写或实体卡操作。新候选待原卡反馈；实卡吞吐/多卡/长时/RAM/Flash/冷启动分别待持板者验收。P2及旧素材布局保留，P3未并入。
