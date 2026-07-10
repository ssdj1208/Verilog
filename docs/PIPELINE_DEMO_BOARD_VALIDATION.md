# 流水演示实板验证记录

验证日期：2026-07-10

## 1. 环境

- 板卡：NEXYS4 DDR
- FPGA：`xc7a100t_0` / `xc7a100tcsg324-1`
- JTAG：Digilent `210292747828A`
- 串口：FTDI `COM8`，115200 8N1，无流控
- 工具：Vivado 2023.2
- 最终 bitstream：`build/bupt_riscv_top.bit`
- SHA-256：`84A9BEABD2FFE16278EB5F912B2DC36377CC32A2A752521DDDB326131BB43871`

## 2. 自动验证

- Boot ROM 连续生成两次哈希一致，深度为 4096 words。
- 指令构造器无界面组装测试通过，覆盖标签回填、RV32M、CSR 和 `PANEL_BASE`。
- 原 SoC testbench 通过：`Simulation succeeded: BUPT RISC-V CPU verified`。
- 流水演示 testbench 通过：`Simulation succeeded: pipeline demo stepping verified`。
- 面板映射 testbench 通过：`Simulation succeeded: pipeline demo panel verified`。
- Vivado 仿真脚本输出：`BUPT_RISCV_SIM_DONE`。

## 3. 实现结果

最终 routed timing：

```text
WNS = +0.034 ns
TNS = 0.000 ns
WHS = +0.012 ns
THS = 0.000 ns
```

所有用户时序约束满足。演示时钟最终使用单一 `BUFGCE`：正常模式保持 CE 开启，演示模式使用脉冲 CE；Vivado methodology 中原有的 `TIMING-14 LUT on the clock tree` 和 `demo_mode_latched` 非时钟锁存告警均已消除。

## 4. 正常模式

`SW15=0` 下载最终 bitstream 后，串口输出：

```text
BUPT RISC-V CPU PROJECT
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
rv32>
```

Shell 的 `help`、`perf`、`cache` 和 `fp` 命令均返回结果并重新出现 `rv32>`。

## 5. 演示模式

`SW15=1` 并复位后完成以下实板检查：

- `LD15` 指示演示模式，启动后 `LD11` 指示暂停。
- `btnL` 单步时每次只推进一个 CPU 周期。
- `btnU` 可切换运行和暂停，`LD11/LD12` 状态正确。
- `btnD` 可切换速度，`LD14` 状态和运行速度同步变化。
- `btnR` 可切换 PC 页和指令页，`LD13` 状态正确。
- `SW[2:0]` 可选择 IF、ID、EX、MEM、WB 流水级。
- `LD5` 最终能锁存 load-use 依赖事件。
- `LD6` 能观察到多周期除法停顿。
- `LD9` 能观察到分支冲刷。
- 将 `SW15` 拨回 0 并复位后，UART Shell 可恢复。

## 6. LD5 诊断记录

初次连续运行时，单周期 load-use 事件不易观察。曾生成临时诊断 bitstream，强制 `led = 16'h0020`，确认 `LD5`、V17 引脚和 XDC 约束正常；该诊断常量未保留在正式源码中。

正式实现同时使用 CPU hazard 脉冲和 ID/EX 指令寄存器依赖检测，并将本次复位后出现过的 load-use 事件锁存到 `LD5`。最终实板运行完整演示循环后，`LD5` 正常点亮。
