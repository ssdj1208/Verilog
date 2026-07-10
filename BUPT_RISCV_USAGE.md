# BUPT RISC-V CPU 项目使用说明

本文档说明如何使用本仓库中的北邮题目 B 改造项目：`bupt_riscv`。该项目源自早期教学 SoC 外壳，当前已整理为独立的 BUPT RISC-V 工程，包含 RV32I 课程子集五级流水 CPU、分支预测、性能计数器、RISC-V boot 程序和 Vivado 脚本。

## 1. 项目内容

核心目录如下：

```text
src/bupt_riscv/                  RISC-V SoC 顶层、总线、外设、DDR 桥接
src/bupt_riscv/riscv_core/       RV32I 五级流水 CPU 核
src/common/                      通用 UART 收发模块
software/bupt_riscv/             RISC-V boot ROM 生成器和 listing
sim/bupt_riscv_tb.v              行为级仿真 testbench
scripts/sim_bupt_riscv.tcl       Vivado 仿真脚本
scripts/build_bupt_riscv.tcl     Vivado 综合/实现/bitstream 脚本
scripts/program_bupt_riscv.tcl   NEXYS4 下载脚本
constr/nexys4ddr_bupt_riscv.xdc  NEXYS4 约束文件
tools/riscv_instruction_builder.py  Boot ROM 图形化指令构造器
```

主要能力：

- RV32I 课程子集指令。
- IF/ID/EX/MEM/WB 五级流水。
- 数据前递、load-use 暂停、DDR wait-state 暂停。
- 64 项 BTB/BHT 分支预测器。
- 16 组 2 路、4-word line LRU D-Cache，带 hit/miss/replacement/refill 统计。
- RV32M 乘除法扩展：`mul/mulh/mulhsu/mulhu/div/divu/rem/remu`。
- FP32 MMIO 浮点协处理器，支持正规格化单精度加法和乘法演示。
- GPIO、UART、DDR status/data、performance counter MMIO。
- RISC-V boot ROM 自测和串口 shell。
- NEXYS4 DDR 五级流水演示模式，支持暂停、单步、变速和 PC/指令显示。

## 2. 环境要求

本项目已按以下环境验证：

```text
Vivado 2023.2
Windows PowerShell
NEXYS4 DDR / Artix-7 xc7a100tcsg324-1
```

你的 Vivado 路径为：

```text
D:\Xilinx\Vivado\2023.2\settings64.bat
```

如果以后换机器，先检查路径是否存在：

```powershell
Test-Path "D:\Xilinx\Vivado\2023.2\settings64.bat"
```

## 3. 每次运行前的准备

进入项目目录：

```powershell
cd D:\CodeProject\Verilog_Project\COCP\Verilog
```

生成 RISC-V boot ROM：

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

成功后会生成：

```text
src/bupt_riscv/bupt_riscv_boot.mem
software/bupt_riscv/gen_bupt_boot.lst
```

其中：

- `.mem` 是 boot ROM 初始化文件，Vivado 仿真和综合会使用它。
- `.lst` 是机器码 listing，答辩时可用于说明 RISC-V 程序执行流程。

## 4. 行为级仿真

运行：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\sim_bupt_riscv.tcl"
```

成功标志：

```text
Simulation succeeded: BUPT RISC-V CPU verified
BUPT_RISCV_SIM_DONE
```

该仿真会检查：

- UART boot banner。
- RV32I ISA 自测。
- DDR pattern test。
- `help`、`mem`、`led 1`、`run demo`、`perf` shell 命令。
- LED MMIO 是否被成功写入。
- performance counter 是否能输出十六进制计数值。

## 5. 生成 bitstream

运行：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\build_bupt_riscv.tcl"
```

成功标志：

```text
BUPT_RISCV_BITSTREAM=<repo>/build/bupt_riscv_top.bit
```

生成的 bitstream 文件：

```text
build/bupt_riscv_top.bit
```

如果脚本中断，优先查看终端最靠前的 `ERROR`。常见原因：

- Vivado 未正确加载环境。
- `bupt_riscv_boot.mem` 未生成。
- MIG IP 生成失败。
- 时序实现失败。

## 6. 下载到 NEXYS4

