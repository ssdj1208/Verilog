# BUPT RISC-V CPU 优化路线图

本文档面向当前 `Verilog/src/bupt_riscv` 工程，规划后续四类优化：

- 完成程序中断机制
- 提升 CPU/SoC 主频
- 优化指令和数据内存系统
- 基于性能计数器降低 CPI

优化目标不是一次性把工程改成复杂乱序 CPU，而是在现有五级流水 RV32I/M SoC 基础上，逐步提升体系结构完整度、可测性能和课程报告说服力。

## 1. 当前基线

### 1.1 结构现状

当前工程已经具备以下基础：

```text
CPU：RV32I 五级流水，支持 RV32M 扩展
SoC：Boot ROM、BRAM、UART、GPIO、Timer、IRQ Controller、DDR Bridge、D-Cache、FP MMIO、Perf MMIO
验证：Vivado 仿真脚本、综合实现脚本、NEXYS4 DDR 下载脚本
性能计数：cycles、retired、branches、mispredicts、stalls
```

相关文件：

```text
src/bupt_riscv/top.v
src/bupt_riscv/soc.v
src/bupt_riscv/simple_bus.v
src/bupt_riscv/timer_mmio.v
src/bupt_riscv/irq_controller.v
src/bupt_riscv/perf_mmio.v
src/bupt_riscv/dcache_2way_lru.v
src/bupt_riscv/riscv_core/riscv.v
software/bupt_riscv/gen_bupt_boot.py
```

### 1.2 性能基线

当前顶层输入系统时钟为 100 MHz。最新实测版本为 2026-07-08 `build19`，SoC/CPU 时钟约束为 100 MHz；RTL 中部分信号仍沿用 `clk50mhz` / `clk50_unbuf` 的历史命名，但 Vivado clock summary 显示 `clk50_unbuf` period 为 10.000 ns，即 100.000 MHz。因此当前性能计数器中的 `cycles` 按 100 MHz 换算时间：

```text
运行时间(s) = cycles / 100,000,000
CPI = cycles / retired
IPC = retired / cycles
stall_rate = stalls / cycles
branch_miss_rate = mispredicts / branches
```

最新 `build19` 实现报告可作为当前 PPA 基线：

```text
WNS = 0.080 ns
TNS = 0.000 ns
LUT = 17229 / 63400 = 27.18%
Register = 30329 / 126800 = 23.92%
BRAM = 9 / 135 = 6.67%
DSP = 2 / 240 = 0.83%
Total On-Chip Power = 1.171 W
Power confidence = Low
```

注意：Vivado 功耗报告 confidence 为 Low，只适合作为估算和 PPA 讨论依据，不应写成精确实测功耗。

### 1.3 优化总原则

后续优化建议遵循以下顺序：

```text
先测量 -> 再改架构 -> 每次只改一类瓶颈 -> 重新仿真和实现 -> 对比数据
```

不要把中断、提频、Cache、分支预测和流水线调整一次性全改完。这样调试难度会急剧上升，也很难说明到底是哪项优化带来了性能收益。

## 2. 阶段 0：建立可复现实验基线

在做大改之前，先把性能测量流程固定下来。

### 2.1 建议新增 shell 命令

当前 `perf` 命令可以打印计数器，但不方便在同一次上板运行中清零和重复测试。建议扩展 boot shell：

```text
perf          打印性能计数器
perf clear    清零性能计数器
bench alu     运行 ALU 循环 benchmark
bench mem     运行 BRAM/DDR/cache benchmark
bench branch  运行分支预测 benchmark
bench int     运行中断响应 benchmark
```

如果命令解析暂时不想做复杂，可以先加入简单命令：

```text
pclr          清零性能计数器
balu          ALU benchmark
bmem          内存 benchmark
bbr           branch benchmark
```

### 2.2 建议记录的基线数据

每次优化前后都记录一张表：

| 项目 | cycles | retired | CPI | branches | mispredicts | branch miss rate | stalls | stall rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| boot 自测后 |  |  |  |  |  |  |  |  |
| bench alu |  |  |  |  |  |  |  |  |
| bench mem |  |  |  |  |  |  |  |  |
| bench branch |  |  |  |  |  |  |  |  |

内存系统优化后还应记录：

