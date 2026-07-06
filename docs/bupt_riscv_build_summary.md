# BUPT RISC-V Vivado 构建摘要

生成时间：2026-07-06 19:09  
工具版本：Vivado 2025.2  
目标器件：xc7a100tcsg324-1  
目标板卡：NEXYS4 DDR  
bitstream：`build/bupt_riscv_top.bit`

## 构建结果

Vivado 实现流程已经完成到 `write_bitstream`，日志中的成功标志为：

```text
INFO: [Vivado 12-1842] Bitgen Completed Successfully.
BUPT_RISCV_BITSTREAM=D:/project/step_into_mips/build/bupt_riscv_top.bit
```

## 时序摘要

约束主时钟：

```text
sys_clk_pin: 10.000 ns, 100.000 MHz
```

全设计时序：

| 指标 | 数值 |
| --- | ---: |
| WNS | 1.316 ns |
| TNS | 0.000 ns |
| Setup failing endpoints | 0 |
| WHS | 0.049 ns |
| THS | 0.000 ns |
| Hold failing endpoints | 0 |

主 100 MHz 时钟域：

| 指标 | 数值 |
| --- | ---: |
| WNS | 6.688 ns |
| TNS | 0.000 ns |
| WHS | 0.265 ns |
| THS | 0.000 ns |

结论：实现后时序满足 100 MHz 约束。

## 资源占用

| 资源 | 使用量 | 总量 | 占比 |
| --- | ---: | ---: | ---: |
| Slice LUTs | 14279 | 63400 | 22.52% |
| Slice Registers | 12305 | 126800 | 9.70% |
| Block RAM Tile | 5 | 135 | 3.70% |
| DSPs | 14 | 240 | 5.83% |
| BUFGCTRL | 5 | 32 | 15.63% |

## 功耗估计

| 指标 | 数值 |
| --- | ---: |
| Total On-Chip Power | 1.826 W |
| Dynamic Power | 1.715 W |
| Device Static Power | 0.111 W |
| Junction Temperature | 33.3 C |

注意：Vivado 报告中的 power confidence 为 Low，课程报告中应说明该功耗来自默认向量不足条件下的估算，适合作为 PPA 讨论依据，不适合作为精确实测功耗。

## PPA 说明建议

- 性能：五级流水线提升吞吐量，分支预测降低控制冒险带来的错误取指开销，2 路 LRU D-Cache 降低重复 DDR 读取开销，RV32M 与 FP32 协处理器提高计算能力。
- 面积：前递网络、BTB/BHT、D-Cache、RV32M 乘除法、FP32 MMIO 协处理器和性能计数器会增加 LUT、寄存器和 DSP 使用。当前 LUT 占比约 22.52%，寄存器占比约 9.70%，DSP 占比约 5.83%，资源余量仍充足。
- 功耗：动态功耗估计约 1.715 W，主要受 DDR/MIG、时钟网络、乘法/DSP、浮点乘法和流水线寄存器切换影响。
- 取舍：Cache 采用 16 组 2 路、1 word line、write-through 的 LRU 设计，换取实现简单、可验证、不会破坏 DDR 一致性；浮点采用 MMIO 协处理器而非完整 RISC-V F 扩展，避免独立浮点寄存器堆和异常状态带来的复杂度。
