# BUPT 项目式课程阶段二题目 B 符合性审查

审查对象：`Verilog` 目录中的 `bupt_riscv` 独立工程  
审查日期：2026-07-09  
目标平台：NEXYS4 DDR，Vivado 2023.2  
当前结论：工程主体已经满足题目 B 的基础要求、进阶要求，并补齐流水线冒险、Cache 替换策略、乘除法扩展和浮点协处理器等拓展方向；Vivado 行为级仿真、综合、实现、bitstream 生成和 NEXYS4 DDR 上板串口验证均已通过。

## 1. 课程要求来源

根据《2026 项目式课程阶段二》题目 B，要求可归纳为三层：

1. 基础要求：设计并实现支持基本指令集的单周期或多周期 CPU；以 RISC-V RV32I 子集或自定义 ISA 为参照；完成数据通路与控制器；在 Minisys/EGO1/NEXYS4 平台综合、布局布线和硬件验证；支持算术、逻辑、访存、跳转等基本指令，能够运行简单测试程序。
2. 进阶要求：在基础 CPU 上集成内存与 I/O，构建完整可运行系统；完成 CPU、内存子系统和基本 I/O 接口集成；支持小型测试程序完整运行；分析系统性能瓶颈并提出优化方案；引入流水线机制，对时钟频率、CPI 与吞吐量进行量化评估。
3. 拓展要求：至少选择一个高性能优化方向深入实现，包括流水线冒险完整解决方案、Cache 替换策略优化、浮点或乘除法扩展、自定义 ISA 扩展、多方案 PPA 取舍分析等。

本工程已经覆盖多个拓展方向：流水线冒险完整解决方案、Cache 替换策略与命中率统计、RV32M 乘除法扩展，以及 FP32 MMIO 浮点协处理器。

## 2. 总体结论

| 审查项 | 当前状态 | 说明 |
| --- | --- | --- |
| RV32I 课程子集 CPU | 已满足 | 已实现 RV32I 常用整数、访存、跳转和分支指令。 |
| 五级流水线 | 已满足 | IF/ID/EX/MEM/WB 寄存器和控制流已在 CPU 核内实现。 |
| 数据冒险处理 | 已满足 | EX/MEM/WB 到 EX 前递，load-use stall，DDR wait-state stall 已实现。 |
| 控制冒险处理 | 已满足 | 64 项 BTB/BHT 分支预测，EX 阶段解析并 flush 错误路径。 |
| 内存与 I/O 系统 | 已满足 | Boot ROM、BRAM、DDR bridge、UART、GPIO、Timer、Perf MMIO 已集成。 |
| 仿真验证 | 已满足 | Vivado 2023.2 行为级仿真通过。 |
| 综合/实现/bitstream | 已满足 | Vivado 2023.2 clean-name rebuild 已生成 `build/bupt_riscv_top.bit`，时序满足 100 MHz。 |
| 实物硬件验证 | 已完成基础验证 | 2026-07-08 build19 已记录 NEXYS4 DDR 串口日志；报告中建议补充截图、LED 照片或视频。 |
| CPI/吞吐量/PPA 报告 | 部分满足 | 硬件计数器已支持，文档中仍需补实验数据和分析表。 |
| Cache 替换策略/乘除法/浮点 | 已满足 | 已新增 2 路 LRU D-Cache、RV32M 乘除法指令和 FP32 MMIO 协处理器，并通过 boot/testbench 验证。 |

## 3. 基础要求审查

### 3.1 RISC-V RV32I 子集

状态：已满足。

证据：

