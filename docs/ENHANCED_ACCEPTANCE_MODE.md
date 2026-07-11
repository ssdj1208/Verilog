# B 题加强版验收模式使用教程

本文档用于 NEXYS4 DDR 实板验收和答辩展示。按本文顺序操作，可以依次展示完整 SoC、RV32I/RV32M、DDR、Cache、FP32、Timer/IRQ、性能计数器、五级流水、数据冒险、控制冒险和中断冲刷。

工程提供两种互不冲突的工作模式：

- `SW15=0`：正常系统模式，启动自检后进入 UART Shell，可执行一键验收命令 `accept`。
- `SW15=1`：流水演示模式，通过 LED 和八位数码管观察五级流水及确定性场景。

> `SW15` 在复位期间锁存。改变 `SW15` 后必须按中心按钮 `btnC` 复位，新的模式才会生效。

## 1. 验收环境

当前实板验证使用以下环境：

| 项目 | 配置 |
| --- | --- |
| FPGA 开发板 | NEXYS4 DDR |
| FPGA 器件 | `xc7a100t_0` / `xc7a100tcsg324-1` |
| Vivado | 2023.2 |
| JTAG | Digilent `210292747828A` |
| UART | FTDI `COM8` |
| 串口参数 | 115200 baud、8 data bits、1 stop bit、no parity、no flow control |
| CPU/SoC 时钟 | 100 MHz |
| bitstream | `build/bupt_riscv_top.bit` |

最终验收构建的参考结果：

| 指标 | 结果 |
| --- | ---: |
| WNS | `+0.055 ns` |
| TNS | `0.000 ns` |
| WHS | `+0.020 ns` |
| THS | `0.000 ns` |
| LUT | `17974 / 63400 (28.35%)` |
| Registers | `31413 / 126800 (24.77%)` |
| BRAM Tile | `5 / 135 (3.70%)` |
| DSP | `2 / 240` |
| Power | `1.185 W`，Vivado 估算值 |
| bitstream SHA-256 | `70DEBC19BDA698754149EB2E1806CAB52D2C50C6F633146D768274970EA5A5D0` |

100 MHz 是已经通过实现后时序检查的工作频率，不应表述为实测最高 Fmax。功耗为 Vivado 在默认活动率下的估算值，不应表述为精确实测功耗。

## 2. 上板前准备

以下命令均在工程根目录 `Verilog` 下执行。

### 2.1 生成 Boot ROM

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

生成结果应满足：

- `src/bupt_riscv/bupt_riscv_boot.mem` 为 4096 words。
- 再执行一次生成器时，ROM 内容不发生变化。
- 最高有效代码地址低于 `0x4000`。

### 2.2 运行完整仿真

```powershell
D:\Xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source scripts\sim_bupt_riscv.tcl
```

日志应包含：

```text
Simulation succeeded: enhanced acceptance UART verified
Simulation succeeded: BUPT RISC-V CPU verified
Simulation succeeded: pipeline demo stepping verified
Simulation succeeded: enhanced pipeline scenarios verified
Simulation succeeded: pipeline demo panel verified
Simulation succeeded: acceptance MMIO verified
BUPT_RISCV_SIM_DONE
```

以上成功标记必须全部出现，且日志中不得出现 `Simulation Failed`。

### 2.3 生成 bitstream

```powershell
D:\Xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source scripts\build_bupt_riscv.tcl
```

构建完成后确认：

- 存在 `build/bupt_riscv_top.bit`。
- `write_bitstream` 成功。
- WNS、TNS、WHS、THS 均无负值。

### 2.4 下载到 FPGA

连接板卡 USB/JTAG 后执行：

```powershell
D:\Xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source scripts\program_bupt_riscv.tcl
```

下载成功标志为：

```text
BUPT_RISCV_PROGRAMMED=xc7a100t_0
```

若下载时已经设置好 `SW15`，配置完成后系统会按该模式启动。若模式不确定，重新设置 `SW15` 并按 `btnC`。

## 3. 板上操作界面

### 3.1 按钮

| 按钮 | 流水演示模式功能 |
| --- | --- |
| `btnC` | 系统复位，并重新锁存 `SW15` 模式 |
| `btnU` | 运行/暂停切换 |
| `btnL` | 暂停时单步推进一个 CPU 周期 |
| `btnR` | 在完整 PC 页和完整指令页之间切换 |
| `btnD` | 切换慢跑速度档位 |

正常系统模式主要使用 `btnC`。其余流水控制按钮只在 `SW15=1` 时用于演示。