连接 NEXYS4，打开电源，确认 JTAG 可用后运行：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\program_bupt_riscv.tcl"
```

成功标志：

```text
BUPT_RISCV_PROGRAMMED=xc7a100t_0 BITSTREAM=<repo>/build/bupt_riscv_top.bit
```

## 7. 串口验收

串口参数：

```text
115200 8N1
```

复位板子后预期输出：

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

可输入命令：

```text
help
mem
cache
fp
led 1
run demo
perf
```

预期行为：

- `help` 输出命令列表。
- `mem` 再次执行 DDR 测试，输出 `DDR TEST OK`。
- `cache` 再次执行 Cache/LRU 测试，输出 `CACHE READY`。
- `fp` 再次执行 FP32 协处理器测试，输出 `FP TEST OK`。
- `led 1` 点亮 LED0，并输出 `OK`。
- `run demo` 运行分支密集小循环，输出 `demo started`。
- `perf` 输出 cycle、retired、branch、mispredict、stall 等计数器。

## 8. 重要源码说明

CPU 核入口：

```text
src/bupt_riscv/riscv_core/riscv.v
```

关键模块：

```text
alu.v                 RV32I ALU
immgen.v              I/S/B/U/J 立即数生成
load_ext.v            lb/lh/lw/lbu/lhu 符号或零扩展
store_align.v         sb/sh/sw 写数据和 byte strobe
branch_predictor.v    64 项 BTB/BHT 分支预测器
```

SoC 入口：

```text
src/bupt_riscv/soc.v
src/bupt_riscv/simple_bus.v
src/bupt_riscv/top.v
```

boot 程序生成器：

```text
software/bupt_riscv/gen_bupt_boot.py
```

## 9. MMIO 地址空间

当前软件使用的主要地址：

```text
0x0000_0000 - 0x0000_3fff    boot ROM
0x0001_0000 - 0x0001_ffff    BRAM RAM / stack
0x1000_0000 - 0x1000_00ff    GPIO / LED
0x1000_1000 - 0x1000_10ff    UART
0x1000_4000 - 0x1000_40ff    DDR status
0x1000_5000 - 0x1000_50ff    performance counters
0x8000_0000 - 0x87ff_ffff    DDR data window
```

performance counter：

```text
0x1000_5000    cycles
0x1000_5004    retired instructions
0x1000_5008    branches
0x1000_500c    branch mispredicts
0x1000_5010    stalls
0x1000_501c    write 1 to clear counters
```

## 10. 常见问题

### 找不到 vivado

确认路径：

```powershell
Test-Path "D:\Xilinx\Vivado\2023.2\settings64.bat"
```

如果返回 `False`，需要改成你实际的 Vivado 安装路径。

### 仿真提示 boot ROM 文件找不到

先运行：

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

再运行仿真。

### 仿真 timeout

先看日志最后几行：

```powershell
Get-Content build\bupt_riscv_sim\vivado\bupt_riscv_sim.sim\sim_1\behav\xsim\simulate.log -Tail 50
```

如果出现 `Simulation Failed`，重点看失败前的 expected/got 字节或 timeout debug 信息。

### 生成 bitstream 很慢

正常。脚本会生成 MIG IP、综合、实现、写 bitstream，可能需要数分钟到十几分钟。

### 上板没有串口输出

检查：

- 串口波特率是否为 `115200 8N1`。
- 是否选中了正确 COM 口。
- 板子是否已经下载 bitstream。
- 下载后是否按了复位。
- USB-UART 线和驱动是否正常。

## 11. 清理说明

仓库中的 Vivado 临时产物可删除，会自动重新生成：

```text
.Xil/
build/bupt_riscv_sim/
build/bupt_riscv_vivado/
vivado*.log
vivado*.jou
dfx_runtime.txt
```

建议保留：

```text
src/bupt_riscv/
software/bupt_riscv/
sim/bupt_riscv_tb.v
scripts/*bupt_riscv*.tcl
constr/nexys4ddr_bupt_riscv.xdc
build/bupt_riscv_top.bit
BUPT_RISCV_USAGE.md
```

## 12. 提交/答辩建议

答辩时建议重点讲：

- 为什么选择 RV32I 课程子集。
- 五级流水线 IF/ID/EX/MEM/WB 如何划分。
- load-use hazard、数据前递、DDR wait-state 如何处理。
- 分支预测器 BTB/BHT 的结构和更新时机。
- `perf` 命令如何量化 cycle、retired、branch、mispredict、stall。
- UART/LED/DDR 如何证明这是完整计算机系统而不只是 CPU 核。

演示顺序建议：

```text
1. 运行 sim_bupt_riscv.tcl，展示仿真通过。
2. 上板复位，展示启动 banner。
3. 输入 help。
4. 输入 mem，展示 DDR TEST OK。
5. 输入 led 1，展示 LED0 点亮。
6. 输入 run demo。
7. 输入 perf，展示性能计数器。
```
