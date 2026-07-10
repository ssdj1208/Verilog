# BUPT RISC-V 项目使用说明

本文档说明如何在 Windows + Vivado 环境下使用本项目，包括生成 boot ROM、运行仿真、综合实现、下载板卡和串口验收。

## 1. 环境要求

已验证环境：

```text
板卡：NEXYS4 DDR / Artix-7 xc7a100tcsg324-1
工具：Vivado 2023.2
系统：Windows PowerShell
串口：115200 8N1
```

本机 Vivado 路径：

```powershell
D:\Xilinx\Vivado\2023.2\settings64.bat
```

如果你换了电脑或 Vivado 安装位置不同，请先检查路径：

```powershell
Test-Path "D:\Xilinx\Vivado\2023.2\settings64.bat"
```

如果返回 `False`，需要把后续命令中的 Vivado 路径替换成你的实际安装路径。

## 2. 项目目录说明

```text
src/bupt_riscv/top.v              FPGA 顶层模块
src/bupt_riscv/soc.v              SoC 集成模块
src/bupt_riscv/simple_bus.v       地址译码和 MMIO 总线
src/bupt_riscv/riscv_core/        五级流水 RV32I CPU 核
src/bupt_riscv/dcache_2way_lru.v  2 路 LRU D-Cache
src/bupt_riscv/fp_mmio.v          FP32 MMIO 浮点协处理器
src/common/                       通用 UART 收发模块
software/bupt_riscv/              Boot 镜像生成脚本
sim/bupt_riscv_tb.v               仿真 testbench
scripts/                          Vivado batch 脚本
constr/                           NEXYS4 DDR 约束文件
docs/                             项目文档
```

## 3. 生成 Boot ROM

在仓库根目录执行：

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

成功后会生成：

```text
src/bupt_riscv/bupt_riscv_boot.mem
software/bupt_riscv/gen_bupt_boot.lst
```

其中：

- `bupt_riscv_boot.mem` 用于初始化硬件 boot ROM。
- `gen_bupt_boot.lst` 是生成的 RISC-V 机器码 listing，答辩时可以用于说明启动程序和自测流程。

## 4. 运行行为级仿真

执行：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\sim_bupt_riscv.tcl"
```

仿真成功标志：

```text
Simulation succeeded: BUPT RISC-V CPU verified
BUPT_RISCV_SIM_DONE
```

testbench 会检查以下内容：

- UART 启动 banner。
- RV32I 指令自测。
- RV32M 乘除法自测。
- DDR 读写 pattern 测试。
- Cache 和 FP MMIO 自测。
- shell 命令：`help`、`mem`、`cache`、`fp`、`perf`、`led 1`、`run demo`。
- LED MMIO 写入。
- 性能计数器输出。

## 5. 综合、实现并生成 bitstream

执行：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\build_bupt_riscv.tcl"
```

成功后会生成：

```text
build/bupt_riscv_top.bit
```

当前 Vivado 2023.2 构建结果满足 100 MHz 时序，资源占用和功耗估计见：

```text
docs/bupt_riscv_build_summary.md
```

## 6. 下载到 NEXYS4 DDR

连接 NEXYS4 DDR 板卡 USB 后执行：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\program_bupt_riscv.tcl"
```

然后打开串口工具，参数设置为：

```text
波特率：115200
数据位：8
校验位：无
停止位：1
流控：无
```

预期串口输出：

```text
BUPT RISC-V CPU PROJECT
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
```

可用 shell 命令：

```text
help       打印命令列表
mem        运行内存/DDR 检查
cache      运行 D-Cache/LRU 自测，成功时输出 CACHE READY
fp         运行 FP32 MMIO 演示
perf       打印 cycle、retired、branch、mispredict、stall 计数器
led 1      点亮 LED 输出
run demo   运行综合演示
```

## 7. 常见问题

### 7.1 Vivado 命令找不到

先检查 settings 脚本是否存在：

```powershell
Test-Path "D:\Xilinx\Vivado\2023.2\settings64.bat"
```

如果路径不存在，找到你自己的 Vivado 安装目录后替换命令中的路径。

### 7.2 仿真超时

先重新生成 boot ROM：

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

再重新运行 `scripts\sim_bupt_riscv.tcl`。如果仍然超时，查看 Vivado transcript 中最后打印的 UART 字符或最后一个 testbench 检查点，定位卡在哪个自测阶段。

### 7.3 上板后串口没有输出

依次检查：

- 串口号是否是 NEXYS4 DDR 的 USB-UART 端口。
- 波特率是否为 `115200`。
- FPGA 是否已经下载 `build/bupt_riscv_top.bit`。
- 顶层复位按键和 XDC 中的复位极性是否一致。
- 板卡时钟是否为 NEXYS4 DDR 的 100 MHz 系统时钟。

## 8. 课程验收建议材料

建议最终报告中保存以下证据：

- 仿真 transcript 截图，包含 `BUPT_RISCV_SIM_DONE`。
- Vivado timing summary 截图。
- Vivado utilization summary 截图。
- 下载板卡后的串口启动输出截图。
- `led 1` 点亮 LED 的照片或视频。
- `perf` 命令输出，并计算 CPI：`CPI = cycles / retired instructions`。
- 对分支预测、Cache、RV32M、FP MMIO 的 PPA 权衡说明。