### 3.2 开关

正常系统模式：

- `SW15=0` 选择 Boot/Shell。
- 执行 `accept` 后，`SW[3:0]` 选择 16 组验收指标。
- `SW[14:4]` 没有专用的验收面板选择功能，但仍可通过面板 MMIO 读取。

流水演示模式：

| 开关 | 功能 |
| --- | --- |
| `SW15` | `1` 选择流水演示模式 |
| `SW7` | `0` 显示 PC/指令，`1` 显示场景结果 |
| `SW[6:3]` | 选择场景 `0`～`F` |
| `SW[2:0]` | 选择 IF/ID/EX/MEM/WB 流水级 |

流水级选择编码：

| `SW[2:0]` | 流水级 |
| --- | --- |
| `000` | IF |
| `001` | ID |
| `010` | EX |
| `011` | MEM |
| `100` | WB |
| `101`～`111` | 按 IF 显示 |

### 3.3 流水模式 LED

| LED | 含义 |
| --- | --- |
| LD0 | IF 级 valid |
| LD1 | ID 级 valid |
| LD2 | EX 级 valid |
| LD3 | MEM 级 valid |
| LD4 | WB 级 valid |
| LD5 | load-use stall 已发生 |
| LD6 | mul/div stall 已发生 |
| LD7 | I-Cache/取指 stall 已发生 |
| LD8 | D-Cache/DDR stall 已发生 |
| LD9 | branch flush 已发生 |
| LD10 | trap/interrupt flush 已发生 |
| LD11 | 当前暂停 |
| LD12 | 当前运行 |
| LD13 | 当前为指令页 |
| LD14 | 当前速度档位 |
| LD15 | 当前处于流水演示模式 |

LD5～LD10 是场景内锁存事件。事件即使只持续一个 CPU 周期，也会保持点亮，直到切换场景或复位。切换场景后旧事件 LED 清零是预期行为。

### 3.4 流水模式数码管

当 `SW7=0` 时：

- `btnR` 在 PC 页和指令页之间切换。
- PC 页显示所选流水级的完整 32-bit PC。
- PC 页最右侧小数点点亮，表示所选流水级当前 `valid=1`。
- 指令页显示所选流水级的完整 32-bit 指令编码。
- 指令页打开时 LD13 点亮。

当 `SW7=1` 时：

- 数码管显示当前场景写入验收 MMIO 的 32-bit 结果。
- `btnR` 仍可改变内部 PC/指令页状态，但结果页会覆盖两者。
- 将 `SW7` 拨回 0 后恢复 PC/指令显示。

## 4. 推荐验收顺序

建议严格按以下顺序展示。这样先证明系统完整可运行，再展示流水内部行为，最后证明两种模式可以重复切换。

1. 下载最终 bitstream，并保存下载成功日志。
2. 设置 `SW15=0`，按 `btnC`，保存正常 Boot 和 Shell 输出。
3. 在串口执行 `accept`，保存完整自动验收输出。
4. 拍摄 16 个 LED 全亮以及 `SW[3:0]=0` 时的 `ACCE5500`。
5. 翻动 `SW[3:0]`，展示 CPI、MIPS、Cache 命中率和分支预测准确率。
6. 执行 `accept clear`，确认返回 `OK` 并恢复普通面板。
7. 设置 `SW15=1`，按 `btnC`，展示暂停、运行、速度、单步和五级 PC/指令。
8. 从场景 0 开始，再依次展示场景 1～7。
9. 设置 `SW15=0`，按 `btnC`，确认 UART Shell 再次出现 `rv32>`。
10. 展示 Vivado timing、utilization、power 和 bitstream SHA-256 记录。

## 5. 正常系统与一键验收

### 5.1 进入正常系统

1. 将 `SW15` 置 0。
2. 按中心按钮 `btnC`。
3. 打开 COM8，设置为 115200、8N1、无流控。
4. 等待 Boot 自检和 Shell 提示符。

正常启动输出应包含：

```text
BUPT RISC-V CPU PROJECT
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
rv32>
```

启动失败、停在 DDR 校准前或没有出现 `rv32>` 时，不应继续记录 `accept` 结果，应先排查复位、串口和 DDR。

### 5.2 执行一键验收

在 Shell 输入：

```text
accept
```

命令会检查 RV32I、RV32M、DDR、D-Cache/LRU、I-Cache、FP32、Timer/IRQ、GPIO 和性能计数器，并运行 ALU、MEM、Branch benchmark。