| 项目 | cache accesses | cache hits | cache misses | hit rate | refill cycles |
| --- | ---: | ---: | ---: | ---: | ---: |
| bench mem |  |  |  |  |  |

### 2.3 验收标准

阶段 0 完成后应满足：

- 串口可稳定运行 benchmark 命令。
- `perf clear` 后计数器从接近 0 开始累加。
- 同一 bitstream、同一 benchmark 连续运行得到一致结果。
- 报告中可以给出优化前的 CPI、stall rate、branch miss rate、cache hit rate。

## 3. 阶段 1：完成程序中断机制

### 3.1 当前状态

当前工程已有中断相关外设：

```text
timer_mmio.v       可产生 timer_irq
irq_controller.v   可屏蔽和查询 irq pending
simple_bus.v       已映射 IRQ MMIO 区域
soc.v              已连接 irq_lines
```

但当前 CPU 核还没有完整的 RISC-V trap/CSR/异常返回链路。也就是说，目前更像是“中断外设已经存在”，还不是“CPU 能自动响应中断”。

### 3.2 最小实现目标

先实现最小机器态中断即可：

```text
1. Timer 产生 pending。
2. IRQ Controller 输出 irq_lines。
3. CPU 在允许中断时检测到 irq_lines 非 0。
4. CPU 在精确提交边界进入 trap。
5. 保存 mepc 和 mcause。
6. 跳转到 mtvec。
7. 中断处理程序清除 timer pending。
8. 执行 mret 返回原程序。
```

推荐先把 `|irq_lines` 映射为 machine external interrupt：

```text
mcause = 0x8000000b
含义：Machine external interrupt
```

后续如果想更贴近标准 CLINT，可把 timer 单独映射成 MTIP：

```text
mcause = 0x80000007
含义：Machine timer interrupt
```

### 3.3 需要支持的 CSR

最小 CSR 集合：

| CSR | 地址 | 用途 |
| --- | ---: | --- |
| `mstatus` | `0x300` | 至少支持 `MIE` 和 `MPIE` |
| `mie` | `0x304` | 至少支持 `MEIE` 或 `MTIE` |
| `mtvec` | `0x305` | 中断入口地址 |
| `mepc` | `0x341` | trap 返回 PC |
| `mcause` | `0x342` | trap 原因 |
| `mip` | `0x344` | pending 状态，可由 irq 输入反映 |

最小指令支持：

```text
csrrw
csrrs
csrrc
csrrwi/csrrsi/csrrci 可选
mret
```

如果时间紧，可以先只实现 boot 程序确实会用到的 CSR 指令组合。

### 3.4 CPU 修改建议

建议新增或拆分以下模块：

```text
riscv_core/csr_file.v       CSR 寄存器和读写逻辑
riscv_core/trap_ctrl.v      中断进入、mret 返回、flush 控制
```

也可以先直接集成在 `riscv.v` 中，等功能稳定后再拆模块。

关键控制逻辑：

```text
irq_take = global_mie && enabled_irq_pending && pipeline_can_take_trap

进入中断时：
  mepc <= interrupted_pc
  mcause <= interrupt_cause
  mstatus.MPIE <= mstatus.MIE
  mstatus.MIE <= 0
  pc <= mtvec
  flush IF/ID/EX/MEM 中错误路径指令

mret 时：
  pc <= mepc
  mstatus.MIE <= mstatus.MPIE
  mstatus.MPIE <= 1
  flush 后续流水级
```

`pipeline_can_take_trap` 建议选择在不会破坏精确状态的位置，例如：

```text
不在 reset
不在 memstall
当前有可提交指令，或流水线处于可安全重定向状态
```

### 3.5 软件测试程序

boot 程序中加入中断测试：

```text
1. 设置 mtvec = irq_handler。
2. 设置 mie.MEIE 或 mie.MTIE。
3. 设置 mstatus.MIE。
4. 配置 timer compare、enable、irq_enable、auto_reload。
5. 主循环继续打印 prompt 或执行空循环。
6. irq_handler 中：
   - 保存临时寄存器
   - 读取/更新一个全局 tick 计数
   - 可切换 LED 或打印简短标记
   - 清除 timer pending
   - 恢复寄存器
   - mret
```

建议串口命令：

