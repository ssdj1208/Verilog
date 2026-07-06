# BUPT RISC-V CPU Project

This repository contains a standalone Beijing University of Posts and Telecommunications project-course stage 2 topic B CPU design. It is a NEXYS4 DDR based RV32I five-stage pipelined SoC prepared for Vivado 2025.2.

## Quick Links

- Usage guide: [docs/USAGE_GUIDE.md](docs/USAGE_GUIDE.md)
- Project completion analysis: [docs/PROJECT_COMPLETION_ANALYSIS.md](docs/PROJECT_COMPLETION_ANALYSIS.md)
- Vivado build summary: [docs/bupt_riscv_build_summary.md](docs/bupt_riscv_build_summary.md)
- Original detailed usage note: [BUPT_RISCV_USAGE.md](BUPT_RISCV_USAGE.md)
- Original requirement audit note: [BUPT_PROJECT_B_AUDIT.md](BUPT_PROJECT_B_AUDIT.md)

## Repository Layout

```text
src/bupt_riscv/                  RISC-V SoC, bus, memory, peripherals, DDR bridge
src/bupt_riscv/riscv_core/       RV32I pipeline CPU core
software/bupt_riscv/             Boot ROM generator and instruction listing
sim/bupt_riscv_tb.v              Vivado behavioral simulation testbench
scripts/sim_bupt_riscv.tcl       Vivado simulation batch script
scripts/build_bupt_riscv.tcl     Vivado synthesis/implementation/bitstream script
scripts/program_bupt_riscv.tcl   NEXYS4 DDR programming script
constr/nexys4ddr_bupt_riscv.xdc  NEXYS4 DDR constraints
docs/                            Usage, completion analysis, build summary
```

## Implemented Features

- RV32I course subset: arithmetic, logic, load/store, branch, jump, LUI, AUIPC.
- Five-stage pipeline: IF, ID, EX, MEM, WB.
- Hazard handling: EX/MEM/WB forwarding, load-use stall, memory wait stall, control flush.
- 64-entry direct-mapped BTB/BHT branch predictor with 2-bit saturating counters.
- SoC integration: Boot ROM, BRAM, UART, GPIO, timer, DDR bridge, performance MMIO.
- Extension work: 2-way LRU D-cache, RV32M multiply/divide, FP32 MMIO coprocessor.
- Boot self-test and shell: `help`, `mem`, `cache`, `fp`, `perf`, `led 1`, `run demo`.

## Fast Start

Vivado path used during verification:

```powershell
D:\programe_files\vivado\2025.2\Vivado\settings64.bat
```

Generate the boot ROM:

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

Run behavioral simulation:

```powershell
cmd /c ""D:\programe_files\vivado\2025.2\Vivado\settings64.bat" && vivado -mode batch -source scripts\sim_bupt_riscv.tcl"
```

Build bitstream:

```powershell
cmd /c ""D:\programe_files\vivado\2025.2\Vivado\settings64.bat" && vivado -mode batch -source scripts\build_bupt_riscv.tcl"
```

Program NEXYS4 DDR:

```powershell
cmd /c ""D:\programe_files\vivado\2025.2\Vivado\settings64.bat" && vivado -mode batch -source scripts\program_bupt_riscv.tcl"
```

Expected UART settings: `115200 8N1`.

Expected boot output includes:

```text
BUPT RISC-V CPU PROJECT
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
```

