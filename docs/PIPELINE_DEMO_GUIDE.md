# Nexys4 五级流水演示使用指南

## 1. 目标

这套演示模式用于在 Nexys4 DDR 板上直观展示当前 RISC-V CPU 的五级流水执行过程。它和原有串口 shell 模式并存：

- `sw[15] = 0`：正常模式，继续进入原有 boot 自检和 UART shell
- `sw[15] = 1`：演示模式，直接进入专用流水线展示程序

演示模式不会依赖 UART 输入，也不会进入 DDR benchmark，重点是稳定观察流水线在板上的流动、停顿和冲刷。

## 2. 上板前准备

1. 生成 boot ROM：

```powershell
python software\bupt_riscv\gen_bupt_boot.py
```

2. 运行仿真回归：

```powershell
D:\Xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source scripts\sim_bupt_riscv.tcl
```

3. 生成 bitstream：

```powershell
D:\Xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source scripts\build_bupt_riscv.tcl
```

4. 下载 bitstream：

```powershell
D:\Xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source scripts\program_bupt_riscv.tcl
```

生成好的 bit 文件默认在 `build/bupt_riscv_top.bit`。

## 3. 板上资源分配

### 3.1 按键

- `btnC`：复位
- `btnU`：运行/暂停切换
- `btnL`：单步推进 1 个 CPU 周期
- `btnR`：切换数码管显示页
- `btnD`：切换慢跑速度

### 3.2 开关

- `sw[15]`：模式选择
  - `0` 为正常模式
  - `1` 为流水演示模式
- `sw[7]`：`0` 显示流水级 PC/指令，`1` 显示当前场景结果
- `sw[6:3]`：选择综合、前递、load-use、RV32M、分支、D-Cache、I-Cache 或 Timer trap 场景
- `sw[2:0]`：选择数码管当前观察的流水级
  - `000`：IF
  - `001`：ID
  - `010`：EX
  - `011`：MEM
  - `100`：WB

### 3.3 LED

- `led[4:0]`：`F / D / E / M / W` 五级当前是否有效
- `led[5]`：`load-use stall`
- `led[6]`：`mul/div stall`
- `led[7]`：`ifetch stall`
- `led[8]`：`dcache stall`
- `led[9]`：`branch flush`
- `led[10]`：`trap flush`
- `led[11]`：暂停状态指示
- `led[12]`：运行状态指示
- `led[13]`：当前是否在指令页
- `led[14]`：速度档位
- `led[15]`：当前是否处于演示模式

`led[5:10]` 都会锁存事件，直到切换场景或复位。观测层同时检查 CPU hazard 脉冲和相邻 ID/EX 指令的寄存器依赖，确保单周期冒险在实板上不会漏看。这只影响显示，不改变 CPU 的暂停或性能计数。

### 3.4 数码管

数码管有两页显示，由 `btnR` 切换。

#### 页面 A：PC 页

- 8 位数码管显示所选流水级的完整 `32-bit PC`
- 最低位小数点点亮表示所选流水级当前 `valid`

#### 页面 B：指令页

- 8 位数码管显示所选流水级的完整 `32-bit` 指令编码
- 由 `sw[2:0]` 选择 IF、ID、EX、MEM 或 WB

#### 场景结果页

- 将 `sw[7]` 置 1
- 显示当前场景写入验收 MMIO 的 32 位结果或事件计数
- 将 `sw[7]` 置 0 后恢复 PC/指令页

## 4. 演示程序里能看到什么

场景 0 保留原固定短程序；`sw[6:3]` 的 1～7 分别提供前递、load-use、RV32M、分支、D-Cache、I-Cache 和 Timer trap 的确定性循环。

- 普通顺序流动：`addi / add / sub`
- 前递：后一条指令立即使用前一条 ALU 结果
- `load-use` 冒险：`lw` 后紧跟依赖结果的 `add`
- 多周期 EX 停顿：`div`
- 分支冲刷：交替触发的 `beq`
- 可见写回：`sw`

所以老师在板上能稳定看到：

- 五级流水中的指令向后推进
- 某些周期流水暂停不动
- 分支发生时前级内容被冲掉并重新取指

## 5. 推荐演示流程

### 5.1 进入演示模式

1. 将 `sw[15]` 拨到 `1`
2. 按 `btnC` 复位
3. 观察 `led[15]` 亮起，表示进入演示模式

### 5.2 先展示“流水在流动”

1. 保持在 PC 页
2. 按 `btnU` 进入慢跑
3. 用 `sw[2:0]` 选择一个流水级，观察完整 PC 不断变化
4. 观察 `led[4:0]`，确认五级有效位随流水推进变化

### 5.3 再展示“单步”

1. 再按一次 `btnU` 暂停
2. 连续按 `btnL`
3. 每按一次，只推进 1 个 CPU 周期
4. 依次切换 `sw[2:0]`，观察 PC 和指令怎样从 IF 推进到 WB

### 5.4 展示“停顿”

1. 继续单步
2. 当 `led[5]` 亮时，说明遇到了 `load-use stall`
3. 当 `led[6]` 亮时，说明遇到了 `div` 导致的多周期 EX 停顿
4. 这时数码管会出现某几级暂时不动的现象

### 5.5 展示“冲刷”

1. 继续单步直到 `led[9]` 亮
2. 说明分支方向已经确定，前面取来的错误路径被冲刷
3. 这时 IF/ID 相关显示会发生跳变

### 5.6 对照某一级的 PC 和指令

1. 用 `sw[2:0]` 选择 IF、ID、EX、MEM 或 WB
2. 在 PC 页单步观察该级完整 PC
3. 按 `btnR` 切到指令页
4. 继续单步，观察同一级的完整指令编码

## 6. 现场演示建议

- 默认先用慢跑让老师感受到“它确实在流”
- 再切到单步，讲清楚一拍一拍推进
- 不建议一开始就讲所有优化点，先让老师看懂五级流水本体
- 遇到问题时优先检查 `sw[15]` 是否在复位前已经拨到 `1`

## 7. 常见现象解释

### 7.1 为什么有时数字不变

这通常不是卡死，而是故意设计出来的停顿：

- `lw` 的数据还没准备好
- `div` 还没算完
- 分支刚决定完，前面几级要被冲刷

### 7.2 怎样判断五级是否同时有效

数码管一次显示一个选定流水级的完整 PC 或指令；`led[4:0]` 同时给出 IF、ID、EX、MEM、WB 五级的有效状态。

### 7.3 为什么演示模式不进串口 shell

演示模式的目的不是交互调试，而是让五级流水现象稳定、可重复。如果同时依赖 UART 和 DDR，课堂现场的观察会更乱，也更难讲清楚。

## 8. 结束后如何回到原系统

1. 将 `sw[15]` 拨回 `0`
2. 按 `btnC` 复位
3. 板子会回到原来的正常模式
4. 串口会重新进入 boot 自检和 `rv32>` shell