- 指令译码在 `src/bupt_riscv/riscv_core/riscv.v` 中完成，支持 `lui`、`auipc`、`jal`、`jalr`、branch、load、store、I 型 ALU 和 R 型 ALU，见 `src/bupt_riscv/riscv_core/riscv.v:120` 到 `src/bupt_riscv/riscv_core/riscv.v:178`。
- 立即数生成支持 I/S/B/U/J 五类格式，见 `src/bupt_riscv/riscv_core/immgen.v:3` 到 `src/bupt_riscv/riscv_core/immgen.v:23`。
- ALU 支持 `add/sub/sll/slt/sltu/xor/srl/sra/or/and`，见 `src/bupt_riscv/riscv_core/alu.v:10` 到 `src/bupt_riscv/riscv_core/alu.v:33`。
- load/store 对 `lb/lh/lw/lbu/lhu` 与 `sb/sh/sw` 做了对齐和扩展处理，见 `src/bupt_riscv/riscv_core/load_ext.v:3` 和 `src/bupt_riscv/riscv_core/store_align.v:3`。
- 寄存器堆写口屏蔽 `x0`，读口也固定返回 0，保证软件可见的 `x0` 恒为 0，见 `src/bupt_riscv/riscv_core/regfile.v`。

### 3.2 算术、逻辑、访存、跳转测试程序

状态：已满足。

证据：

- 启动镜像生成器定义了 RV32I 指令编码函数，见 `software/bupt_riscv/gen_bupt_boot.py:72` 到 `software/bupt_riscv/gen_bupt_boot.py:132`。
- 启动程序包含 ISA 测试、DDR 测试和 shell，见 `software/bupt_riscv/gen_bupt_boot.py:174`、`software/bupt_riscv/gen_bupt_boot.py:251`、`software/bupt_riscv/gen_bupt_boot.py:277`。
- 预期启动输出包括 `BUPT RISC-V CPU PROJECT`、`RV32I ISA PASS`、`DDR TEST OK`、`PERF READY`，见 `software/bupt_riscv/gen_bupt_boot.py:448` 到 `software/bupt_riscv/gen_bupt_boot.py:453`。

## 4. 进阶要求审查

### 4.1 完整 SoC、内存与 I/O 集成

状态：已满足。

证据：

- `soc.v` 将 RISC-V CPU、boot ROM、总线和外设连接起来，见 `src/bupt_riscv/soc.v:43` 到 `src/bupt_riscv/soc.v:100`。
- `simple_bus.v` 地址映射包括 BRAM、GPIO、UART、Timer、Perf MMIO 和 DDR，见 `src/bupt_riscv/simple_bus.v:47` 到 `src/bupt_riscv/simple_bus.v:54`。
- DDR 通路通过 `ddr_bridge` 接入，见 `src/bupt_riscv/simple_bus.v:157` 到 `src/bupt_riscv/simple_bus.v:187`。
- 性能计数器 MMIO 地址位于 `0x1000_5000`，见 `src/bupt_riscv/simple_bus.v:53` 和 `src/bupt_riscv/perf_mmio.v:41` 到 `src/bupt_riscv/perf_mmio.v:45`。

### 4.2 五级流水线

状态：已满足。

证据：

- IF 阶段 PC 更新和预测取指，见 `src/bupt_riscv/riscv_core/riscv.v:45` 到 `src/bupt_riscv/riscv_core/riscv.v:51`。
- IF/ID 流水寄存器，见 `src/bupt_riscv/riscv_core/riscv.v:61` 到 `src/bupt_riscv/riscv_core/riscv.v:66`。
- ID/EX 流水寄存器，见 `src/bupt_riscv/riscv_core/riscv.v:210` 到 `src/bupt_riscv/riscv_core/riscv.v:233`。
- EX/MEM 流水寄存器，见 `src/bupt_riscv/riscv_core/riscv.v:305` 到 `src/bupt_riscv/riscv_core/riscv.v:314`。
- MEM/WB 流水寄存器，见 `src/bupt_riscv/riscv_core/riscv.v:324` 到 `src/bupt_riscv/riscv_core/riscv.v:332`。

### 4.3 性能量化基础

状态：硬件已满足，报告还需补充。

证据：