```text
int on       开启 timer interrupt
int off      关闭 timer interrupt
int stat     打印 tick 计数和 irq pending
```

### 3.6 验收标准

中断阶段完成后应满足：

- 仿真中可观察到 `pc -> mtvec -> mret -> mepc`。
- 上板后 `int on` 能让 LED 或 tick 计数周期性变化。
- 中断处理后 shell 仍然可用，没有跑飞。
- `perf` 中可以观察到中断开启后额外 cycles 和 retired 指令。
- 报告中能展示中断响应流程图、CSR 表和串口/LED 现象。

## 4. 阶段 2：提升主频

### 4.1 目标设定

规划初始基线曾以 50 MHz SoC 主频为目标起点；当前 `build19` 已实现 100 MHz 稳定运行。本节保留提频阶段设计思路，用于说明从旧基线到当前版本的优化路径：

```text
第一目标：75 MHz 稳定通过实现
第二目标：100 MHz 稳定通过实现
挑战目标：125 MHz，视时序余量决定是否继续
```

课程项目中，若能在 NEXYS4 DDR 上稳定跑到 100 MHz，并保留 DDR、Cache、UART 和中断功能，已经是很有说服力的优化。

### 4.2 需要同步调整的参数

提频不是只改 MMCM 输出。以下参数必须同步检查：

| 项目 | 50 MHz 旧基线值 | 100 MHz 目标值 | 说明 |
| --- | ---: | ---: | --- |
| UART `CLKS_PER_BIT` | 434 | 868 | 115200 波特率 |
| Timer tick | `500000` 等 | 按目标时间翻倍 | 保持真实时间不变 |
| XDC 约束 | 派生 50 MHz | 派生目标频率 | 保证 Vivado 真正约束 CPU 时钟 |
| CDC false path | 已有部分约束 | 重新检查 | 避免错误约束或漏约束 |

### 4.3 常见关键路径

根据当前结构，优先排查这些路径：

```text
simple_bus 大型 rdata mux
dcache tag compare + data select
ALU / branch compare / branch target
乘法、除法、FP MMIO 组合路径
CSR/trap 新增控制逻辑
流水线 stall/flush 控制扇出
DDR bridge ready/rdata 返回路径
```

### 4.4 RTL 优化手段

优先做低风险改法：

```text
1. 将 MMIO 外设 rdata 注册化。
2. 将 simple_bus 的大 mux 拆成分层 mux。
3. 对 FP MMIO 输出增加寄存器，避免长组合路径直达总线。
4. 对 D-Cache tag/data 输出增加一级寄存。
5. 对乘法使用 DSP pipeline。
6. 对除法保持迭代，但避免 busy 信号形成长控制路径。
7. 降低高扇出 stall/flush 信号的组合复杂度。
```

如果 100 MHz 仍不满足，再考虑更深流水：

```text
IF1/IF2：取指地址和指令返回分开
EX1/EX2：ALU/branch/乘法路径分开
MEM1/MEM2：cache tag 和 data 返回分开
```

### 4.5 验收标准

提频阶段完成后应满足：

- Vivado routed timing summary 中 WNS >= 0。
- 串口输出正常，UART 波特率无乱码。
- boot 自测全部通过。
- `perf` 中同一个 benchmark 的 cycles 可比较，实际时间按新主频换算后下降。
- 报告中给出提频前后 PPA 对比表。

建议表格：

| 版本 | SoC 频率 | WNS | LUT | Reg | BRAM | DSP | bench alu time | bench mem time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline | 50 MHz |  |  |  |  |  |  |  |
| freq75 | 75 MHz |  |  |  |  |  |  |  |
| freq100 | 100 MHz |  |  |  |  |  |  |  |

## 5. 阶段 3：优化内存系统

### 5.1 当前瓶颈判断

如果 `bench mem` 的 CPI 明显高于 `bench alu`，并且 `stalls/cycles` 较高，主要瓶颈通常在：

```text
取指等待
load-use stall
D-Cache miss
DDR 访问延迟
写穿透造成的写等待
总线仲裁或 CDC 等待
```

当前 D-Cache 设计偏教学友好，适合验证，但仍有提升空间：

```text
容量较小
cache line 较短
write-through 简单但写性能有限
DDR burst 利用不足
miss 时流水线基本阻塞
```

### 5.2 优先级 1：加入 I-Cache

