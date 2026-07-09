# RISC-V Instruction Studio

> 新版界面已经按中文用户和课程设计展示场景重新制作。下面这一段为当前版本说明。

运行方式：

```powershell
cd D:\vscode\小学期计组课设\Verilog
python tools\riscv_instruction_builder.py
```

新版特点：

- 中文界面：操作码、指令格式、立即数、地址快捷名、输出文件、状态提示均使用中文说明。
- 小型 IDE 风格：顶部 Header、左侧指令构建器、右侧程序预览、底部输出文件区。
- 高分屏优化：启动时启用 Windows DPI awareness，并设置 Tk scaling，减少字体发虚。
- 核心逻辑不变：指令编码、程序数据结构、`.mem/.lst` 生成格式都保持原有行为。
- 错误提示不再弹出默认错误框，而是在底部状态栏用中文显示。

---

`riscv_instruction_builder.py` is a polished Tkinter GUI for building boot ROM
programs for the BUPT RISC-V SoC. It keeps the assembler dependency-free while
presenting the workflow like a small instruction studio.

Run it from the `Verilog` directory:

```powershell
cd D:\vscode\小学期计组课设\Verilog
python tools\riscv_instruction_builder.py
```

If the path above is displayed incorrectly by your editor, use:

```powershell
cd D:\vscode\小学期计组课设\Verilog
python tools\riscv_instruction_builder.py
```

## What It Does

- Uses a left-side instruction editor and right-side program preview.
- Selects an opcode from a dropdown and shows the exact instruction format.
- Displays only the fields required by the selected instruction.
- Accepts registers, immediates, offsets, labels, CSR names, and board address shortcuts.
- Adds, deletes, reorders, and previews instructions.
- Shows the used boot-ROM word count.
- Generates:
  - `src/bupt_riscv/bupt_riscv_boot.mem`
  - `software/bupt_riscv/gen_bupt_boot.lst`

The generated `.mem` file has 4096 32-bit words, matching `boot_rom.v`.

## Quick Demo

Click `Load LED demo`, then `Generate .mem and .lst`.

The generated program does:

```asm
li   x1, 5
li   x2, 7
add  x3, x1, x2
li   x4, GPIO_BASE
sw   x3, 0(x4)
done:
j    done
```

On hardware, LED bits should show decimal 12 (`0x000c`).

## Supported Instruction Groups

- Pseudo/directives: `label`, `nop`, `li`, `j`, `call`, `ret`
- RV32I arithmetic/logical: `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and`
- RV32I immediate: `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai`
- Loads/stores: `lb`, `lh`, `lw`, `lbu`, `lhu`, `sb`, `sh`, `sw`
- Control flow: `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`, `jal`, `jalr`
- RV32M: `mul`, `mulh`, `mulhsu`, `mulhu`, `div`, `divu`, `rem`, `remu`
- CSR/system: `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci`, `mret`

## Address Shortcuts

Immediate fields accept either numbers such as `0x10000000` or these shortcuts:

```text
GPIO_BASE
UART_BASE
TIMER_BASE
IRQ_BASE
DDR_STATUS_BASE
PERF_BASE
CACHE_BASE
FP_BASE
DEBUG_BASE
DDR_BASE
BRAM_BASE
```

## After Generating

Run simulation:

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\sim_bupt_riscv.tcl"
```

Build bitstream:

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\build_bupt_riscv.tcl"
```

Program the board:

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\program_bupt_riscv.tcl"
```
