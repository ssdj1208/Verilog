# BUPT RISC-V Vivado 构建摘要

生成时间：2026-07-10 22:11  
工具版本：Vivado 2023.2  
目标器件：xc7a100tcsg324-1  
目标板卡：NEXYS4 DDR  
构建目录：`build/bupt_riscv_vivado_acceptance/`  
bitstream：`build/bupt_riscv_top.bit`

## 构建结果

Vivado 实现流程已经完成到 `write_bitstream`，日志中的成功标志为：

```text
INFO: [Vivado 12-1842] Bitgen Completed Successfully.
BUPT_RISCV_BITSTREAM=D:/CodeProject/Verilog_Project/COCP/Verilog/build/bupt_riscv_top.bit
```

## 时序摘要

约束主时钟：

```text
sys_clk_pin: 10.000 ns, 100.000 MHz
```

全设计时序：

| 指标 | 数值 |
| --- | ---: |
| WNS | 0.055 ns |
| TNS | 0.000 ns |
| Setup failing endpoints | 0 |
| WHS | 0.020 ns |
| THS | 0.000 ns |
| Hold failing endpoints | 0 |

SoC/CPU 100 MHz 时钟域：

| 指标 | 数值 |
| --- | ---: |
| WNS | 0.055 ns |
| TNS | 0.000 ns |
| WHS | 0.027 ns |
| THS | 0.000 ns |

结论：实现后时序满足 100 MHz 约束。

## 资源占用

| 资源 | 使用量 | 总量 | 占比 |
| --- | ---: | ---: | ---: |
| Slice LUTs | 17974 | 63400 | 28.35% |
| Slice Registers | 31413 | 126800 | 24.77% |
| Block RAM Tile | 5 | 135 | 3.70% |
| DSPs | 2 | 240 | 0.83% |
| BUFGCTRL | 5 | 32 | 15.63% |

## 功耗估计

| 指标 | 数值 |
| --- | ---: |
| Total On-Chip Power | 1.185 W |
| Dynamic Power | 1.077 W |
| Device Static Power | 0.108 W |
| Junction Temperature | 30.4 C |

注意：Vivado 报告中的 power confidence 为 Low，课程报告中应说明该功耗来自默认向量不足条件下的估算，适合作为 PPA 讨论依据，不适合作为精确实测功耗。

## PPA 说明建议

- 性能：五级流水线提升吞吐量，分支预测降低控制冒险带来的错误取指开销，2 路 LRU D-Cache 降低重复 DDR 读取开销，RV32M 与 FP32 协处理器提高计算能力。
- 面积：前递网络、BTB/BHT、I-Cache、D-Cache、RV32M、FP32、验收状态寄存器和数码管面板会增加 LUT、寄存器和 DSP 使用。本次最终构建的 LUT 占比约 28.35%，寄存器占比约 24.77%，DSP 占比约 0.83%，资源余量仍充足。
- 功耗：动态功耗估计约 1.077 W，主要受 DDR/MIG、时钟网络、乘法/DSP、浮点乘法和流水线寄存器切换影响。
- 取舍：D-Cache 采用 16 组 2 路、4-word line、write-through 的 LRU 设计，换取实现简单、可验证、不会破坏 DDR 一致性；浮点采用 MMIO 协处理器而非完整 RISC-V F 扩展，避免独立浮点寄存器堆和异常状态带来的复杂度。