- 计数器包括 cycle、retired instruction、branch、mispredict、stall，见 `src/bupt_riscv/perf_mmio.v:17` 到 `src/bupt_riscv/perf_mmio.v:35`。
- shell 的 `perf` 命令会读取并打印这些计数器，见 `software/bupt_riscv/gen_bupt_boot.py:320` 到 `software/bupt_riscv/gen_bupt_boot.py:338`。
- 仿真 testbench 检查了 `cycles=`、`retired=`、`branches=`、`mispredicts=`、`stalls=` 输出，见 `sim/bupt_riscv_tb.v:263` 到 `sim/bupt_riscv_tb.v:274`。

需要补充到课程报告：

- 综合后的最高时钟频率或时序裕量。
- `perf` 命令输出截图，并计算 CPI = cycles / retired。
- 至少比较一个场景，例如含分支循环程序与普通顺序程序的 stall 和 mispredict 差异。
- PPA 说明：分支预测器、前递网络、2 路 LRU D-Cache、RV32M 乘除法和 FP32 协处理器增加面积与功耗，但降低访存/控制冒险成本并提升计算能力；DDR 等待冻结牺牲吞吐但保证访存正确性。

## 5. 拓展要求审查

### 5.1 数据前递与 load-use 暂停

状态：已满足。

证据：

- EX 阶段从 MEM/WB 前递到 ALU 输入，见 `src/bupt_riscv/riscv_core/riscv.v:251` 到 `src/bupt_riscv/riscv_core/riscv.v:269`。
- load-use hazard 检测并暂停 IF/ID，同时 flush EX，见 `src/bupt_riscv/riscv_core/riscv.v:339` 到 `src/bupt_riscv/riscv_core/riscv.v:345`。
- DDR 或其他慢速访存 `d_ready=0` 时冻结流水线，见 `src/bupt_riscv/riscv_core/riscv.v:317` 和 `src/bupt_riscv/riscv_core/riscv.v:324` 到 `src/bupt_riscv/riscv_core/riscv.v:332`。

### 5.2 分支预测与错误路径 flush

状态：已满足。

证据：

- 分支目标为 `PC + imm`，`jalr` 目标地址最低位清零，见 `src/bupt_riscv/riscv_core/riscv.v:290` 到 `src/bupt_riscv/riscv_core/riscv.v:293`。
- 预测错误时重定向 PC 并 flush 错误路径，见 `src/bupt_riscv/riscv_core/riscv.v:296` 到 `src/bupt_riscv/riscv_core/riscv.v:300` 和 `src/bupt_riscv/riscv_core/riscv.v:344` 到 `src/bupt_riscv/riscv_core/riscv.v:345`。
- 64 项直接映射 BTB/BHT 和 2 位饱和计数器，见 `src/bupt_riscv/riscv_core/branch_predictor.v:15` 到 `src/bupt_riscv/riscv_core/branch_predictor.v:18`、`src/bupt_riscv/riscv_core/branch_predictor.v:26`、`src/bupt_riscv/riscv_core/branch_predictor.v:42` 到 `src/bupt_riscv/riscv_core/branch_predictor.v:44`。

### 5.3 Cache 替换策略与命中率统计

状态：已满足。

证据：

- 新增 `src/bupt_riscv/dcache_2way_lru.v`，实现 16 组 2 路组相联 D-Cache，4-word cache line，write-through 写策略，LRU victim 选择。
- Cache 位于 DDR 通路前，只缓存 `0x8000_0000` DDR 区域，不影响 boot ROM、BRAM、UART、GPIO 等本地 MMIO。
- 新增 Cache MMIO 地址 `0x1000_6000`，可读取 accesses、hits、misses、replacements、结构信息和替换策略；写 `0x1000_601c` 可清统计并 invalidate cache line。
- boot 自测 `cache_test` 会构造同组 3 个地址，验证 2 路填充、第三个地址触发 LRU replacement，并检查 hit/miss/replacement 计数。
- 串口启动和 shell 命令均会输出 `CACHE READY`。

### 5.4 RV32M 乘除法扩展

状态：已满足。

证据：

