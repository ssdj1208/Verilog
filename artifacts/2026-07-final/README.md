# 2026-07 最终验证材料

本目录保存 BUPT RISC-V CPU 项目的最终可交付验证证据。源码基线为提交
`2f6daaced9640459831fc96ab4832fc1885af290`（`ssdj` 分支），打包日期为
2026-07-16。

## 环境

- Vivado：2023.2
- FPGA：xc7a100tcsg324-1
- 开发板：NEXYS4 DDR
- 目标时钟：100 MHz（10.000 ns）

## 目录说明

- `bitstream/`：最终验收构建生成的 `bupt_riscv_top.bit`。
- `waves/`：六个行为级仿真的 Vivado WDB 波形数据库。
- `simulation/`：每个 testbench 的独立 `simulate.log` 和 Vivado 批处理输出。
- `implementation/`：最终构建的综合、MIG 综合、实现日志，以及时序、资源、功耗和 DRC 报告。
- `board/`：串口启动、命令、性能测试、下载和实板复测记录。该目录包含开发过程记录，最终结果应结合文件时间和项目文档判断。
- `SHA256SUMS.txt`：本目录所有交付文件的 SHA-256 校验值。

原始 Vivado 缓存、检查点、编译对象和重复构建没有提交。它们可由仓库中的
`scripts/sim_bupt_riscv.tcl` 与 `scripts/build_bupt_riscv.tcl` 重新生成。

## 仿真结果

2026-07-16 使用 `scripts/sim_bupt_riscv.tcl` 分别重跑六个 testbench，均返回成功：

| Testbench | 成功标志 |
| --- | --- |
| `bupt_riscv_acceptance_tb` | `Simulation succeeded: enhanced acceptance UART verified` |
| `bupt_riscv_tb` | `Simulation succeeded: BUPT RISC-V CPU verified` |
| `bupt_riscv_demo_tb` | `Simulation succeeded: pipeline demo stepping verified` |
| `bupt_riscv_scenarios_tb` | `Simulation succeeded: enhanced pipeline scenarios verified` |
| `pipeline_demo_panel_tb` | `Simulation succeeded: pipeline demo panel verified` |
| `acceptance_mmio_tb` | `Simulation succeeded: acceptance MMIO verified` |

## 实现结果

最终实现证据来自
`build/bupt_riscv_vivado_acceptance_final/bupt_riscv.runs/`。实现日志包含
`Bitgen Completed Successfully`。`top_timing_summary_routed.rpt` 显示 100 MHz
约束下 WNS 为 0.055 ns、TNS 为 0.000 ns；详细资源和功耗数据见
`implementation/` 以及 `docs/bupt_riscv_build_summary.md`。

## 使用波形和 bitstream

克隆仓库后先取得 Git LFS 文件：

```powershell
git lfs install
git lfs pull
```

在 Vivado GUI 中选择 `File > Open Waveform Database` 打开 `waves/*.wdb`，或在
Vivado Tcl Console 中运行：

```tcl
open_wave_database artifacts/2026-07-final/waves/bupt_riscv_tb_behav.wdb
```

下载 bitstream 前应确认目标板卡为 NEXYS4 DDR。推荐继续使用
`scripts/program_bupt_riscv.tcl`，以保持器件选择和下载流程一致。