最终实板的一次参考输出如下。cycle、retired、Cache 统计和性能数值会随运行时机小幅变化，不要求逐字符一致。

```text
=== BUPT B ACCEPTANCE V1 ===
CLOCK 100.000 MHz
[PASS] RV32I
[PASS] RV32M
DDR TEST OK
[PASS] DDR
CACHE READY
[PASS] DCACHE LRU
[PASS] ICACHE
FP TEST OK
[PASS] FP32 ADD result=0x40700000
[PASS] FP32 MUL result=0x40400000
[PASS] TIMER IRQ
ALU cycles=43048 retired=8009 CPI=5.374 IPC=0.186 throughput=18.60 MIPS
MEM cycles=5408 retired=461 CPI=11.731
DCACHE accesses=128 hits=48 misses=80 replacements=0 hit_rate=37.50%
BRANCH branches=3301 mispredicts=504 accuracy=84.73%
ICACHE accesses=964222 hits=964129 misses=96 hit_rate=100.00%
ACCEPT_STATUS=FFFF
ACCEPTANCE PASS
rv32>
```

固定通过条件是：

- UART 列出的自检项目均打印 `[PASS]`。
- FP 加法结果为 `0x40700000`，即 3.75 的 FP32 编码。
- FP 乘法结果为 `0x40400000`，即 3.0 的 FP32 编码。
- CPI、IPC、MIPS、命中率和预测准确率的分母非零，结果处于合理范围。
- 最终出现 `ACCEPT_STATUS=FFFF`。
- 最终出现 `ACCEPTANCE PASS` 并返回 `rv32>`。

若出现 `[FAIL]`、`[SKIP]`、`ACCEPTANCE FAIL` 或状态不是 `FFFF`，应保存完整串口输出，不要只记录最后一行。

### 5.3 正常模式 LED

执行 `accept` 后，LED 表示各验收项是否通过：

| LED | 验收项 |
| --- | --- |
| LD0 | RV32I |
| LD1 | RV32M |
| LD2 | DDR |
| LD3 | D-Cache/LRU |
| LD4 | I-Cache |
| LD5 | FP32 加法 |
| LD6 | FP32 乘法 |
| LD7 | Timer/IRQ |
| LD8 | GPIO 回读 |
| LD9 | 性能计数器有效 |
| LD10 | ALU benchmark |
| LD11 | MEM benchmark |
| LD12 | Branch benchmark |
| LD13 | CPI/IPC/MIPS 计算有效 |
| LD14 | Cache/预测比例有效 |
| LD15 | 全部验收通过 |

全部通过时应观察到 `LD[15:0]=16'hFFFF`，即 16 个 LED 全亮。

### 5.4 正常模式数码管

`accept` 完成后，通过 `SW[3:0]` 选择显示指标：

| `SW[3:0]` | 显示内容 | 通过时的判断方法 |
| --- | --- | --- |
| `0` | 总状态 | `ACCE5500`；失败时为 `BAD0xxxx` |
| `1` | 状态位图 | 全部通过时为 `0000FFFF` |
| `2` | ALU CPI | 十进制定点数，有小数点 |
| `3` | ALU 吞吐量 | MIPS，十进制定点数，有小数点 |
| `4` | MEM CPI | 十进制定点数，有小数点 |
| `5` | D-Cache 命中率 | 百分比，保留两位小数 |
| `6` | D-Cache miss 数 | 十进制计数 |
| `7` | D-Cache replacement 数 | 十进制计数 |
| `8` | 分支预测准确率 | 百分比，保留两位小数 |
| `9` | 分支误预测数 | 十进制计数 |
| `A` | I-Cache 命中率 | 百分比，保留两位小数 |
| `B` | FP 加法结果 | `40700000` |
| `C` | FP 乘法结果 | `40400000` |
| `D` | Timer tick | 非零计数 |
| `E` | 前递事件数 | 十进制计数 |
| `F` | 总 stall 数 | 十进制计数 |

答辩时推荐至少展示 `0`、`2`、`3`、`5`、`8`、`A`、`B` 和 `C`，这样可以同时覆盖总体状态、性能、Cache、分支预测和浮点功能。

### 5.5 退出验收面板

输入：

```text
accept clear
```

预期返回：

```text
OK
rv32>
```

验收 LED 状态被清除，数码管恢复正常系统下的空白状态，Shell 保持可用。

## 6. 流水演示基础操作

### 6.1 进入流水模式