- `src/bupt_riscv/riscv_core/riscv.v` 对 R 型 `funct7=0000001` 译码为 RV32M 指令。
- `src/bupt_riscv/riscv_core/alu.v` 支持 `mul`、`mulh`、`mulhsu`、`mulhu`、`div`、`divu`、`rem`、`remu`，包含除零和 `0x80000000 / -1` 的 RISC-V 特殊结果。
- boot 自测 `run_m_tests` 覆盖乘法、有符号/无符号除法和取余。
- 串口启动输出 `M EXT PASS`。

### 5.5 浮点协处理器

状态：已满足。

证据：

- 新增 `src/bupt_riscv/fp_mmio.v`，在 `0x1000_7000` 提供 FP32 MMIO 协处理器。
- 当前支持正规格化 IEEE-754 single precision 的加法和乘法，适合作为课程级浮点硬件扩展演示。
- boot 自测写入 `1.5 + 2.25 = 3.75` 和 `1.5 * 2.0 = 3.0` 的 FP32 bit pattern，读回结果并断言。
- 串口启动和 shell 命令均会输出 `FP TEST OK`。

## 6. Vivado 与验证审查

### 6.1 仿真

状态：已满足。

已在 Vivado 2023.2 中重新运行：

```powershell
cmd /c "call ""D:\Xilinx\Vivado\2023.2\settings64.bat"" && vivado -mode batch -source scripts\sim_bupt_riscv.tcl"
```

结果：

```text
Simulation succeeded: BUPT RISC-V CPU verified
BUPT_RISCV_SIM_DONE
```

脚本证据：

- 仿真脚本创建 Vivado 工程、加载 RISC-V RTL 和 testbench，见 `scripts/sim_bupt_riscv.tcl:8` 到 `scripts/sim_bupt_riscv.tcl:24`。
- 脚本检查成功标志，见 `scripts/sim_bupt_riscv.tcl:35` 到 `scripts/sim_bupt_riscv.tcl:40`。
- testbench 检查 UART 启动输出、DDR、LED 和 perf 命令，见 `sim/bupt_riscv_tb.v:237` 到 `sim/bupt_riscv_tb.v:276`。

### 6.2 综合、实现与 bitstream

状态：已满足。

证据：

- 构建脚本面向 `xc7a100tcsg324-1`，即 NEXYS4 DDR 所用 Artix-7 器件，见 `scripts/build_bupt_riscv.tcl:6`。
- 构建脚本加载 `nexys4ddr_bupt_riscv.xdc` 并执行到 `write_bitstream`，见 `scripts/build_bupt_riscv.tcl:20` 和 `scripts/build_bupt_riscv.tcl:30`。
- 已于 2026-07-09 16:05 完成 clean-name rebuild 实现和 bitstream 生成，当前目录存在最终 bit 文件：`build/bupt_riscv_top.bit`。
- Vivado 成功日志显示 `Bitgen Completed Successfully`，并输出 `BUPT_RISCV_BITSTREAM=D:/CodeProject/Verilog_Project/COCP/Verilog/build/bupt_riscv_top.bit`。
- 时序满足 100 MHz：clean-name rebuild routed WNS = +0.080 ns，TNS = 0.000 ns；SoC/CPU clock = 100.000 MHz。
- 资源占用：Slice LUTs 17229/63400（27.18%），Slice Registers 30329/126800（23.92%），Block RAM Tile 9/135（6.67%），DSP 2/240（0.83%）。
- 功耗估计：Total On-Chip Power 1.171 W，Dynamic Power 1.063 W，Device Static Power 0.108 W。
- 精简构建摘要见 `docs/bupt_riscv_build_summary.md`。

建议补证据：

- 保存 Vivado implementation 完成截图。
- 课程报告中引用 `docs/bupt_riscv_build_summary.md` 的时序、资源、功耗数据。

### 6.3 实物上板

状态：已完成基础上板验收，报告中建议整理截图和照片。

下载脚本已经准备好：

