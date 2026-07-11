# 题目 B 四人团队分工与协作方案

## 1. 文档目的

本文档用于北京邮电大学《项目式课程阶段二》题目 B 的团队任务划分、开发协作、过程管理和答辩准备。

当前项目在 NEXYS4 DDR 平台上实现了一个以 RV32I 为基础的五级流水 RISC-V SoC，包含流水线冒险处理、分支预测、I-Cache、2 路 LRU D-Cache、DDR、UART、GPIO、Timer、中断、性能计数器、RV32M 乘除法扩展和 FP32 MMIO 协处理器。为了让四名成员的贡献比例接近 25%，分工不能只按文件数量划分，而应同时考虑以下因素：

1. RTL 设计和调试难度。
2. 模块数量和代码规模。
3. 模块之间的集成责任。
4. 仿真、上板和性能分析工作量。
5. 报告撰写和答辩讲解工作量。

团队采用四个技术方向进行划分：

| 成员 | 技术方向 | 核心职责 | 目标占比 |
| --- | --- | --- | ---: |
| 成员 1 | CPU 指令集与执行单元 | RV32I、寄存器堆、立即数、ALU、访存格式、RV32M | 25% |
| 成员 2 | 五级流水线与冒险控制 | 流水寄存器、前递、暂停、flush、分支预测、CSR/中断流水控制 | 25% |
| 成员 3 | 存储层次与 DDR | Boot ROM、BRAM、I-Cache、D-Cache、LRU、DDR 通路 | 25% |
| 成员 4 | SoC、外设、软件与验证 | 总线、UART、GPIO、Timer、IRQ、FP32、性能计数、boot、仿真和上板 | 25% |

四名成员各自承担约 20% 的专项设计、调试和文档工作，并共同承担约 5% 的系统联调、课程报告检查和答辩演练，使最终贡献比例保持在 25% 左右。

## 2. 系统结构与责任边界

项目的主要执行路径如下：

```text
NEXYS4 DDR 顶层 top
        |
        v
       SoC
        |
        +-- RV32I 五级流水 CPU
        |     +-- 指令译码与执行
        |     +-- 数据前递与暂停
        |     +-- 分支预测与错误路径清除
        |     +-- CSR、Timer 中断和 mret
        |
        +-- 指令存储路径
        |     +-- I-Cache
        |     +-- Boot ROM
        |
        +-- 数据总线
              +-- BRAM
              +-- GPIO / UART / Timer / IRQ
              +-- 性能计数器 / FP32
              +-- D-Cache
                    +-- DDR Bridge
                          +-- MIG / DDR2
```

责任划分遵循以下原则：

- 成员 1 负责“指令执行什么操作”。
- 成员 2 负责“指令在什么时刻执行以及多条指令如何并行”。
- 成员 3 负责“指令和数据存在哪里以及如何完成存储访问”。
- 成员 4 负责“CPU、内存和外设如何组成完整系统并完成验证”。

`riscv.v` 和 `simple_bus.v` 是多人关注的核心文件，但必须设置唯一修改负责人：

- `riscv.v` 默认由成员 2 维护。成员 1 提交译码或执行单元修改需求，由成员 2 合入流水线控制。
- `simple_bus.v` 默认由成员 4 维护。成员 3 提供 Cache 和 DDR 接口变更，由成员 4 合入地址译码和总线连接。
- 未经模块负责人确认，不直接修改共享文件，以避免接口冲突和功能回归。

## 3. 成员 1：CPU 指令集与执行单元

### 3.1 工作目标

成员 1 负责 RV32I 基础指令和 RV32M 扩展的功能正确性，保证指令可以被正确译码、计算、访存和写回。该方向对应题目 B 的“设计指令集、数据通路与控制器”以及“支持算术、逻辑、访存、跳转等基本指令类型”。

### 3.2 负责模块

主要负责以下文件：