1. 将 `SW15` 置 1。
2. 建议先将 `SW[6:3]` 置 0、`SW7` 置 0。
3. 按 `btnC`。

复位后预期：

- LD15 点亮，表示流水演示模式有效。
- LD11 点亮，表示 CPU 初始暂停。
- LD12 熄灭。
- UART 不进入 Shell，这是预期行为。

### 6.2 展示连续运行和速度

1. 按一次 `btnU` 开始慢跑。
2. 确认 LD11 熄灭、LD12 点亮。
3. 观察 LD0～LD4 和数码管 PC 随流水推进变化。
4. 按 `btnD` 切换速度，确认 LD14 和变化速度同步改变。
5. 再按一次 `btnU` 暂停，确认 LD11 重新点亮。

### 6.3 展示单步

1. 保持暂停状态。
2. 将 `SW7` 置 0。
3. 使用 `SW[2:0]` 选择一个流水级。
4. 连续按 `btnL`，每次只推进一个 CPU 周期。
5. 依次选择 IF、ID、EX、MEM、WB，观察同一段程序逐级推进。

### 6.4 展示 PC 和指令

1. 将 `SW7` 置 0。
2. 使用 `SW[2:0]` 选择流水级。
3. LD13 熄灭时，数码管显示该级完整 PC。
4. 按 `btnR`，LD13 点亮，数码管显示该级完整指令。
5. 再按 `btnR` 返回 PC 页。

PC 页最右侧小数点表示该级当前有效。暂停后切换各级，更容易对照五级 PC、指令和 LD0～LD4 的 valid 状态。

## 7. 流水场景验收

### 7.1 每个场景的统一操作方法

对场景 0～7 使用以下步骤：

1. 保持 `SW15=1`。
2. 用 `SW[6:3]` 选择场景。
3. 场景切换后观察 LD5～LD10 清零。
4. 按 `btnU` 运行，等待场景完成若干轮。
5. 按 `btnU` 暂停。
6. 检查对应事件 LED。
7. 将 `SW7` 置 1，读取 32-bit 场景结果。
8. 如需观察内部流水，将 `SW7` 置 0，再使用 `btnL`、`btnR` 和 `SW[2:0]`。

场景程序只在循环边界读取 `SW[6:3]`。刚切换场景时，数码管可能短暂保留上一场景结果；继续运行到新场景完成一轮后会更新。

### 7.2 场景总表

| `SW[6:3]` | 场景 | 必须观察的结果 |
| --- | --- | --- |
| `0` | 综合循环 | PC/指令持续流动；LD5、LD6、LD9 最终可锁存 |
| `1` | 数据前递 | 结果格式 `hhhh0008`，低 16 位固定为 `0008` |
| `2` | Load-use | LD5 点亮，结果固定为 `0000000D` |
| `3` | RV32M | LD6 点亮，结果固定为 `002A0007` |
| `4` | 分支预测 | LD9 点亮，结果包含 branch/mispredict 动态计数 |
| `5` | D-Cache/DDR | LD8 点亮，结果包含 access/hit/miss/replacement |
| `6` | I-Cache 冲突 | LD7 点亮，结果非零并随循环增加 |
| `7` | Timer trap | LD10 点亮，结果为非零中断 tick |
| `8`～`F` | 保留 | 显示 `BAD500xx`，不执行功能测试 |

### 7.3 场景 0：综合循环

该场景混合执行相关 ALU 指令、load-use、除法和交替分支，适合先展示“流水确实在运行”。

操作建议：

1. `SW[6:3]=0000`、`SW7=0`。
2. 慢跑观察 LD0～LD4 和 PC 变化。
3. 暂停后单步，观察某些级因 stall 暂时不变。
4. 运行足够长时间，确认 LD5、LD6、LD9 可以锁存。

结果页显示综合循环最后一次计算结果，该值可能在不同循环分支间变化，因此不作为固定判定值。

### 7.4 场景 1：数据前递

场景执行连续相关 ALU 指令：后一条指令立即使用前一条尚未写回寄存器堆的结果，用于证明 MEM/WB 到 EX 的前递路径。

预期结果格式：

```text
hhhh0008
```

- 低 16 位 `0008` 是确定性计算结果。
- 高 16 位 `hhhh` 是前递计数器快照，会随运行时机变化。
- 第一轮完成时高 16 位可能仍为 0，继续运行后可更新。
- 已确认的一次实板显示为 `00000008`。

