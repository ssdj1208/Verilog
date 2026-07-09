# 项目完成度分析

## 1. 总体结论

本项目已经可以作为北京邮电大学《项目式课程阶段二》题目 B 的 RISC-V CPU 方向提交基础。它在 NEXYS4 DDR 平台上实现了一个独立的 RV32I 五级流水 CPU SoC，并配套提供 boot 程序、仿真脚本、综合脚本、下载脚本、MMIO 外设、性能计数器和拓展功能。

当前状态：

```text
行为级仿真：脚本已准备
综合/实现/bitstream：Vivado 2023.2 已通过，已生成 build/bupt_riscv_top.bit
时序目标：满足 100 MHz
实物上板证据：需要学生在 NEXYS4 DDR 上补充截图、照片或视频
```

也就是说，RTL、工程脚本和 bitstream 构建已经基本完成。后续课程交付重点是收集上板验证证据，并在报告中补充波形、串口输出、PPA 分析和性能计数数据。

## 2. 课程要求覆盖矩阵

| 课程要求 | 当前状态 | 说明 |
| --- | --- | --- |
| RV32I 或自定义 ISA CPU | 已完成 | 本项目采用 RV32I 课程子集，不再沿用原始 MIPS ISA。 |
| 基本算术逻辑指令 | 已完成 | 支持 `add/sub/sll/slt/sltu/xor/srl/sra/or/and` 以及 I 型 ALU 指令。 |
| 基本访存指令 | 已完成 | 支持 `lb/lh/lw/lbu/lhu` 和 `sb/sh/sw`，包含字节使能和符号扩展。 |
| 分支跳转指令 | 已完成 | 支持 `beq/bne/blt/bge/bltu/bgeu`、`jal`、`jalr`。 |
| 五级流水线 | 已完成 | 实现 IF、ID、EX、MEM、WB 五级流水寄存器和控制流。 |
| 数据冒险处理 | 已完成 | 实现 EX/MEM/WB 前递和 load-use 暂停。 |
| 控制冒险处理 | 已完成 | 实现分支预测、EX 阶段解析和错误路径 flush。 |
| 内存和 I/O 集成 | 已完成 | 集成 Boot ROM、BRAM、UART、GPIO、Timer、DDR Bridge、性能计数 MMIO。 |
| 性能计数器 | 已完成 | 支持 cycle、retired instruction、branch、mispredict、stall 计数。 |
| Vivado 仿真脚本 | 已完成 | `scripts/sim_bupt_riscv.tcl`。 |
| Vivado 构建脚本 | 已完成 | `scripts/build_bupt_riscv.tcl`，已生成工程和 bitstream。 |
| NEXYS4 DDR 下载脚本 | 已完成 | `scripts/program_bupt_riscv.tcl`。 |
| 实物硬件验证 | 待补证据 | 需要下载板卡后保存串口截图、LED 照片或视频。 |

## 3. RV32I 指令完成度

已实现的 RV32I 课程子集：

```text
lui, auipc
jal, jalr
beq, bne, blt, bge, bltu, bgeu
addi, slti, sltiu, xori, ori, andi
slli, srli, srai
add, sub, sll, slt, sltu, xor, srl, sra, or, and
lb, lh, lw, lbu, lhu
sb, sh, sw
```

关键正确性点：

- 寄存器 `x0` 恒为 0。
- I/S/B/U/J 五类立即数按 RISC-V 格式生成。
- 分支目标为 `PC + imm`。
- `jal` 写回 `PC + 4`。
- `jalr` 目标地址最低位清零。
- 有符号和无符号比较分开处理。
- load 指令支持 byte/halfword 的符号扩展和零扩展。

## 4. 流水线和冒险处理完成度

已经实现：

- IF 阶段取指和分支预测。
- ID 阶段译码、寄存器读取、立即数生成。
- EX 阶段 ALU 执行、分支/跳转解析、目标地址生成。
- MEM 阶段数据总线访问。
- WB 阶段寄存器写回。
- EX/MEM/WB 到 EX 的数据前递。
- load-use hazard 暂停。
- DDR 或慢速 MMIO `d_ready=0` 时冻结流水线。
- 分支、跳转、`jalr` 预测错误时 flush 错误路径。