```text
src/bupt_riscv/riscv_core/alu.v
src/bupt_riscv/riscv_core/regfile.v
src/bupt_riscv/riscv_core/immgen.v
src/bupt_riscv/riscv_core/load_ext.v
src/bupt_riscv/riscv_core/store_align.v
src/bupt_riscv/riscv_core/iter_mul.v
src/bupt_riscv/riscv_core/iter_div.v
```

协同负责：

```text
src/bupt_riscv/riscv_core/riscv.v
software/bupt_riscv/gen_bupt_boot.py 中的指令编码和 ISA 自测
```

### 3.3 具体任务

1. 整理 RV32I 指令格式和控制信号表。
2. 检查 opcode、funct3 和 funct7 的译码逻辑。
3. 维护 I、S、B、U、J 五类立即数生成逻辑。
4. 维护寄存器堆双读单写接口，保证 `x0` 恒为 0。
5. 实现并验证以下基础运算：

```text
add, sub, sll, slt, sltu, xor, srl, sra, or, and
addi, slti, sltiu, xori, ori, andi, slli, srli, srai
```

6. 实现并验证 `lui`、`auipc`、`jal` 和 `jalr` 的运算数据。
7. 实现 `lb/lh/lw/lbu/lhu` 的字节选择、符号扩展和零扩展。
8. 实现 `sb/sh/sw` 的写数据对齐和 byte enable。
9. 维护 RV32M 乘除法扩展：

```text
mul, mulh, mulhsu, mulhu, div, divu, rem, remu
```

10. 验证除数为 0 和 `0x80000000 / -1` 等特殊情况。
11. 在 boot 程序中维护 RV32I、RV32M 自测用例。
12. 为答辩准备至少一张指令译码表和一张执行数据通路图。

### 3.4 输入输出接口

成员 1 向成员 2 提供：

- 指令译码所需的控制信号定义。
- ALU 操作码与具体运算的对应关系。
- 乘除法单元的 `start/busy/ready/result` 时序约定。
- load/store 对地址低两位、funct3 和写掩码的处理规则。

成员 1 从成员 2 接收：

- EX 阶段已经完成前递的两个源操作数。
- 当前流水级的有效位和暂停条件。
- 指令执行结果进入 EX/MEM 流水寄存器的时机。

### 3.5 验收标准

必须完成以下验证：

- RV32I 自测输出 `RV32I ISA PASS`。
- RV32M 自测输出 `M EXT PASS`。
- `x0` 写入后仍为 0。
- 有符号和无符号比较结果正确。
- `jal` 写回 `PC + 4`。
- `jalr` 目标地址最低位清零。
- byte、halfword 和 word 访存对齐正确。
- 乘除法特殊情况符合 RISC-V 定义。

### 3.6 报告与答辩内容

成员 1 负责报告中的以下章节：

- 指令集选择与指令格式。
- CPU 数据通路中的执行单元。
- 寄存器堆和立即数生成。
- load/store 对齐逻辑。
- RV32M 扩展设计。

答辩时应能够解释一条 `lw`、一条算术指令和一条跳转指令的数据流，以及迭代乘除法为什么会引起流水线暂停。

## 4. 成员 2：五级流水线与冒险控制

### 4.1 工作目标

成员 2 负责 IF、ID、EX、MEM、WB 五级流水线的组织和控制，确保数据冒险、控制冒险、慢速访存和中断重定向能够被正确处理。该方向对应题目 B 的“引入流水线机制”和拓展要求中的“数据前推、分支预测”。

### 4.2 负责模块

主要负责以下文件：

```text
src/bupt_riscv/riscv_core/riscv.v
src/bupt_riscv/riscv_core/branch_predictor.v
src/bupt_riscv/riscv_core/pc.v
src/bupt_riscv/riscv_core/flopr.v
src/bupt_riscv/riscv_core/flopenr.v
src/bupt_riscv/riscv_core/floprc.v
src/bupt_riscv/riscv_core/flopenrc.v
src/bupt_riscv/pipeline_demo_panel.v
```

### 4.3 具体任务