场景 1 没有单独占用 LD5～LD10，判定以结果低 16 位和正常模式 `SW[3:0]=E` 的前递计数为主。

### 7.5 场景 2：Load-use

场景先执行 `lw`，下一条指令立即使用加载结果，CPU 必须插入 load-use stall。

预期：

- LD5 点亮并保持。
- 结果固定为：

```text
0000000D
```

该结果来自加载值 8 后执行加 5。此结果和 LD5 必须同时满足。该显示已通过实板确认。

### 7.6 场景 3：RV32M

场景执行 `mul`、`div` 和 `rem`，其中多周期除法会暂停 EX 流水级。

预期：

- LD6 点亮并保持。
- 结果固定为：

```text
002A0007
```

高 16 位 `002A` 是 `7 * 6 = 42`，低 16 位 `0007` 是 `42 / 6 = 7`。

### 7.7 场景 4：分支预测

场景使用交替结果的条件分支，使预测器持续工作并产生可见的错误预测冲刷。

预期：

- LD9 点亮并保持，证明至少发生过一次 branch flush。
- 结果格式为：

```text
BBBBMMMM
```

- `BBBB`：branch 计数低 16 位。
- `MMMM`：mispredict 计数低 16 位。
- 两者会随运行时间增加，不要求固定数值。
- 正常情况下 branch 非零，mispredict 小于或等于 branch。

### 7.8 场景 5：D-Cache/DDR

场景执行一组确定性的 DDR 读写和 D-Cache 访问，用于展示 Cache miss、refill 和 DDR 等待。完整的同组地址及 LRU replacement 正确性由正常模式 `accept` 中的 `DCACHE LRU` 自测负责验证。

预期：

- LD8 点亮并保持，证明出现 D-Cache/DDR 等待。
- 结果格式为：

```text
AAHHMMRR
```

| 字节 | 含义 |
| --- | --- |
| `AA` | access 计数低 8 位 |
| `HH` | hit 计数低 8 位 |
| `MM` | miss 计数低 8 位 |
| `RR` | replacement 计数低 8 位 |

验收时要求 access 和 miss 非零，且 `hit + miss` 与 access 的关系合理。replacement 允许为 0；是否完成 LRU replacement 验证应以正常模式的 `[PASS] DCACHE LRU` 为准。数值按 8-bit 截断显示，因此长时间运行后的回绕不表示 Cache 失败。

### 7.9 场景 6：I-Cache 冲突

场景在 Boot ROM 的 `0x3000` 和 `0x3400` 两个同 index 代码块之间反复跳转，稳定触发 I-Cache refill。

预期：

- LD7 点亮并保持。
- 结果为非零跳转次数。
- 持续运行时结果继续增加。
- PC 页可观察到 `000030xx` 和 `000034xx` 地址区域交替出现。

### 7.10 场景 7：Timer trap

场景配置短周期 Timer，打开机器态中断，等待 trap handler 更新 tick 后通过 `mret` 返回。

预期：

- LD10 点亮并保持，证明发生 trap flush。
- 结果为非零 Timer tick。
- 场景完成一轮后会关闭中断，再返回场景分派器，避免影响其他场景。

### 7.11 保留场景 8～F

保留场景不运行功能测试，结果页显示：

```text
BAD500xx
```

其中 `xx` 包含所选场景编号。该显示用于证明非法/保留场景分派有效，不表示硬件验收失败。

## 8. 快速答辩演示版本

时间有限时，可按以下 5～8 分钟顺序演示：

1. 正常模式启动，展示 Boot 自检和 `rv32>`。
2. 执行 `accept`，展示 `ACCEPT_STATUS=FFFF` 和 `ACCEPTANCE PASS`。
3. 展示 16 个 LED 全亮及 `ACCE5500`。
4. 展示 ALU CPI、MIPS、D-Cache 命中率和分支预测准确率。
5. 切换流水模式，展示慢跑、暂停、单步和 IF～WB PC/指令。
6. 场景 2 展示 LD5 与 `0000000D`。
7. 场景 3 展示 LD6 与 `002A0007`。
8. 场景 4～7 依次展示 LD9、LD8、LD7、LD10。
9. 切回正常模式，展示 `rv32>` 恢复。

讲解时建议先说明可观察现象，再说明内部机制。例如先指出“LD5 已锁存且流水暂时不推进”，再解释这是 `lw` 数据尚未可用导致的 load-use stall。

## 9. 常见问题和排查

### 9.1 切换 SW15 后模式没有变化

