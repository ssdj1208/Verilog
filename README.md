# 北邮项目式课程阶段二题目 B：RISC-V CPU 项目

本目录是面向北京邮电大学《项目式课程阶段二》题目 B 的独立交付版本，目标是在 NEXYS4 DDR 板卡上实现一个基于 **RV32I 课程子集** 的五级流水 CPU SoC。当前工程已使用 Vivado 2023.2 完成仿真、综合、实现、bitstream 生成和 NEXYS4 DDR 上板串口验证；仓库根目录中的旧实验目录和课程资料仅作参考，当前有效工程入口是 `Verilog/`。

## 一、文档入口

- 详细使用说明：[docs/USAGE_GUIDE.md](docs/USAGE_GUIDE.md)
- 项目完成度分析：[docs/PROJECT_COMPLETION_ANALYSIS.md](docs/PROJECT_COMPLETION_ANALYSIS.md)
- Vivado 构建与 PPA 摘要：[docs/bupt_riscv_build_summary.md](docs/bupt_riscv_build_summary.md)
- 原始详细使用记录：[BUPT_RISCV_USAGE.md](BUPT_RISCV_USAGE.md)
- 原始题目符合性审查：[BUPT_PROJECT_B_AUDIT.md](BUPT_PROJECT_B_AUDIT.md)

## 二、目录结构

```text
src/bupt_riscv/                  RISC-V SoC、总线、内存、外设、DDR 桥接
src/bupt_riscv/riscv_core/       RV32I 五级流水 CPU 核
src/common/                      通用 UART 收发模块
software/bupt_riscv/             Boot ROM 生成脚本和指令 listing
sim/bupt_riscv_tb.v              Vivado 行为级仿真 testbench
scripts/sim_bupt_riscv.tcl       Vivado 仿真脚本
scripts/build_bupt_riscv.tcl     Vivado 综合、实现、bitstream 生成脚本
scripts/program_bupt_riscv.tcl   NEXYS4 DDR 下载脚本
constr/nexys4ddr_bupt_riscv.xdc  NEXYS4 DDR 引脚约束
docs/                            使用说明、完成度分析、构建摘要
```

## 三、已经实现的功能

- RV32I 课程子集：算术、逻辑、访存、分支、跳转、`lui`、`auipc`。
- 五级流水线：IF、ID、EX、MEM、WB。
- 冒险处理：EX/MEM/WB 前递、load-use 暂停、慢速内存等待暂停、错误路径 flush。
- 分支预测：64 项直接映射 BTB/BHT，2 位饱和计数器。
- SoC 外设：Boot ROM、BRAM、UART、GPIO、Timer、DDR Bridge、性能计数 MMIO。
- 拓展功能：2 路组相联 LRU D-Cache、RV32M 乘除法、FP32 MMIO 浮点协处理器。
- Boot 自测和串口 shell：`help`、`mem`、`cache`、`fp`、`perf`、`led 1`、`run demo`。

## 四、快速开始

本项目当前验证使用的 Vivado 路径为：

```powershell
D:\Xilinx\Vivado\2023.2\settings64.bat
```

如果你的 Vivado 安装路径不同，请把下面命令中的路径替换成自己的实际路径。

生成 RISC-V boot ROM：

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

运行行为级仿真：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\sim_bupt_riscv.tcl"
```

生成 bitstream：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\build_bupt_riscv.tcl"
```

下载到 NEXYS4 DDR：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\program_bupt_riscv.tcl"
```

串口设置：

```text
波特率：115200
格式：8N1
流控：无
```

预期启动输出：

```text
BUPT RISC-V CPU PROJECT
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
```

## 五、当前完成状态

当前 RTL、boot 程序、仿真脚本和综合脚本已经形成可独立构建的目录结构。2026-07-09 clean-name rebuild 已运行 `scripts/build_bupt_riscv.tcl` 并生成 `build/bupt_riscv_top.bit`，实现后时序满足 100 MHz 约束；2026-07-08 `build19` 已记录 NEXYS4 DDR 上板串口验证和 benchmark/perf 输出。课程报告中建议整理串口输出截图、LED 点亮照片或视频、`perf` 命令输出和 CPI 计算。