1. 维护 IF、ID、EX、MEM、WB 五级流水寄存器。
2. 维护各流水级 `valid` 信号，防止气泡和错误路径被统计为真实指令。
3. 实现 EX/MEM 和 MEM/WB 到 EX 的数据前递。
4. 实现分支和 `jalr` 在 ID/EX 路径上的操作数前递。
5. 检测 load-use 冒险，暂停 PC 和 IF/ID，并向 EX 插入气泡。
6. 处理乘除法多周期执行造成的暂停。
7. 处理 `d_ready=0` 或 `i_ready=0` 造成的数据访问和取指等待。
8. 维护分支预测器：

- 64 项直接映射 BTB。
- BHT 2 位饱和计数器。
- IF 阶段预测方向和目标。
- EX 阶段计算实际方向和目标。
- 预测错误时重定向 PC 并 flush 错误路径。

9. 处理非分支指令误命中 BTB 的恢复逻辑。
10. 维护 CSR、Timer 中断、`mtvec`、`mepc`、`mcause` 和 `mret` 的流水线行为。
11. 输出 retire、branch、mispredict、stall、flush 和 forwarding 等性能事件。
12. 准备数据冒险、控制冒险和中断冲刷的波形证据。

### 4.4 输入输出接口

成员 2 从成员 1 接收：

- 译码控制信号。
- ALU 和乘除法执行结果。
- load/store 的格式化结果。

成员 2 从成员 3 接收：

- 指令侧 `i_ready/i_rdata`。
- 数据侧 `d_ready/d_rdata`。
- Cache 或 DDR 请求未完成时的等待状态。

成员 2 向成员 4 提供：

- 数据总线请求信号。
- 中断输入接口。
- 各类性能事件脉冲。
- 流水线演示所需的各级 PC、指令和有效位。

### 4.5 验收标准

至少验证以下场景：

1. 相邻 ALU 指令通过前递得到正确结果。
2. load-use 相关恰好产生必要暂停。
3. store 数据相关可以得到正确写数据。
4. 分支预测正确时不产生额外 flush。
5. 分支预测错误时恢复到正确 PC。
6. `jal` 和 `jalr` 跳转后错误路径不产生副作用。
7. Cache 或 DDR 等待期间流水寄存器保持稳定。
8. 中断发生时保存正确 `mepc`，`mret` 后正确返回。
9. stall、mispredict、flush 和 forward 计数能够随测试场景变化。

### 4.6 报告与答辩内容

成员 2 负责报告中的以下章节：

- 五级流水线总体结构。
- 流水寄存器和有效位设计。
- 数据冒险检测与前递。
- load-use 暂停。
- 分支预测和控制冒险。
- 中断对流水线的影响。

答辩时应能够结合波形解释 stall、bubble 和 flush 的区别，并说明分支预测对 CPI、面积和关键路径的影响。

## 5. 成员 3：存储层次、Cache 与 DDR

### 5.1 工作目标

成员 3 负责指令和数据存储路径，保证 Boot ROM、BRAM、Cache 和 DDR 能够向 CPU 提供正确的数据和握手响应。该方向对应题目 B 的“内存子系统、Cache 设计或存储层次规划”以及“Cache 替换策略优化与命中率分析”。

### 5.2 负责模块

主要负责以下文件：

```text
src/bupt_riscv/boot_rom.v
src/bupt_riscv/bram_ram.v
src/bupt_riscv/icache.v
src/bupt_riscv/dcache_2way_lru.v
src/bupt_riscv/ddr_bridge.v
src/bupt_riscv/ddr_backend_cdc.v
src/bupt_riscv/mig_axi_adapter.v
src/bupt_riscv/ddr_model.v
src/bupt_riscv/mig/nexys4ddr_mig.prj
```

协同负责：

```text
src/bupt_riscv/simple_bus.v 中的存储通路连接
```

### 5.3 具体任务

1. 维护 Boot ROM 初始化和同步读时序。
2. 维护 BRAM 的 byte enable 和读写行为。
3. 维护 I-Cache：

- 64 行直接映射。
- 每行 4 个 word。
- tag、index 和 word offset 解析。
- miss 后从 Boot ROM refill 整行。
- access、hit、miss 和 refill 周期统计。