高性能处理器首先要稳定供指。建议新增 I-Cache：

```text
容量：1 KB 或 2 KB 起步
相联度：直接映射或 2 路组相联
line size：4 words 或 8 words
策略：只读 cache，无需 dirty bit
接口：CPU i_addr/i_data/i_ready
miss refill：从 Boot ROM/BRAM/DDR 取一整条 line
```

收益：

```text
减少取指等待
降低分支后重新取指代价
为后续预取队列打基础
```

风险：

```text
需要处理分支 flush 和 miss refill 的交互
需要保证 Boot ROM、BRAM、DDR 地址空间一致
如果存在自修改代码，需要加 invalidate；当前 boot 场景可暂不支持
```

### 5.3 优先级 2：升级 D-Cache line 和 refill

建议从当前单 word line 升级为多 word line：

```text
line size：4 words
refill：一次 miss 连续读取 4 个 word
hit：按 offset 选择 word
```

如果 DDR bridge 支持 burst，可进一步做：

```text
DDR burst read 一次填满 cache line
对齐地址发起 burst
refill FSM 记录 beat index
```

收益：

```text
顺序访问数组时 miss 次数降低
DDR 带宽利用率提高
bench mem 的 cycles 明显下降
```

### 5.4 优先级 3：Store Buffer

在 write-through 策略下，store 可能让流水线等待外设或 DDR。可以加入 store buffer：

```text
CPU store 命中后写入 buffer
流水线继续前进
后台慢慢写回下级存储
load 若命中 store buffer，需要 forward 最新数据
```

收益：

```text
降低 store 密集程序的 stall
保持 write-through 一致性，复杂度低于完整 write-back
```

风险：

```text
需要处理 load-after-store forwarding
需要处理 MMIO 区域不能随意缓冲
```

### 5.5 优先级 4：Write-back D-Cache

如果时间充裕，再考虑 write-back：

```text
每条 line 增加 dirty bit
替换 dirty line 前先 writeback
store hit 只更新 cache
store miss 选择 write-allocate 或 no-write-allocate
```

收益：

```text
大幅减少重复写 DDR
更接近真实高性能处理器
```

风险：

```text
状态机复杂度明显增加
调试难度高
需要处理 flush/invalidate
MMIO 区域必须 bypass cache
```

课程项目更推荐先做 I-Cache、多 word line、DDR burst、store buffer。write-back 可以作为挑战项。

### 5.6 增强内存性能计数器

建议补充以下计数：

```text
icache_accesses
icache_hits
icache_misses
dcache_accesses
dcache_hits
dcache_misses
dcache_writebacks
refill_cycles
ddr_read_reqs
ddr_write_reqs
ddr_wait_cycles
```

这样报告中可以把“内存系统优化”讲清楚，而不是只说感觉更快。

### 5.7 验收标准

内存系统阶段完成后应满足：

- Boot、自测、shell、DDR 测试仍然通过。
- `bench mem` cycles 下降。
- cache hit rate 可打印并可复现。
- DDR 访问不破坏 MMIO 和 UART。
- Vivado 时序仍满足目标频率。

## 6. 阶段 4：降低 CPI

### 6.1 CPI 分解方法

不要只看总 CPI，要把 CPI 拆成原因：

```text
CPI = cycles / retired
stall_rate = stalls / cycles
branch_miss_rate = mispredicts / branches
cache_miss_rate = cache_misses / cache_accesses
```

建议新增更细的 stall 计数：

```text
stall_load_use
stall_ifetch
stall_dcache_miss
stall_ddr_wait
stall_muldiv
stall_fp
flush_branch
flush_trap
```

这样可以判断该优先优化哪里：

| 现象 | 可能瓶颈 | 优先优化 |
| --- | --- | --- |
| `stall_ifetch` 高 | 取指等待 | I-Cache / prefetch |
| `stall_dcache_miss` 高 | 数据 miss | D-Cache line / DDR burst |
| `branch_miss_rate` 高 | 分支预测弱 | BHT/BTB/gshare/RAS |
| `stall_load_use` 高 | load-use 冒险 | 编译调度/旁路/流水调整 |
| `stall_muldiv` 高 | 乘除法阻塞 | 乘法流水化/除法非阻塞 |
| `stall_fp` 高 | FP MMIO 等待 | FP pipeline / ready-valid |