这部分正好对应答辩中常问的问题：为什么需要前递、哪些情况必须暂停、分支预测错误后如何恢复正确 PC。

## 5. 拓展功能完成度

### 5.1 分支预测

状态：已完成。

实现方式：

- 64 项直接映射 BTB/BHT。
- BTB 保存预测目标地址。
- BHT 使用 2 位饱和计数器。
- IF 阶段给出预测。
- EX 阶段解析真实结果并更新预测器。
- 错误预测次数通过性能计数器输出。

### 5.2 Cache 替换策略

状态：已完成。

实现文件：

```text
src/bupt_riscv/dcache_2way_lru.v
```

设计要点：

- 16 组。
- 2 路组相联。
- 每行 1 个 word。
- LRU victim 选择。
- write-through 写策略。
- 支持 accesses、hits、misses、replacements 统计。
- MMIO 地址区域：`0x1000_6000`。

这一部分可以作为课程拓展方向“Cache 替换策略优化与命中率分析”的支撑内容。报告中可以结合 `cache` shell 命令输出讨论命中率和替换次数。

### 5.3 RV32M 乘除法扩展

状态：已完成。

支持指令：

```text
mul, mulh, mulhsu, mulhu, div, divu, rem, remu
```

ALU 中包含 RISC-V 对除零和有符号溢出的特殊结果处理。Boot 自测通过后会输出：

```text
M EXT PASS
```

### 5.4 FP32 浮点协处理器

状态：已完成 MMIO 形式的浮点协处理器，但不是完整 RISC-V F 扩展。

实现文件：

```text
src/bupt_riscv/fp_mmio.v
```

设计要点：

- 通过 MMIO 访问，不增加独立浮点寄存器堆。
- 支持 FP32 加法演示路径。
- 支持 FP32 乘法演示路径。
- MMIO 地址区域：`0x1000_7000`。
- Boot 自测通过后会输出：

```text
FP TEST OK
```

答辩和报告中建议表述为“内存映射浮点协处理器”，不要说成完整 RISC-V F 扩展，因为完整 F 扩展还涉及浮点寄存器堆、舍入模式、异常标志和更多指令。

## 6. 验证状态

行为级仿真成功标志：

```text
Simulation succeeded: BUPT RISC-V CPU verified
BUPT_RISCV_SIM_DONE
```

boot 和 testbench 检查的输出包括：

```text
BUPT RISC-V CPU PROJECT
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
```

当前 Vivado 2023.2 实现结果：

| 指标 | 结果 |
| --- | ---: |
| WNS | 1.316 ns |
| TNS | 0.000 ns |
| 主 100 MHz 时钟 WNS | 6.688 ns |
| LUT | 14153 / 63400，22.32% |
| Register | 12313 / 126800，9.71% |
| BRAM Tile | 5 / 135，3.70% |
| DSP | 14 / 240，5.83% |
| 估计功耗 | 1.707 W |

结论：当前实现满足 100 MHz 时序，资源占用仍有较大余量。

## 7. 最终答辩前仍需补充的内容

RTL 和脚本已经完成，答辩前建议补充以下材料：

- Vivado 仿真成功截图。
- Timing summary 截图。
- Utilization summary 截图。
- NEXYS4 DDR 下载后的串口输出截图。
- `led 1` 点亮 LED 的照片或视频。
- `perf` 命令输出，并计算 `CPI = cycles / retired instructions`。
- 一段 PPA 权衡分析，说明前递网络、分支预测、Cache、RV32M、FP MMIO 对面积、性能和功耗的影响。

## 8. 答辩建议说法

- 本项目已经从原始 MIPS 思路改造为 RV32I 指令集。
- CPU 不是单周期演示，而是 IF/ID/EX/MEM/WB 五级流水结构。
- 大多数 ALU 相关冒险通过前递解决。
- load-use 冒险仍然需要暂停，因为 load 数据要到 MEM 阶段后才可用。
- 分支预测可以降低控制冒险代价，但需要 BTB/BHT 资源，并且预测错误时必须 flush。
- Cache 使用 LRU 替换，便于解释、验证和统计命中率。
- 浮点部分采用 MMIO 协处理器形式，降低完整 F 扩展带来的复杂度，适合课程项目规模。