4. 维护 D-Cache：

- 16 组、2 路组相联。
- 每行 4 个 word。
- write-through 写策略。
- 无效路优先和 LRU victim 选择。
- 读 miss 的整行 refill。
- 写命中更新 Cache 并写穿 DDR。
- access、hit、miss、replacement 和 refill 周期统计。

5. 维护 Cache 清统计和 invalidate 功能。
6. 维护 DDR Bridge 的请求、等待和响应状态机。
7. 维护 CPU 时钟域到 DDR/MIG 时钟域的 CDC 通路。
8. 维护仿真使用的 DDR model 和实板使用的 MIG/AXI 适配接口。
9. 设计同组冲突地址，验证第三条 Cache line 触发 LRU 替换。
10. 分析 Cache 命中率、refill 开销和 DDR 等待周期。

### 5.4 输入输出接口

成员 3 从 CPU/总线侧接收：

- 指令地址 `i_addr`。
- 数据访问有效信号、读写方向、地址、写数据和写掩码。

成员 3 向 CPU/总线侧提供：

- 指令数据和 `i_ready`。
- load 数据和 `d_ready`。
- DDR 校准完成和忙状态。
- Cache 各类统计值。

成员 3 与成员 4 共同确认 MMIO 和 DDR 地址区域，避免普通外设访问误入 D-Cache。

### 5.5 验收标准

必须完成以下验证：

- Boot ROM 可以正确执行启动程序。
- BRAM 支持 byte、halfword 和 word 访问。
- I-Cache 首次访问产生 miss，重复访问产生 hit。
- D-Cache 重复读取产生 hit。
- 两路填满后访问第三个同组地址触发 replacement。
- LRU 被最近访问后，下一次替换选择另一条路。
- 写操作最终进入 DDR，并保持 Cache 内容一致。
- DDR 测试输出 `DDR TEST OK`。
- Cache 自测输出 `[PASS] DCACHE LRU` 和 `[PASS] ICACHE`。

### 5.6 报告与答辩内容

成员 3 负责报告中的以下章节：

- 存储地址空间与层次结构。
- I-Cache 结构和 refill 流程。
- D-Cache 结构、写策略和 LRU 算法。
- DDR Bridge 与 MIG 接口。
- Cache 命中率和访存性能分析。

答辩时应能够画出地址的 tag/index/offset 划分，并逐周期解释一次 Cache miss 从 CPU 请求到 refill 完成的过程。

## 6. 成员 4：SoC、外设、软件与系统验证

### 6.1 工作目标

成员 4 负责将 CPU、存储系统和外设集成为完整可运行系统，并负责 boot 软件、自动测试、Vivado 流程和实物上板验收。该方向对应题目 B 的“完整计算机系统设计”“基本 I/O 接口集成”“运行小型测试程序”和“性能量化评估”。

### 6.2 负责模块

主要负责以下文件：

```text
src/bupt_riscv/top.v
src/bupt_riscv/soc.v
src/bupt_riscv/simple_bus.v
src/bupt_riscv/gpio_mmio.v
src/bupt_riscv/uart_mmio.v
src/bupt_riscv/timer_mmio.v
src/bupt_riscv/irq_controller.v
src/bupt_riscv/perf_mmio.v
src/bupt_riscv/fp_mmio.v
src/bupt_riscv/acceptance_mmio.v
src/bupt_riscv/demo_clock_ctrl.v
src/common/uart_rx.v
src/common/uart_tx.v
software/bupt_riscv/gen_bupt_boot.py
sim/*.v
scripts/*.tcl
constr/nexys4ddr_bupt_riscv.xdc
```

### 6.3 具体任务

1. 维护 FPGA 顶层时钟、复位、UART、LED、按键、数码管和 DDR 引脚。
2. 维护 SoC 中 CPU、总线、DDR 后端和演示面板的连接。
3. 维护地址译码和 MMIO 映射：

