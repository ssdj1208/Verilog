# Project Completion Analysis

## 1. Overall Conclusion

The project is suitable as a BUPT project-course stage 2 topic B submission baseline. It implements a standalone RV32I five-stage pipelined CPU SoC for NEXYS4 DDR, with simulation scripts, build scripts, boot software, MMIO peripherals, performance counters, and several extension features.

Current status:

```text
Simulation: passed
Implementation/bitstream: passed
Timing target: 100 MHz met
Board-level evidence: to be collected by the student on physical NEXYS4 DDR hardware
```

The design already covers the basic and advanced CPU requirements. The main remaining work is not RTL development, but collecting physical-board proof and writing the final report with screenshots, waveforms, PPA discussion, and measured performance data.

## 2. Requirement Coverage Matrix

| Requirement | Status | Evidence |
| --- | --- | --- |
| RV32I or custom ISA CPU | Complete | RV32I decode, immediate generation, ALU, load/store, branch, jump are implemented under `src/bupt_riscv/riscv_core/`. |
| Basic arithmetic and logic instructions | Complete | `add/sub/sll/slt/sltu/xor/srl/sra/or/and` and I-type ALU operations are supported. |
| Basic memory access | Complete | `lb/lh/lw/lbu/lhu` and `sb/sh/sw` are implemented with byte-lane alignment. |
| Branch and jump instructions | Complete | `beq/bne/blt/bge/bltu/bgeu`, `jal`, and `jalr` are implemented. |
| Five-stage pipeline | Complete | IF, ID, EX, MEM, WB pipeline registers and control flow are implemented in `riscv.v`. |
| Data hazard handling | Complete | EX/MEM/WB forwarding and load-use stall are implemented. |
| Control hazard handling | Complete | Branch prediction, EX-stage resolution, and wrong-path flush are implemented. |
| Memory and I/O integration | Complete | Boot ROM, BRAM, UART, GPIO, timer, DDR bridge, and MMIO bus are integrated. |
| Performance counters | Complete | Cycle, retired instruction, branch, mispredict, and stall counters are exposed by MMIO. |
| Vivado 2025.2 simulation script | Complete | `scripts/sim_bupt_riscv.tcl`. |
| Vivado 2025.2 build script | Complete | `scripts/build_bupt_riscv.tcl`. |
| NEXYS4 DDR programming script | Complete | `scripts/program_bupt_riscv.tcl`. |
| Physical board validation | Pending evidence | Needs serial screenshot, LED photo/video, and hardware run log after programming the board. |

## 3. RV32I Instruction Coverage

Implemented course subset:

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

Important correctness points:

- `x0` is hardwired to zero in the register file.
- B-type and J-type immediates use RISC-V bit placement.
- Branch target uses `PC + imm`.
- `jal` writes `PC + 4`.
- `jalr` target clears bit 0.
- Signed and unsigned branch comparisons are separated.
- Load extension handles signed and zero-extended byte/halfword reads.

## 4. Pipeline and Hazard Completion

Implemented:

- IF-stage instruction fetch and branch prediction.
- ID-stage decode, register read, and immediate generation.
- EX-stage ALU execution, branch/jump resolution, target generation.
- MEM-stage data bus access.
- WB-stage register writeback.
- EX/MEM/WB to EX forwarding.
- Load-use hazard stall.
- DDR or slow-MMIO wait-state pipeline freeze.
- Branch/jump misprediction flush.

This satisfies the typical defense focus areas: why forwarding is needed, when stall is unavoidable, and how control hazards are corrected.

## 5. Extension Feature Completion

### 5.1 Branch Prediction

Status: complete.

Implemented as a 64-entry direct-mapped BTB/BHT:

- BTB stores predicted target.
- BHT uses 2-bit saturating counters.
- IF stage predicts.
- EX stage resolves and updates.
- Mispredict count is exposed through performance counters.

### 5.2 D-Cache Replacement Strategy

Status: complete.

Implemented in `src/bupt_riscv/dcache_2way_lru.v`:

- 16 sets.
- 2 ways.
- 1 word per cache line.
- LRU victim selection.
- Write-through policy.
- Statistics: accesses, hits, misses, replacements.
- MMIO address region: `0x1000_6000`.

This is suitable for the course extension direction "Cache replacement strategy and hit-rate analysis".

### 5.3 RV32M Multiply/Divide

Status: complete.

Implemented instructions:

```text
mul, mulh, mulhsu, mulhu, div, divu, rem, remu
```

The ALU includes RISC-V special-case behavior for divide-by-zero and signed overflow.

### 5.4 FP32 MMIO Coprocessor

Status: complete as an MMIO coprocessor, not as full RISC-V F extension.

Implemented in `src/bupt_riscv/fp_mmio.v`:

- FP32 add demo path.
- FP32 multiply demo path.
- MMIO address region: `0x1000_7000`.
- Boot self-test prints `FP TEST OK`.

For the final report, describe it as a memory-mapped floating-point coprocessor. Do not claim it is a full RISC-V F extension with floating-point registers and IEEE exception flags.

## 6. Verification Status

Simulation success markers:

```text
Simulation succeeded: BUPT RISC-V CPU verified
BUPT_RISCV_SIM_DONE
```

Boot output checked by testbench:

```text
BUPT RISC-V CPU PROJECT
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
```

The latest implementation generated a bitstream and met 100 MHz timing. Summary:

| Metric | Result |
| --- | ---: |
| WNS | 1.316 ns |
| TNS | 0.000 ns |
| Main 100 MHz clock WNS | 6.688 ns |
| LUTs | 14279 / 63400, 22.52% |
| Registers | 12305 / 126800, 9.70% |
| BRAM tiles | 5 / 135, 3.70% |
| DSPs | 14 / 240, 5.83% |
| Estimated power | 1.826 W |

## 7. Remaining Work Before Final Defense

The RTL and scripts are complete enough for course acceptance. Before final submission, collect and add the following evidence to the report:

- Vivado simulation transcript screenshot.
- Timing summary screenshot.
- Utilization summary screenshot.
- Serial terminal screenshot after programming NEXYS4 DDR.
- Photo or short video proving LED control works.
- `perf` command output and CPI calculation.
- A short PPA tradeoff paragraph explaining the cost of pipeline forwarding, branch prediction, cache, RV32M, and FP MMIO.

## 8. Recommended Defense Talking Points

- The design uses RV32I rather than the original MIPS ISA.
- The CPU is not a single-cycle demo; it is a five-stage pipelined design.
- Load-use hazards still need a stall because the loaded value is only available after memory access.
- Forwarding reduces most ALU-to-ALU stalls.
- Branch prediction improves control-flow throughput but costs LUT/register resources and needs flush recovery.
- The cache uses LRU replacement to make replacement behavior explainable and measurable.
- FP support is implemented as an MMIO coprocessor to keep the CPU core and register file manageable for a course project.