- `scripts/program_bupt_riscv.tcl` 会打开硬件管理器、连接目标设备并下载 bit，见 `scripts/program_bupt_riscv.tcl:9`、`scripts/program_bupt_riscv.tcl:16`、`scripts/program_bupt_riscv.tcl:31`。
- 成功后会打印 `BUPT_RISCV_PROGRAMMED=... BITSTREAM=...`，见 `scripts/program_bupt_riscv.tcl:46`。

已记录的验收步骤：

1. 用 USB 连接 NEXYS4 DDR。
2. 运行下载命令。
3. 打开串口，波特率 115200，8N1。
4. 保存串口输出：

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

5. 输入 `led 1`，保存 LED0 点亮照片或视频。
6. 输入 `perf`，保存性能计数器输出截图。

## 7. 文件清单

核心工程文件：

- `src/bupt_riscv/top.v`：NEXYS4 DDR 顶层。
- `src/bupt_riscv/soc.v`：SoC 集成。
- `src/bupt_riscv/simple_bus.v`：地址译码和外设总线。
- `src/bupt_riscv/riscv_core/riscv.v`：RV32I 五级流水 CPU。
- `src/bupt_riscv/riscv_core/alu.v`：ALU。
- `src/bupt_riscv/riscv_core/immgen.v`：立即数生成。
- `src/bupt_riscv/riscv_core/load_ext.v`：load 数据扩展。
- `src/bupt_riscv/riscv_core/store_align.v`：store 写掩码和数据对齐。
- `src/bupt_riscv/riscv_core/branch_predictor.v`：BTB/BHT 分支预测。
- `src/bupt_riscv/perf_mmio.v`：性能计数器 MMIO。
- `src/bupt_riscv/dcache_2way_lru.v`：2 路 LRU D-Cache。
- `src/bupt_riscv/fp_mmio.v`：FP32 MMIO 浮点协处理器。
- `software/bupt_riscv/gen_bupt_boot.py`：RISC-V boot ROM 生成器。
- `sim/bupt_riscv_tb.v`：行为级验收 testbench。
- `scripts/sim_bupt_riscv.tcl`：Vivado 仿真脚本。
- `scripts/build_bupt_riscv.tcl`：Vivado 综合实现脚本。
- `scripts/program_bupt_riscv.tcl`：NEXYS4 下载脚本。
- `constr/nexys4ddr_bupt_riscv.xdc`：NEXYS4 DDR 约束。
- `build/bupt_riscv_top.bit`：运行 `scripts/build_bupt_riscv.tcl` 后生成的 bitstream。

## 8. 最终评分风险与建议

高优先级：

1. 整理实物上板证据。已有串口日志，报告中建议补充截图和 LED 照片或视频。
2. 整理实测 CPI/吞吐量截图。当前硬件和 shell 已支持 `perf` 与 `bench`，报告中需要贴一次上板输出并计算 CPI。
3. 保存 Vivado 报告。包括 utilization、timing summary、综合实现成功截图。

中优先级：

1. 可在报告中单独说明：Cache 采用小容量 2 路 LRU，是为了在资源可控前提下展示替换策略和命中率统计；浮点采用 MMIO 协处理器而非完整 RISC-V F 扩展，是为了避免引入独立浮点寄存器堆和复杂异常状态。
2. 可把 Cache 统计和 `perf` 输出整理成一张性能实验表，便于答辩时说明命中率、CPI 和 PPA。
3. 可把仿真日志、串口日志、性能数据整理到 `docs/bupt_riscv/`，便于提交。

## 9. 审查结论

从代码实现和 Vivado 行为级仿真看，当前工程已经具备题目 B 要求的 CPU、RV32I 子集、五级流水线、内存与 I/O、DDR 测试、UART shell、性能计数器、流水线冒险优化、Cache LRU 替换、RV32M 乘除法和 FP32 浮点协处理器。  

严格按课程验收口径，当前已经具备 NEXYS4 DDR 实物串口运行记录；性能/PPA 的基础数据已经在 `docs/CPU_OPTIMIZATION_ROADMAP.md` 和 `docs/bupt_riscv_build_summary.md` 中补齐，报告中再贴串口 `perf`/`bench` 输出并计算 CPI 即可。