| 地址区域 | 功能 |
| --- | --- |
| `0x0000_0000` | Boot ROM |
| `0x0001_0000` | BRAM |
| `0x1000_0000` | GPIO |
| `0x1000_1000` | UART |
| `0x1000_2000` | Timer |
| `0x1000_3000` | IRQ Controller |
| `0x1000_4000` | DDR Status |
| `0x1000_5000` | Performance Counters |
| `0x1000_6000` | Cache Statistics |
| `0x1000_7000` | FP32 Coprocessor |
| `0x1000_8000` | Debug Registers |
| `0x1000_9000` | Pipeline Panel |
| `0x1000_A000` | Acceptance Registers |
| `0x8000_0000` | DDR Data Region |

4. 维护 UART 收发和 Shell 命令。
5. 维护 GPIO/LED 控制。
6. 维护 Timer、IRQ Controller 和中断测试程序。
7. 维护 FP32 MMIO 加法和乘法协处理器。
8. 维护性能计数器和 `perf`、`bench` 命令。
9. 维护 boot ROM 生成器、字符串输出和自动验收程序。
10. 维护行为级 testbench，检查 UART、DDR、Cache、FP32、Timer 和性能输出。
11. 维护 Vivado 仿真、综合、实现、bitstream 和下载脚本。
12. 组织实物上板验证，保存串口日志、LED 照片、数码管显示和 Vivado 报告。

### 6.4 输入输出接口

成员 4 从成员 1 和成员 2 接收：

- CPU 指令和数据总线接口。
- IRQ 输入接口。
- retire、branch、mispredict、stall、flush 和 forward 性能事件。

成员 4 从成员 3 接收：

- Cache 的 CPU 侧握手接口。
- DDR 后端接口。
- Cache 和 DDR 状态统计。

成员 4 负责保持顶层端口、XDC 约束和构建脚本一致。

### 6.5 验收标准

必须完成以下验证：

- UART 输出完整启动日志和 `rv32>` 提示符。
- `led 1` 可以控制 LED。
- `perf` 可以输出周期、退休指令、分支、预测错误和暂停统计。
- `bench alu`、`bench mem` 和 `bench branch` 可以运行。
- FP32 自测输出 `FP TEST OK`。
- Timer 中断测试通过，`mret` 后程序继续运行。
- 自动验收输出 `ACCEPTANCE PASS`。
- Vivado 行为级仿真通过。
- 综合、布局布线和 bitstream 生成通过。
- NEXYS4 DDR 实板串口和 I/O 验证通过。

### 6.6 报告与答辩内容

成员 4 负责报告中的以下章节：

- SoC 总体结构和地址映射。
- UART、GPIO、Timer 和中断系统。
- FP32 MMIO 协处理器。
- 性能计数器和 benchmark。
- 仿真、综合、时序、资源、功耗和实物验证。

答辩时应能够从软件写 MMIO 地址开始，解释请求如何经过总线到达外设，并说明 CPI、IPC、吞吐量和 PPA 数据的获取方式。

## 7. 25% 工作量平衡方案

为避免“负责集成的人工作过多”或“负责单个模块的人贡献不足”，每个人的工作由四部分组成：

| 工作类型 | 每人建议占比 | 说明 |
| --- | ---: | --- |
| RTL/软件设计与维护 | 12% | 完成本方向核心实现和接口维护 |
| 仿真与问题定位 | 5% | 设计专项用例、检查波形、修复问题 |
| 报告与图表 | 4% | 撰写对应章节，准备结构图和实验数据 |
| 联调与答辩 | 4% | 参加完整系统验收、交叉评审和答辩演练 |
| 合计 | 25% | 四人合计 100% |

成员 4 的文件数量较多，但其中大量外设模块规模较小；成员 2 和成员 3 的文件数量较少，但流水控制和 Cache/DDR 的调试难度较高；成员 1 需要覆盖较多指令和边界条件。因此应以任务难度和验收责任衡量贡献，不按代码行数计算。

## 8. 开发和协作流程

### 8.1 接口先行

在修改模块前先记录：

- 输入输出信号名称和位宽。
- 请求和响应的有效周期。
- stall、ready、busy 的含义。
- 复位值。
- 是否允许连续请求。
- 是否跨时钟域。