### 6.2 分支预测优化

当前已有分支预测，可继续增强：

```text
1. 增大 BHT/BTB 表项。
2. 使用 2-bit 饱和计数器。
3. 引入 gshare：PC xor 全局历史。
4. JAL/JALR target 提前预测。
5. 增加 Return Address Stack，用于函数返回预测。
6. 统计预测命中率并在 perf 中输出。
```

优先级建议：

```text
2-bit BHT + BTB 容量扩大 -> gshare -> RAS
```

### 6.3 Load-use 和数据冒险优化

五级流水中 load-use stall 很常见。优化方向：

```text
1. 确认 MEM/WB 到 EX 的 forwarding 完整。
2. 对 load-use 只停必要周期，避免额外停顿。
3. 对 BRAM/cache hit 数据尽量提前返回。
4. 在 boot benchmark 中调整指令排布，观察硬件极限和软件调度差异。
```

如果加入两级 MEM，需要重新检查 load-use 规则：

```text
MEM1 tag check
MEM2 data return
load-use stall 可能增加，需要通过 forwarding 和调度抵消
```

### 6.4 乘除法和 FP 优化

推荐优先级：

```text
1. 乘法使用 DSP pipeline，做到固定短延迟。
2. 除法保持迭代，但只阻塞依赖结果的指令。
3. FP MMIO 改 ready-valid 协议，避免长组合路径。
4. 常用 FP 操作可流水化，结果通过寄存器返回。
```

注意：如果为了提频增加 pipeline，单条指令 latency 可能变长，但总吞吐可能提高。报告中要区分：

```text
Latency：单次操作延迟
Throughput：每秒完成多少操作
CPI：平均每条 retired 指令消耗周期
```

### 6.5 前端预取队列

在 I-Cache 之后，可以加入简单预取队列：

```text
fetch queue depth：2 到 4 条指令
顺序 PC 自动预取
分支 mispredict 时 flush queue
I-Cache miss 时暂停填充
```

收益：

```text
隐藏部分取指延迟
减轻后端短暂停顿造成的前端空泡
```

### 6.6 验收标准

CPI 优化阶段完成后应满足：

- `bench alu` CPI 接近 1。
- `bench branch` 的 branch miss rate 下降。
- `bench mem` 的 CPI 和 stall rate 下降。
- 每项优化都能用计数器解释收益来源。

建议报告表格：

| 版本 | benchmark | CPI | stall rate | branch miss rate | cache hit rate | 说明 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| baseline | alu |  |  |  |  |  |
| +interrupt | alu |  |  |  |  | 功能增强，性能略受影响 |
| +100MHz | alu |  |  |  |  | cycles 可能相近，真实时间下降 |
| +I-Cache | mem |  |  |  |  | 取指等待下降 |
| +D-Cache line | mem |  |  |  |  | 数据 miss 成本下降 |
| +branch opt | branch |  |  |  |  | mispredict 下降 |

## 7. 推荐实施顺序

### 7.1 低风险路线

如果目标是稳妥完成课程优化：

```text
1. perf clear + benchmark 命令
2. 完成最小 timer interrupt
3. 提频到 75 MHz
4. 加 I-Cache
5. D-Cache 多 word line
6. 提频到 100 MHz
7. 分支预测小幅增强
```

优点：

```text
每一步都能独立验证
报告材料丰富
不容易把工程改崩
```

### 7.2 高性能路线

如果目标是更接近高性能软核：

```text
1. perf 细分计数器
2. I-Cache + fetch queue
3. D-Cache 多 word line + DDR burst
4. Store buffer
5. 100 MHz 时序优化
6. 乘法流水化
7. gshare + RAS
8. write-back D-Cache
```

优点：

```text
性能收益更大
体系结构更接近真实处理器
```

代价：

```text
验证工作量大
Cache 一致性和异常交互复杂
时序压力明显增加
```

## 8. 验证计划

### 8.1 仿真验证

每次修改后至少跑：

```powershell
python software\bupt_riscv\gen_bupt_boot.py
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\sim_bupt_riscv.tcl"
```

建议仿真检查点：

```text
RV32I ISA PASS
M EXT PASS
DDR TEST OK
CACHE READY
FP TEST OK
PERF READY
INT TEST OK
BUPT_RISCV_SIM_DONE
```