原因：`SW15` 是复位锁存的模式选择。

处理：设置好 `SW15` 后按 `btnC`，等待复位结束。LD15 亮表示流水模式；UART 出现 Boot/Shell 表示正常模式。

### 9.2 场景切换后仍显示上一场景结果

原因：场景只在程序循环边界重新读取开关，新场景尚未完成第一轮。

处理：保持运行更长时间。看到目标事件 LED 后再暂停并查看结果页。

### 9.3 目标事件 LED 没有立即点亮

原因可能包括：

- CPU 仍处于暂停状态，LD11 亮而 LD12 灭。
- 慢跑速度下尚未执行到目标指令。
- 刚切换场景，旧锁存已清零但新事件尚未发生。

处理：按 `btnU` 确认 LD12 亮，必要时按 `btnD` 切换速度并继续运行。LD5～LD10 一旦触发就会锁存，不需要捕捉单周期闪烁。

### 9.4 切换场景后旧事件 LED 熄灭

这是预期行为。场景切换会清除 LD5～LD10 的旧锁存，以保证当前亮起的 LED 只属于新场景。

### 9.5 流水模式没有 UART Shell

这是预期行为。流水模式直接进入专用演示程序，不执行正常 Boot Shell。需要 Shell 时将 `SW15` 置 0 并按 `btnC`。

### 9.6 D-Cache 场景启动较慢

D-Cache 场景需要等待 MIG 完成 DDR 校准，然后才执行同组地址访问。不要在刚复位后立刻判定失败，应等待 LD8 和结果页更新。

### 9.7 动态计数与文档示例不同

cycle、retired、branch、mispredict、Cache 和场景计数依赖运行时间，部分场景还只显示计数器低 8 位或低 16 位。验收应检查：

- 固定结果字段是否正确。
- 目标事件 LED 是否点亮。
- 动态计数是否非零、能变化且关系合理。
- UART 最终状态是否为 `FFFF` 和 `PASS`。

不要要求动态计数与某次截图逐字符一致。

### 9.8 数码管显示全 0

流水模式刚复位时 CPU 初始暂停，场景尚未写入结果，显示 0 属于正常现象。按 `btnU` 运行，等待场景完成后再查看结果页。

## 10. 验收证据清单

建议按以下清单保存截图、照片或视频，便于课程报告和现场复核：

- [ ] Vivado 下载日志，包含 `BUPT_RISCV_PROGRAMMED=xc7a100t_0`。
- [ ] 正常 Boot 输出和 `rv32>`。
- [ ] `accept` 完整 UART 输出。
- [ ] `ACCEPT_STATUS=FFFF` 和 `ACCEPTANCE PASS`。
- [ ] 16 个 LED 全亮照片。
- [ ] `SW[3:0]=0`、数码管 `ACCE5500` 照片。
- [ ] ALU CPI、MIPS、D-Cache 命中率、分支预测准确率和 I-Cache 命中率页面。
- [ ] 场景 1 的 `hhhh0008` 结果。
- [ ] 场景 2 的 LD5 和 `0000000D`。
- [ ] 场景 3 的 LD6 和 `002A0007`。
- [ ] 场景 4 的 LD9 和 branch/mispredict 结果。
- [ ] 场景 5 的 LD8 和 D-Cache 统计结果。
- [ ] 场景 6 的 LD7 和非零跳转计数。
- [ ] 场景 7 的 LD10 和非零 Timer tick。
- [ ] PC/指令页、五级选择、暂停、运行、单步和速度切换视频。
- [ ] 切回 `SW15=0` 后 Shell 恢复的 UART 截图。
- [ ] bitstream SHA-256、timing、utilization 和 power 报告。

## 11. 最终通过判据

只有同时满足以下条件，才将加强版实板验收记录为通过：

1. bitstream 成功下载到 `xc7a100t_0`。
2. 正常模式 Boot、自检和 UART Shell 正常。
3. `accept` 输出全部 `[PASS]`、`ACCEPT_STATUS=FFFF` 和 `ACCEPTANCE PASS`。
4. 16 个 LED 全亮，数码管可展示 `ACCE5500` 和各项指标。
5. 流水模式的运行、暂停、单步、速度、PC/指令页均正常。
6. 场景 1～7 的固定结果、动态结果和目标事件 LED 符合本文说明。
7. 从流水模式切回正常模式后，UART Shell 能再次恢复。
8. 最终实现满足 100 MHz 时序要求，并保存构建和实板证据。