涉及共享接口的修改必须由接口两侧负责人共同确认。

### 8.2 单模块验证

每名成员先完成本方向的专项验证，不依赖完整 SoC 才能发现问题。例如：

- 成员 1 使用指令序列验证 ALU 和 load/store。
- 成员 2 使用流水线场景 testbench 验证前递和 flush。
- 成员 3 使用 Cache/DDR 请求序列验证 hit、miss 和 refill。
- 成员 4 使用 MMIO testbench 验证 UART、Timer、FP32 和性能计数器。

### 8.3 系统联调

联调按照以下顺序进行：

1. CPU + Boot ROM，确认能够取指和执行基本指令。
2. CPU + BRAM，确认 load/store 正确。
3. CPU + UART/GPIO，确认软件可见 I/O 正确。
4. CPU + Timer/IRQ，确认中断进入和返回正确。
5. CPU + D-Cache + DDR model，确认慢速访存握手正确。
6. 加入性能计数器和 benchmark。
7. 运行完整自动验收 testbench。
8. 综合、实现、生成 bitstream 并上板验证。

### 8.4 问题归属原则

| 问题表现 | 第一负责人 | 协同负责人 |
| --- | --- | --- |
| 指令计算结果错误 | 成员 1 | 成员 2 |
| 相邻指令相关时结果错误 | 成员 2 | 成员 1 |
| 分支后执行了错误路径 | 成员 2 | 成员 1 |
| Cache 命中数据错误 | 成员 3 | 成员 4 |
| DDR 长时间不返回 | 成员 3 | 成员 4 |
| MMIO 地址访问错误 | 成员 4 | 成员 3 |
| UART Shell 命令错误 | 成员 4 | 对应功能负责人 |
| 仿真通过但实板失败 | 成员 4 | 成员 2、成员 3 |
| CPI 或计数关系异常 | 成员 2 | 成员 4 |

## 9. 阶段计划

### 阶段 1：需求确认与代码理解

四名成员共同阅读题目要求、工程说明和启动流程。每名成员输出本方向的模块清单、接口说明和风险点。

阶段输出：

- 四份模块说明。
- 一张系统结构图。
- 一份统一地址映射表。
- 一份统一控制和握手信号说明。

### 阶段 2：专项功能确认

各成员分别确认 RV32I/RV32M、流水线、Cache/DDR 和外设/软件功能。

阶段输出：

- ISA 自测结果。
- 流水线冒险波形。
- Cache hit/miss/LRU 测试结果。
- UART、FP32、Timer 和 perf 测试结果。

### 阶段 3：系统联调与自动验收

运行完整行为级仿真，修复跨模块接口问题。自动验收应覆盖 RV32I、RV32M、DDR、D-Cache、I-Cache、FP32、Timer IRQ 和性能计数。

阶段输出：

- 仿真成功日志。
- 自动验收输出。
- 关键波形截图。
- 问题和修复记录。

### 阶段 4：综合、实现和上板

执行 Vivado 综合、布局布线和 bitstream 生成，检查时序、资源和功耗。在 NEXYS4 DDR 上验证 UART、LED、Timer、Cache 和性能命令。

阶段输出：

- Timing Summary。
- Utilization Report。
- Power Report。
- bitstream。
- 串口日志。
- LED、数码管或开发板照片。

### 阶段 5：报告和答辩

各成员完成自己负责章节，再进行交叉检查。最终报告中的模块名称、地址、参数和性能数据必须与 RTL 一致。

阶段输出：

- 最终课程报告。
- 四人答辩讲稿。
- 系统框图、数据通路图和波形图。
- 功能演示顺序和异常处理预案。

## 10. 最终报告章节分工

建议报告结构如下：