中断相关波形重点：

```text
irq_lines
csr_mstatus
csr_mie
csr_mtvec
csr_mepc
csr_mcause
pc
flush
mret
```

Cache 相关波形重点：

```text
cache_access
cache_hit
cache_miss
refill_state
ddr_backend_valid
ddr_backend_ready
cpu_stall
```

### 8.2 上板验证

上板流程：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\build_bupt_riscv.tcl"
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\program_bupt_riscv.tcl"
```

串口检查：

```text
help
perf
perf clear
bench alu
bench mem
bench branch
int on
int stat
int off
```

### 8.3 Vivado 报告检查

每个版本保存：

```text
top_timing_summary_routed.rpt
top_utilization_placed.rpt
top_power_routed.rpt
串口输出截图
benchmark 结果表
```

必须检查：

```text
WNS >= 0
TNS = 0
没有严重 DRC
没有未约束主时钟路径
UART 正常
DDR 校准正常
```

## 9. 风险和规避

| 风险 | 表现 | 规避方式 |
| --- | --- | --- |
| 中断破坏流水线精确状态 | mret 后跑飞 | 只在安全提交边界响应中断，进入 trap 时 flush |
| CSR 指令实现不完整 | boot 程序无法配置中断 | 先只支持实际用到的 CSR 指令 |
| 提频后 UART 乱码 | 波特率分频未更新 | 根据 SoC 主频重新计算 `CLKS_PER_BIT` |
| Cache 优化后 DDR 错误 | refill/writeback 状态机 bug | 先仿真固定地址读写，再跑随机访问 |
| MMIO 被 cache 缓存 | UART/GPIO/Timer 行为异常 | MMIO 地址范围必须 bypass cache |
| write-back 数据丢失 | DDR 读回旧值 | dirty/writeback/invalidate 全部验证后再启用 |
| 计数器口径混乱 | 优化前后无法比较 | 固定 benchmark、固定清零点、固定主频换算 |
| 时序假通过 | 约束漏掉派生时钟 | 检查 clock summary 和 unconstrained paths |

## 10. 最终报告建议结构

优化完成后，报告中可以按以下结构组织：

```text
1. 当前 CPU/SoC 架构概述
2. 性能基线和测量方法
3. 程序中断机制设计
   - CSR
   - trap 流程
   - timer interrupt demo
4. 主频提升
   - 关键路径
   - RTL 调整
   - timing 对比
5. 内存系统优化
   - I-Cache
   - D-Cache line/refill
   - DDR burst/store buffer
   - cache hit rate 对比
6. CPI 优化
   - 分支预测
   - stall 分类
   - benchmark 对比
7. PPA 权衡
   - 性能收益
   - 资源增加
   - 功耗估算
