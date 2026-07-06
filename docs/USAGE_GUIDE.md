# BUPT RISC-V Project Usage Guide

## 1. Environment

Verified environment:

```text
Board: NEXYS4 DDR / Artix-7 xc7a100tcsg324-1
Tool:  Vivado 2025.2
OS:    Windows PowerShell
UART:  115200 8N1
```

Vivado path used on the development machine:

```powershell
D:\programe_files\vivado\2025.2\Vivado\settings64.bat
```

If Vivado is installed elsewhere, replace this path in the commands below.

## 2. Directory Overview

```text
src/bupt_riscv/top.v             FPGA top module
src/bupt_riscv/soc.v             SoC integration
src/bupt_riscv/simple_bus.v      Address decoder and MMIO bus
src/bupt_riscv/riscv_core/       Five-stage RV32I CPU core
src/bupt_riscv/dcache_2way_lru.v 2-way LRU D-cache
src/bupt_riscv/fp_mmio.v         FP32 MMIO coprocessor
software/bupt_riscv/             Boot image generator
sim/bupt_riscv_tb.v              Simulation testbench
scripts/                         Vivado batch scripts
constr/                          NEXYS4 DDR constraints
docs/                            Documentation
```

## 3. Generate Boot ROM

Run from the repository root:

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

Generated files:

```text
src/bupt_riscv/bupt_riscv_boot.mem
software/bupt_riscv/gen_bupt_boot.lst
```

The `.mem` file initializes the boot ROM. The `.lst` file is useful during defense because it lists the generated RISC-V machine code and labels.

## 4. Run Simulation

```powershell
cmd /c ""D:\programe_files\vivado\2025.2\Vivado\settings64.bat" && vivado -mode batch -source scripts\sim_bupt_riscv.tcl"
```

Success markers:

```text
Simulation succeeded: BUPT RISC-V CPU verified
BUPT_RISCV_SIM_DONE
```

The testbench checks:

- UART boot banner.
- RV32I instruction self-test.
- RV32M multiply/divide self-test.
- DDR read/write pattern test.
- Cache and FP MMIO self-tests.
- Shell commands: `help`, `mem`, `cache`, `fp`, `perf`, `led 1`, `run demo`.
- LED MMIO write.
- Performance counter output.

## 5. Build Bitstream

```powershell
cmd /c ""D:\programe_files\vivado\2025.2\Vivado\settings64.bat" && vivado -mode batch -source scripts\build_bupt_riscv.tcl"
```

Expected output:

```text
build/bupt_riscv_top.bit
```

The last verified build passed timing at 100 MHz. See [bupt_riscv_build_summary.md](bupt_riscv_build_summary.md).

## 6. Program the Board

Connect the NEXYS4 DDR board by USB, then run:

```powershell
cmd /c ""D:\programe_files\vivado\2025.2\Vivado\settings64.bat" && vivado -mode batch -source scripts\program_bupt_riscv.tcl"
```

Open a serial terminal:

```text
Baud rate: 115200
Data bits: 8
Parity:    none
Stop bits: 1
Flow ctrl: none
```

Expected UART output:

```text
BUPT RISC-V CPU PROJECT
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
```

Useful shell commands:

```text
help       Print command list
mem        Run memory/DDR check
cache      Print cache statistics
fp         Run FP32 MMIO demo
perf       Print cycle, retired, branch, mispredict, stall counters
led 1      Turn on LED output
run demo   Run integrated demo
```

## 7. Common Problems

### Vivado command not found

Check the settings script path:

```powershell
Test-Path "D:\programe_files\vivado\2025.2\Vivado\settings64.bat"
```

If it returns `False`, find the actual Vivado installation path and replace it in the commands.

### Simulation timeout

Regenerate the boot ROM first:

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

Then rerun `scripts\sim_bupt_riscv.tcl`. If it still times out, inspect the Vivado transcript for the last printed UART character or the last testbench checkpoint.

### Board has no UART output

Check:

- Serial port is the NEXYS4 DDR USB-UART port.
- Baud rate is `115200`.
- FPGA was programmed with `build/bupt_riscv_top.bit`.
- Reset button/polarity matches the XDC and top module.

## 8. Suggested Acceptance Evidence

For the final course report, save:

- Simulation transcript containing `BUPT_RISCV_SIM_DONE`.
- Vivado timing/resource reports.
- Serial terminal screenshot showing boot self-test pass messages.
- Photo or video showing `led 1` changes LED output.
- `perf` command output and CPI calculation.