| 报告章节 | 负责人 | 主要内容 |
| --- | --- | --- |
| 项目背景与需求分析 | 四人共同 | 题目 B 要求、目标平台、设计目标 |
| 指令集与执行数据通路 | 成员 1 | RV32I、ALU、立即数、访存格式、RV32M |
| 五级流水线与冒险处理 | 成员 2 | 流水级、前递、暂停、分支预测、中断冲刷 |
| 存储层次设计 | 成员 3 | Boot ROM、BRAM、I-Cache、D-Cache、DDR |
| SoC 与外设集成 | 成员 4 | 总线、地址映射、UART、GPIO、Timer、IRQ、FP32 |
| 性能评估 | 成员 2、4 | CPI、IPC、stall、分支预测、吞吐量 |
| Cache 实验 | 成员 3 | 命中率、miss、replacement、refill 周期 |
| PPA 分析 | 四人共同 | 频率、资源、功耗和设计取舍 |
| 仿真与实物验证 | 成员 4 统稿 | testbench、Vivado、串口和开发板证据 |
| 总结与展望 | 四人共同 | 已完成内容、限制和后续优化 |

## 11. 答辩分工与演示顺序

建议答辩顺序控制在逻辑上从 CPU 内部逐步扩展到完整系统：

1. 成员 1 介绍指令集、数据通路和 RV32M。
2. 成员 2 介绍五级流水线、数据冒险和分支预测。
3. 成员 3 介绍 I-Cache、D-Cache、LRU 和 DDR。
4. 成员 4 介绍 SoC、外设、FP32、性能统计和实物验证。

建议实物演示顺序：

```text
开发板复位
  -> 查看 UART 启动自测
  -> 执行 accept
  -> 执行 led 1
  -> 执行 cache
  -> 执行 fp
  -> 执行 int on / int stat
  -> 执行 perf
  -> 执行 bench alu / mem / branch
  -> 展示流水线面板和关键波形
```

每名成员除回答自己模块问题外，还应掌握以下公共问题：

- 系统为什么选择 RV32I。
- 为什么采用五级流水线。
- Cache 和 DDR 如何影响流水线。
- CPI 如何计算。
- 当前 FP32 为什么不是完整 F 扩展。
- 当前设计在性能、面积和功耗之间做了什么取舍。

## 12. 交付物清单

### 成员 1

- RV32I/RV32M 指令实现说明。
- 指令译码表。
- ALU 和乘除法测试结果。
- 执行数据通路图。
- 报告对应章节和答辩讲稿。

### 成员 2

- 五级流水线结构说明。
- 前递、load-use、分支预测和中断冲刷波形。
- stall/flush 控制表。
- 性能事件说明。
- 报告对应章节和答辩讲稿。

### 成员 3

- 存储层次结构图。
- I-Cache 和 D-Cache 参数表。
- LRU 测试和 Cache 统计结果。
- DDR 访问流程说明。
- 报告对应章节和答辩讲稿。

### 成员 4

- SoC 结构图和 MMIO 地址表。
- UART Shell 和 boot 自测说明。
- FP32、Timer IRQ 和 perf 测试结果。
- Vivado 仿真、综合、实现和上板证据。
- 报告对应章节和答辩讲稿。

### 团队共同交付

- 可综合的完整 RTL 工程。
- 可重复执行的 boot ROM 生成脚本。
- 行为级仿真脚本和自动验收 testbench。
- Vivado 构建和下载脚本。
- 最终 bitstream。
- 课程设计报告。
- 答辩 PPT、演示流程和问题清单。

## 13. 工作完成判定

每名成员的任务不能仅以“代码已写完”作为完成标准。满足以下条件后，才视为该成员完成自己的 25%：

1. 负责模块功能正确，接口说明完整。
2. 至少提供一个能够暴露错误的专项测试。
3. 通过完整系统回归，没有破坏其他模块。
4. 提供仿真日志、波形或实物结果作为证据。
5. 完成报告对应章节和必要图表。
6. 能够在答辩中解释设计逻辑、边界条件和取舍。
7. 参加系统联调、上板验证和交叉评审。

按照上述标准分工，四名成员分别覆盖 CPU 执行、流水控制、存储系统和 SoC 验证四个完整技术方向。每个方向都有独立设计内容、明确接口、专项测试、报告章节和答辩任务，能够较为合理地支撑每人 25% 的贡献比例。