8. 总结和后续工作
```

一句话定位：

```text
本项目从可运行五级流水 SoC，进一步扩展为支持机器态中断、可量化性能优化、具备更完整内存层次结构的 RISC-V FPGA 软核。
```

## 11. 建议里程碑

| 里程碑 | 目标 | 主要输出 |
| --- | --- | --- |
| M0 | 建立 benchmark 和 perf clear | 串口性能表 |
| M1 | Timer interrupt 跑通 | `int on/off/stat`、CSR/trap 波形 |
| M2 | 75 MHz 稳定 | timing/utilization 对比 |
| M3 | I-Cache 跑通 | 取指 stall 降低 |
| M4 | D-Cache 多 word line | `bench mem` cycles 降低 |
| M5 | 100 MHz 稳定 | 实际运行时间下降 |
| M6 | CPI 细分优化 | CPI/stall/miss rate 对比表 |

推荐先完成 M0 和 M1。它们能让后续所有优化更容易证明，也能显著提升项目完整度。

## 12. M0-M6 实测记录（2026-07-08 build19）

本节记录 2026-07-08 对 Nexys4 DDR 实板的 M0-M6 检查结果，范围只包含 M0-M6。

结论：当前项目已经实现 M0-M6 的主要功能目标，并且 `build19` 可在 100 MHz SoC/CPU 时钟下通过 Vivado routed timing、仿真和上板串口测试。性能上仍能看到明确瓶颈：`bench alu` 主要受乘法/多周期执行 stall 影响，`bench mem` 主要受 D-Cache/DDR refill 等待影响，`bench branch` 的 branch miss rate 约 15.2%，后续仍有继续优化空间。

### 12.1 版本和验证来源

| 项目 | 记录 |
| --- | --- |
| 测试日期 | 2026-07-08 |
| FPGA 板卡 | Nexys4 DDR / `xc7a100t_0` |
| 当前 bitstream | `Verilog/build/bupt_riscv_top.bit` |
| build 目录 | `Verilog/build/bupt_riscv_opt_full_build19/` |
| routed bitstream | `Verilog/build/bupt_riscv_opt_full_build19/bupt_riscv.runs/impl_1/top.bit` |
| SHA256 | `88AD6023361F438F1D94D89FF44814AAB81A66BD23D34CF15564E2E2BD3758A1` |
| 生成时间 | 2026-07-08 17:06:06 |
| 上板串口 | `COM8`, 115200 8N1 |
| 串口日志 | `Verilog/build/board_test_m0_m6_build19_20260708_170802.log` |
| 仿真验证 | `scripts/sim_bupt_riscv.tcl` 输出 `BUPT_RISCV_SIM_DONE` |
| 上板下载 | `scripts/program_bupt_riscv.tcl` 输出 `BUPT_RISCV_PROGRAMMED=xc7a100t_0` |

说明：`build18` 是上一版有效 bitstream；实测时发现 `perf` 命令会把 shell 等待串口输入的周期混入 benchmark 快照。`build19` 在 `bench alu/mem/branch` 内部先保存完整性能计数器快照，再打印字段，因此本节性能表以 `build19` 为准。

### 12.2 M0-M6 实现状态

| 里程碑 | 路线图目标 | 当前实现情况 | 上板/报告证据 |
| --- | --- | --- | --- |
| M0 | 建立 benchmark 和 `perf clear` | 已实现。支持 `perf`, `perf clear`, `bench alu`, `bench mem`, `bench branch`；`bench` 内部输出快照字段，避免 shell idle 污染 benchmark 数据。 | 串口 `help` 列出命令；`perf clear` 返回 `OK`；三类 benchmark 连续两次可复现。 |
| M1 | Timer interrupt 跑通 | 已实现。CPU 支持最小 machine-mode CSR/trap/mret，boot shell 支持 `int on/off/stat`。 | `int on` 后 tick 从 `0x00000000` 增至 `0x000000FF`、`0x000001FE`，shell 仍可交互。 |
| M2 | 75 MHz 稳定 | 已被 100 MHz 稳定实现覆盖；未单独保留 75 MHz bitstream 表。 | `clk50_unbuf` 实际 period 10.000 ns / 100.000 MHz，routed WNS `+0.080 ns`。 |
| M3 | I-Cache 跑通 | 已实现。`icache.v` 为 64 lines、4-word line、1 KB 只读 I-Cache，miss 时整行 refill。 | Boot、自测、串口 benchmark 均通过；benchmark 中 `stall_if` 维持在几十到百周期量级。 |
| M4 | D-Cache 多 word line | 已实现。`dcache_2way_lru.v` 为 2-way、4-word line，带 hit/miss/refill 计数。 | `bench mem` 两次 cycles 为 `0x5405`、`0x540D`，misses 均为 `0x140`。 |
| M5 | 100 MHz 稳定 | 已实现。UART 分频为 868，Timer tick 配置为 100 MHz 口径。 | 上板串口 115200 无乱码；Vivado timing 全部满足。 |
| M6 | CPI 细分优化 | 已实现细分计数和实测表。当前已输出 `stall_lu/md/dc/if/ddr`、`flush_br/tr`，可定位 CPI 来源。 | `bench alu/mem/branch` 均打印 cycles/retired/stalls/branch/miss 相关字段。 |

### 12.3 build19 PPA

| 项目 | 实测/报告值 |
| --- | ---: |
| SoC/CPU clock | 100.000 MHz |
| WNS | +0.080 ns |
| TNS | 0.000 ns |
| Failing endpoints | 0 |
| LUT | 17229 / 63400 = 27.18% |
| Register | 30329 / 126800 = 23.92% |
| BRAM | 9 / 135 = 6.67% |
| DSP | 2 / 240 = 0.83% |
| Total On-Chip Power | 1.171 W |
| Dynamic Power | 1.063 W |
| Static Power | 0.108 W |
| Junction Temperature | 30.3 C |
| Power confidence | Low |

Vivado power confidence 为 Low，功耗只作为估算值和 PPA 讨论依据，不作为精确实测功耗。

### 12.4 上板功能测试

| 命令 | 结果 | 判定 |
| --- | --- | --- |
| `help` | 输出 `help mem perf perf clear bench alu bench mem bench branch cache fp led run int on off stat` | PASS |
| `mem` | `DDR TEST OK` | PASS |
| `cache` | `CACHE READY` | PASS |
| `fp` | `FP TEST OK` | PASS |
| `perf clear` | `OK` | PASS |
| `perf` | 输出 cycles/retired/branches/mispredicts/stalls 和细分 stall/flush 字段 | PASS |
| `bench alu` | 两次 cycles 均为 `0x0000A81E` | PASS |
| `bench mem` | cycles 为 `0x00005405`、`0x0000540D`，misses 均为 `0x00000140` | PASS |
| `bench branch` | branches 均为 `0x000019C8`，mispredicts 为 `0x000003ED`、`0x000003EA` | PASS |
| `int on/stat/off` | tick 从 `0x00000000` 增至 `0x000000FF`、`0x000001FE`，`int off` 返回 `INT OFF` | PASS |

`int off` 后最后一次 `int stat` 显示 `pending=00000001`，表示 timer pending 事件已经锁存；CPU/shell 未跑飞，后续命令仍可交互。

### 12.5 Benchmark 性能表

换算口径：

```text
运行时间(us) = cycles / 100,000,000 * 1,000,000
CPI = cycles / retired
IPC = retired / cycles
stall_rate = stalls / cycles
branch_miss_rate = mispredicts / branches
```

| Benchmark | runs | cycles | retired | CPI | IPC | branches | mispredicts | branch miss rate | stalls | stall rate | time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `bench alu` | avg of 2 | 43038 | 8007 | 5.375 | 0.186 | 1000 | 1.5 | 0.15% | 33011 | 76.70% | 430.38 us |
| `bench mem` | avg of 2 | 21513 | 1806 | 11.912 | 0.084 | 512 | 4.0 | 0.78% | 18651 | 86.70% | 215.13 us |
| `bench branch` | avg of 2 | 16438 | 3607 | 4.557 | 0.219 | 6600 | 1003.5 | 15.20% | 14 | 0.09% | 164.38 us |

重复性记录：

| Benchmark | run1 cycles | run2 cycles | run1 key result | run2 key result |
| --- | ---: | ---: | --- | --- |
| `bench alu` | 43038 | 43038 | mispredicts 2 | mispredicts 1 |
| `bench mem` | 21509 | 21517 | misses 320 | misses 320 |
| `bench branch` | 16439 | 16437 | mispredicts 1005 | mispredicts 1002 |

### 12.6 Stall 和 Cache 细分

| Benchmark | stall_lu | stall_md | stall_dc | stall_if | stall_ddr | flush_br | flush_tr | 主要瓶颈 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `bench alu` | 6 | 33000 | 15 | 74 | 0 | 1.5 | 0 | 乘法/多周期执行等待占主导 |
| `bench mem` | 9 | 0 | 18652 | 97.5 | 18636 | 4 | 0 | D-Cache miss/refill 与 DDR 等待占主导 |
| `bench branch` | 8 | 0 | 15 | 73 | 0 | 1003.5 | 0 | 分支预测失败带来的 flush 占主导 |

`bench mem` 固定执行 256 次 store + 256 次 load，按 512 次数据访问估算：

| 项目 | 值 |
| --- | ---: |
| data accesses | 512 |
| cache misses | 320 |
| estimated hits | 192 |
| estimated hit rate | 37.50% |
| estimated miss rate | 62.50% |

说明：cache hit rate 为按 benchmark 访问次数和硬件 miss 计数推导得到；当前串口 `bench mem` 直接打印 `misses`，未单独打印 hits/refill cycles。细分 stall 计数器为独立事件计数，可能与总 `stalls` 因同周期重叠或采样边界存在少量差异，不要求逐项相加等于总 stalls。
