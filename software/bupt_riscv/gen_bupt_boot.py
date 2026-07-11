#!/usr/bin/env python3
"""生成 BUPT RV32I SoC 的 Boot ROM 镜像。

这个脚本不是普通的 PC 端测试程序，而是一个“极简汇编器 + ROM 生成器”。
它用 Python 函数逐条拼出 RISC-V 机器码，生成
src/bupt_riscv/bupt_riscv_boot.mem。硬件里的 boot_rom.v 会用 $readmemh
把这个 mem 文件装入 FPGA Boot ROM。上板复位后，CPU 实际执行的就是
这里生成的启动自检、UART shell、benchmark 和中断演示程序。
"""
from pathlib import Path

# Boot ROM 深度，单位是 32-bit word。需要和 src/bupt_riscv/boot_rom.v 保持一致。
BOOT_WORDS = 4096

# SoC 的 MMIO 地址映射。这里的常量必须和 src/bupt_riscv/simple_bus.v 的
# 地址译码一致，否则 boot 程序会访问到错误外设。
GPIO_BASE = 0x10000000
UART_BASE = 0x10001000
TIMER_BASE = 0x10002000
IRQ_BASE = 0x10003000
DDR_STATUS_BASE = 0x10004000
PERF_BASE = 0x10005000
CACHE_BASE = 0x10006000
FP_BASE = 0x10007000
DEBUG_BASE = 0x10008000
PANEL_BASE = 0x10009000
ACCEPT_BASE = 0x1000A000
DDR_BASE = 0x80000000
BRAM_BASE = 0x00010000

# Boot 程序在 BRAM 中预留的工作区。CMD_BUF 保存串口命令行，
# SNAP_BASE 保存 benchmark 结束瞬间的性能计数器快照。
CMD_BUF = BRAM_BASE + 0x500
SNAP_BASE = BRAM_BASE + 0x600
SNAP_CACHE_ACCESS = 0x40
SNAP_CACHE_HITS = 0x44
SNAP_CACHE_MISSES = 0x48
SNAP_CACHE_REPLACEMENTS = 0x4C
SNAP_ICACHE_ACCESS = 0x50
SNAP_ICACHE_HITS = 0x54
SNAP_ICACHE_MISSES = 0x58

# UART MMIO 内部寄存器偏移。STATUS bit0 是 tx_ready，bit1 是 rx_valid。
UART_TXDATA = 0x0
UART_RXDATA = 0x4
UART_STATUS = 0x8

# RISC-V ABI 寄存器别名表，后面发射指令时可以直接写 "t0"、"a0"、"sp"。
REG = {f"x{i}": i for i in range(32)}
REG.update({
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21,
    "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
})

# prog 是最终写入 ROM 的机器码数组；labels/fixups 实现“先占位、后回填”的
# 标签解析；listing 用来生成 gen_bupt_boot.lst，便于对照地址和汇编。
prog = []
labels = {}
fixups = []
listing = []


def pc():
    # 当前 ROM 写入地址，单位是 byte。RV32I/RV32M 指令固定 4 字节。
    return len(prog) * 4


def label(name):
    # 给当前位置打标签，供 branch/jal/la 等伪指令后续回填目标地址。
    labels[name] = pc()
    listing.append((None, None, f"{name}:"))


def emit(word, asm):
    # 追加一条 32-bit 机器码，并在 listing 中记录可读的汇编文本。
    prog.append(word & 0xFFFFFFFF)
    listing.append((pc() - 4, word & 0xFFFFFFFF, asm))


def pad_to(address):
    if pc() > address:
        raise SystemExit(f"boot layout exceeded reserved address 0x{address:04x}: pc=0x{pc():04x}")
    while pc() < address:
        emit(0, "pad")


# 下面六个函数分别编码 R/I/S/B/U/J 指令格式，只做 bit-field 拼接。
# 具体的 add/lw/beq 等函数会调用它们，形成更易读的“汇编 DSL”。
def r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return ((funct7 & 0x7F) << 25) | (REG[rs2] << 20) | (REG[rs1] << 15) | ((funct3 & 7) << 12) | (REG[rd] << 7) | opcode


def i(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xFFF) << 20) | (REG[rs1] << 15) | ((funct3 & 7) << 12) | (REG[rd] << 7) | opcode


def s(imm, rs2, rs1, funct3):
    return (((imm >> 5) & 0x7F) << 25) | (REG[rs2] << 20) | (REG[rs1] << 15) | ((funct3 & 7) << 12) | ((imm & 0x1F) << 7) | 0x23


def benc(imm, rs2, rs1, funct3):
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (REG[rs2] << 20) | (REG[rs1] << 15) | ((funct3 & 7) << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def u(imm, rd, opcode):
    return (imm & 0xFFFFF000) | (REG[rd] << 7) | opcode


def jenc(imm, rd):
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (REG[rd] << 7) | 0x6F


# RV32I/RV32M 常用指令包装。调用这些函数相当于向 Boot ROM 发射一条指令。
def add(rd, rs1, rs2): emit(r(0, rs2, rs1, 0, rd), f"add {rd},{rs1},{rs2}")
def sub(rd, rs1, rs2): emit(r(0x20, rs2, rs1, 0, rd), f"sub {rd},{rs1},{rs2}")
def sll(rd, rs1, rs2): emit(r(0, rs2, rs1, 1, rd), f"sll {rd},{rs1},{rs2}")
def slt(rd, rs1, rs2): emit(r(0, rs2, rs1, 2, rd), f"slt {rd},{rs1},{rs2}")
def sltu(rd, rs1, rs2): emit(r(0, rs2, rs1, 3, rd), f"sltu {rd},{rs1},{rs2}")
def xor(rd, rs1, rs2): emit(r(0, rs2, rs1, 4, rd), f"xor {rd},{rs1},{rs2}")
def srl(rd, rs1, rs2): emit(r(0, rs2, rs1, 5, rd), f"srl {rd},{rs1},{rs2}")
def sra(rd, rs1, rs2): emit(r(0x20, rs2, rs1, 5, rd), f"sra {rd},{rs1},{rs2}")
def or_(rd, rs1, rs2): emit(r(0, rs2, rs1, 6, rd), f"or {rd},{rs1},{rs2}")
def and_(rd, rs1, rs2): emit(r(0, rs2, rs1, 7, rd), f"and {rd},{rs1},{rs2}")
def mul(rd, rs1, rs2): emit(r(1, rs2, rs1, 0, rd), f"mul {rd},{rs1},{rs2}")
def mulh(rd, rs1, rs2): emit(r(1, rs2, rs1, 1, rd), f"mulh {rd},{rs1},{rs2}")
def mulhsu(rd, rs1, rs2): emit(r(1, rs2, rs1, 2, rd), f"mulhsu {rd},{rs1},{rs2}")
def mulhu(rd, rs1, rs2): emit(r(1, rs2, rs1, 3, rd), f"mulhu {rd},{rs1},{rs2}")
def div(rd, rs1, rs2): emit(r(1, rs2, rs1, 4, rd), f"div {rd},{rs1},{rs2}")
def divu(rd, rs1, rs2): emit(r(1, rs2, rs1, 5, rd), f"divu {rd},{rs1},{rs2}")
def rem(rd, rs1, rs2): emit(r(1, rs2, rs1, 6, rd), f"rem {rd},{rs1},{rs2}")
def remu(rd, rs1, rs2): emit(r(1, rs2, rs1, 7, rd), f"remu {rd},{rs1},{rs2}")


def addi(rd, rs1, imm): emit(i(imm, rs1, 0, rd, 0x13), f"addi {rd},{rs1},{imm}")
def slti(rd, rs1, imm): emit(i(imm, rs1, 2, rd, 0x13), f"slti {rd},{rs1},{imm}")
def sltiu(rd, rs1, imm): emit(i(imm, rs1, 3, rd, 0x13), f"sltiu {rd},{rs1},{imm}")
def xori(rd, rs1, imm): emit(i(imm, rs1, 4, rd, 0x13), f"xori {rd},{rs1},{imm}")
def ori(rd, rs1, imm): emit(i(imm, rs1, 6, rd, 0x13), f"ori {rd},{rs1},{imm}")
def andi(rd, rs1, imm): emit(i(imm, rs1, 7, rd, 0x13), f"andi {rd},{rs1},{imm}")
def slli(rd, rs1, sh): emit(i(sh, rs1, 1, rd, 0x13), f"slli {rd},{rs1},{sh}")
def srli(rd, rs1, sh): emit(i(sh, rs1, 5, rd, 0x13), f"srli {rd},{rs1},{sh}")
def srai(rd, rs1, sh): emit(i(0x400 | sh, rs1, 5, rd, 0x13), f"srai {rd},{rs1},{sh}")


def lb(rd, off, rs1): emit(i(off, rs1, 0, rd, 0x03), f"lb {rd},{off}({rs1})")
def lh(rd, off, rs1): emit(i(off, rs1, 1, rd, 0x03), f"lh {rd},{off}({rs1})")
def lw(rd, off, rs1): emit(i(off, rs1, 2, rd, 0x03), f"lw {rd},{off}({rs1})")
def lbu(rd, off, rs1): emit(i(off, rs1, 4, rd, 0x03), f"lbu {rd},{off}({rs1})")
def lhu(rd, off, rs1): emit(i(off, rs1, 5, rd, 0x03), f"lhu {rd},{off}({rs1})")
def sb(rs2, off, rs1): emit(s(off, rs2, rs1, 0), f"sb {rs2},{off}({rs1})")
def sh(rs2, off, rs1): emit(s(off, rs2, rs1, 1), f"sh {rs2},{off}({rs1})")
def sw(rs2, off, rs1): emit(s(off, rs2, rs1, 2), f"sw {rs2},{off}({rs1})")


def lui(rd, imm20): emit(u(imm20 << 12, rd, 0x37), f"lui {rd},0x{imm20:x}")
def auipc(rd, imm20): emit(u(imm20 << 12, rd, 0x17), f"auipc {rd},0x{imm20:x}")
def jalr(rd, off, rs1): emit(i(off, rs1, 0, rd, 0x67), f"jalr {rd},{off}({rs1})")
def nop(): addi("zero", "zero", 0)


def branch(name, rs1, rs2, target):
    # 分支目标可能还没定义，所以先写入 0 占位，等所有 label 收集完再回填。
    funct3 = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}[name]
    fixups.append((len(prog), "branch", target, rs1, rs2, funct3))
    emit(0, f"{name} {rs1},{rs2},{target}")


def beq(rs1, rs2, target): branch("beq", rs1, rs2, target)
def bne(rs1, rs2, target): branch("bne", rs1, rs2, target)
def blt(rs1, rs2, target): branch("blt", rs1, rs2, target)
def bge(rs1, rs2, target): branch("bge", rs1, rs2, target)
def bltu(rs1, rs2, target): branch("bltu", rs1, rs2, target)
def bgeu(rs1, rs2, target): branch("bgeu", rs1, rs2, target)


def jal(rd, target):
    # jal 的目标也走 fixup 机制，最后根据 label 计算相对偏移。
    fixups.append((len(prog), "jal", target, rd, None, None))
    emit(0, f"jal {rd},{target}")


def j(target): jal("zero", target)
def call(target): jal("ra", target)
def ret(): jalr("zero", 0, "ra")


# Machine mode CSR 地址。这里只用最小的一组 CSR 来做 timer interrupt 演示。
CSR_MSTATUS = 0x300
CSR_MIE     = 0x304
CSR_MTVEC   = 0x305
CSR_MEPC    = 0x341
CSR_MCAUSE  = 0x342
CSR_MIP     = 0x344
MSTATUS_MIE  = 1 << 3
MSTATUS_MPIE = 1 << 7
MIE_MEIE     = 1 << 11


def _csr(csr, rs1, funct3, rd):
    # CSR 指令编码，用于设置 mtvec/mie/mstatus，并在中断处理结束后 mret。
    return ((csr & 0xFFF) << 20) | (REG[rs1] << 15) | ((funct3 & 7) << 12) | (REG[rd] << 7) | 0x73


def csrrw(rd, csr, rs1): emit(_csr(csr, rs1, 1, rd), f"csrrw {rd},{csr:#x},{rs1}")
def csrrs(rd, csr, rs1): emit(_csr(csr, rs1, 2, rd), f"csrrs {rd},{csr:#x},{rs1}")
def csrrc(rd, csr, rs1): emit(_csr(csr, rs1, 3, rd), f"csrrc {rd},{csr:#x},{rs1}")
def csrrwi(rd, csr, imm): emit(((csr & 0xFFF) << 20) | ((imm & 0x1F) << 15) | (5 << 12) | (REG[rd] << 7) | 0x73, f"csrrwi {rd},{csr:#x},{imm}")
def csrrsi(rd, csr, imm): emit(((csr & 0xFFF) << 20) | ((imm & 0x1F) << 15) | (6 << 12) | (REG[rd] << 7) | 0x73, f"csrrsi {rd},{csr:#x},{imm}")
def csrrci(rd, csr, imm): emit(((csr & 0xFFF) << 20) | ((imm & 0x1F) << 15) | (7 << 12) | (REG[rd] << 7) | 0x73, f"csrrci {rd},{csr:#x},{imm}")
def mret(): emit(0x30200073, "mret")


def li(rd, value):
    # 伪指令 li：小常数直接 addi，较大常数拆成 lui + addi。
    # lo 可能为负数，所以这里按 RISC-V 常见规则给 hi 先加 0x800 做修正。
    value &= 0xFFFFFFFF
    hi = (value + 0x800) >> 12
    lo = value - ((hi & 0xFFFFF) << 12)
    if hi & 0xFFFFF:
        lui(rd, hi & 0xFFFFF)
        if lo:
            addi(rd, rd, lo)
    else:
        addi(rd, "zero", lo)


def la(rd, target):
    # 伪指令 la：生成两条占位指令，最后按 label 的绝对地址回填高 20 位和低 12 位。
    fixups.append((len(prog), "la_hi", target, rd, None, None))
    emit(0, f"lui {rd},%hi({target})")
    fixups.append((len(prog), "la_lo", target, rd, None, None))
    emit(0, f"addi {rd},{rd},%lo({target})")


def expect(reg, value, fail_label="isa_fail"):
    # 自检断言：比较寄存器值和期望值，不相等就跳到失败处理标签。
    li("t6", value)
    bne(reg, "t6", fail_label)


def puts_label(name):
    # 输出字符串：先把字符串 label 地址放入 a0，再调用 ROM 中的 puts 子程序。
    la("a0", name)
    call("puts")


def wait_fp_ready(label_name):
    # FP MMIO 的 ready 寄存器在 FP_BASE+0x10。写入操作数和 op 后轮询到非零。
    label(label_name)
    lw("t2", 16, "t0")
    beq("t2", "zero", label_name)


def print_perf_field(msg_label, offset):
    # perf 命令打印一个性能字段：字段名 + PERF_BASE 对应偏移的 32-bit 十六进制值。
    puts_label(msg_label)
    li("t0", PERF_BASE)
    lw("a0", offset, "t0")
    call("print_hex")


# 性能计数器输出字段。偏移含义对应 src/bupt_riscv/perf_mmio.v 的读寄存器表：
# cycles、retired、branches、mispredicts、各类 stall 和 flush 计数。
PERF_SNAPSHOT_FIELDS = [
    ("msg_cycles", 0),
    ("msg_retired", 4),
    ("msg_branch", 8),
    ("msg_misp", 12),
    ("msg_stall", 16),
    ("msg_stall_lu", 20),
    ("msg_stall_md", 24),
    ("msg_stall_dc", 28),
    ("msg_stall_if", 32),
    ("msg_stall_ddr", 36),
    ("msg_flush_br", 40),
    ("msg_flush_tr", 44),
    ("msg_forwards", 48),
]


def snapshot_perf():
    # benchmark 结束后先把性能计数器复制到 BRAM。
    # 这样后续 UART 打印本身产生的指令退休和 stall 不会污染 benchmark 数据。
    li("t0", PERF_BASE)
    li("t1", SNAP_BASE)
    for _, offset in PERF_SNAPSHOT_FIELDS:
        lw("t2", offset, "t0")
        sw("t2", offset, "t1")


def snapshot_cache_stats():
    # benchmark 结束后保存 D/I-Cache 统计，避免 UART 输出继续扰动 I-Cache 数据。
    li("t0", CACHE_BASE)
    li("t1", SNAP_BASE)
    for source_offset, snapshot_offset in (
        (0x00, SNAP_CACHE_ACCESS),
        (0x04, SNAP_CACHE_HITS),
        (0x08, SNAP_CACHE_MISSES),
        (0x0C, SNAP_CACHE_REPLACEMENTS),
        (0x20, SNAP_ICACHE_ACCESS),
        (0x24, SNAP_ICACHE_HITS),
        (0x28, SNAP_ICACHE_MISSES),
    ):
        lw("t2", source_offset, "t0")
        sw("t2", snapshot_offset, "t1")


def print_snapshot_field(msg_label, offset):
    # 从 BRAM 快照区打印一个 benchmark 字段。
    puts_label(msg_label)
    li("t0", SNAP_BASE)
    lw("a0", offset, "t0")
    call("print_hex")


def print_snapshot_tail(skip_offsets=()):
    # 打印快照中的其余字段；skip_offsets 用来避免重复打印 benchmark 的主指标。
    skip = set(skip_offsets)
    for msg_label, offset in PERF_SNAPSHOT_FIELDS:
        if offset not in skip:
            print_snapshot_field(msg_label, offset)


# Boot ROM 入口。复位后 PC 从 0 取指，首先设置栈，然后依次运行启动自检。
# 每个自检成功后会通过 UART 打印一行 PASS/OK/READY；失败则进入对应 fail 死循环。
label("_start")
li("sp", BRAM_BASE + 0x1000)
li("t0", PANEL_BASE)
lw("t1", 0, "t0")
li("t2", 0x8000)
and_("t1", "t1", "t2")
bne("t1", "zero", "pipeline_demo_entry")
puts_label("msg_banner")
call("run_isa_tests")
puts_label("msg_isa_pass")
call("run_m_tests")
puts_label("msg_m_pass")
call("ddr_test")
call("cache_test")
call("fp_test")
puts_label("msg_perf_ready")
call("print_prompt")
j("shell_loop")

# 演示模式按 PANEL_BASE 的 SW[6:3] 分派确定性场景。每个场景执行一轮后
# 回到分派器，因此拨动开关后只需继续单步或运行即可切换。
label("pipeline_demo_entry")
li("s0", BRAM_BASE + 0x200)
li("s1", 0)
li("t0", 0x10)
sw("t0", 0, "s0")

label("pipeline_demo_dispatch")
li("t0", PANEL_BASE)
lw("t1", 0, "t0")
srli("t1", "t1", 3)
andi("t1", "t1", 0x0F)
li("t2", 0)
beq("t1", "t2", "pipeline_demo_mixed")
li("t2", 1)
beq("t1", "t2", "pipeline_demo_forward")
li("t2", 2)
beq("t1", "t2", "pipeline_demo_loaduse")
li("t2", 3)
beq("t1", "t2", "pipeline_demo_muldiv")
li("t2", 4)
beq("t1", "t2", "pipeline_demo_branch")
li("t2", 5)
beq("t1", "t2", "pipeline_demo_dcache")
li("t2", 6)
beq("t1", "t2", "pipeline_demo_icache")
li("t2", 7)
beq("t1", "t2", "pipeline_demo_trap")
li("t0", 0xBAD50000)
or_("t0", "t0", "t1")
li("t2", ACCEPT_BASE)
sw("t0", 8, "t2")
j("pipeline_demo_dispatch")

label("pipeline_demo_mixed")
addi("t1", "zero", 5)
addi("t2", "t1", 3)
add("t3", "t2", "t1")
sub("t4", "t3", "t1")
sw("t4", 4, "s0")
lw("t5", 4, "s0")
add("t6", "t5", "t1")
div("s2", "t6", "t1")
addi("s3", "s2", 1)
xori("s1", "s1", 1)
andi("s4", "s1", 1)
beq("s4", "zero", "pipeline_demo_taken")
addi("s5", "s3", 2)
j("pipeline_demo_store")

label("pipeline_demo_taken")
add("s5", "s3", "t4")

label("pipeline_demo_store")
sw("s5", 8, "s0")
li("t0", ACCEPT_BASE)
sw("s5", 8, "t0")
j("pipeline_demo_dispatch")

label("pipeline_demo_forward")
addi("t1", "zero", 5)
addi("t2", "t1", 3)
add("t3", "t2", "t1")
sub("t4", "t3", "t1")
li("t0", PERF_BASE)
lw("t5", 0x30, "t0")
slli("t5", "t5", 16)
or_("t5", "t5", "t4")
li("t0", ACCEPT_BASE)
sw("t5", 8, "t0")
j("pipeline_demo_dispatch")

label("pipeline_demo_loaduse")
li("t0", BRAM_BASE + 0x220)
li("t1", 8)
sw("t1", 0, "t0")
lw("t2", 0, "t0")
addi("t3", "t2", 5)
li("t0", ACCEPT_BASE)
sw("t3", 8, "t0")
j("pipeline_demo_dispatch")

label("pipeline_demo_muldiv")
li("t0", 7)
li("t1", 6)
mul("t2", "t0", "t1")
div("t3", "t2", "t1")
rem("t4", "t2", "t1")
slli("t2", "t2", 16)
or_("t2", "t2", "t3")
li("t0", ACCEPT_BASE)
sw("t2", 8, "t0")
j("pipeline_demo_dispatch")

label("pipeline_demo_branch")
xori("s1", "s1", 1)
andi("t0", "s1", 1)
beq("t0", "zero", "pipeline_demo_branch_taken")
addi("t1", "zero", 1)
j("pipeline_demo_branch_done")
label("pipeline_demo_branch_taken")
addi("t1", "zero", 2)
label("pipeline_demo_branch_done")
li("t0", PERF_BASE)
lw("t2", 8, "t0")
lw("t3", 12, "t0")
slli("t2", "t2", 16)
or_("t2", "t2", "t3")
li("t0", ACCEPT_BASE)
sw("t2", 8, "t0")
j("pipeline_demo_dispatch")

label("pipeline_demo_dcache")
li("t0", DDR_STATUS_BASE)
label("pipeline_demo_ddr_wait")
lw("t1", 0, "t0")
andi("t1", "t1", 1)
beq("t1", "zero", "pipeline_demo_ddr_wait")
li("t0", DDR_BASE + 0x310)
li("t1", 0x01020304)
sw("t1", 0, "t0")
li("t1", 0x11121314)
sw("t1", 0x40, "t0")
li("t1", 0x21222324)
sw("t1", 0x80, "t0")
li("t4", CACHE_BASE)
li("t1", 1)
sw("t1", 0x1c, "t4")
lw("t1", 0, "t0")
lw("t1", 0x40, "t0")
lw("t1", 0x80, "t0")
lw("t1", 0, "t0")
lw("t2", 0, "t4")
lw("t3", 4, "t4")
lw("t5", 8, "t4")
lw("t6", 12, "t4")
andi("t2", "t2", 0xff)
andi("t3", "t3", 0xff)
andi("t5", "t5", 0xff)
andi("t6", "t6", 0xff)
slli("t2", "t2", 24)
slli("t3", "t3", 16)
slli("t5", "t5", 8)
or_("t2", "t2", "t3")
or_("t2", "t2", "t5")
or_("t2", "t2", "t6")
li("t0", ACCEPT_BASE)
sw("t2", 8, "t0")
j("pipeline_demo_dispatch")

label("pipeline_demo_icache")
j("pipeline_demo_icache_a")

label("pipeline_demo_trap")
li("t0", BRAM_BASE + 0x400)
sw("zero", 0, "t0")
la("t0", "irq_handler")
csrrw("zero", CSR_MTVEC, "t0")
li("t0", MIE_MEIE)
csrrs("zero", CSR_MIE, "t0")
li("t0", MSTATUS_MIE)
csrrs("zero", CSR_MSTATUS, "t0")
li("t0", TIMER_BASE)
sw("zero", 0, "t0")
li("t1", 16)
sw("t1", 4, "t0")
li("t1", 7)
sw("t1", 8, "t0")
label("pipeline_demo_trap_wait")
li("t2", BRAM_BASE + 0x400)
lw("t3", 0, "t2")
beq("t3", "zero", "pipeline_demo_trap_wait")
sw("zero", 8, "t0")
li("t1", MSTATUS_MIE)
csrrc("zero", CSR_MSTATUS, "t1")
li("t0", ACCEPT_BASE)
sw("t3", 8, "t0")
j("pipeline_demo_dispatch")

# RV32I 基础指令自检。覆盖算术逻辑、移位、比较、load/store 字节半字扩展、
# 分支跳转和 auipc/jalr。每一步都用 expect 检查结果。
label("run_isa_tests")
li("t0", 5)
addi("t1", "t0", 7)
expect("t1", 12)
sub("t2", "t1", "t0")
expect("t2", 7)
li("t0", 0x55)
li("t1", 0x0F)
and_("t2", "t0", "t1")
expect("t2", 0x05)
or_("t2", "t0", "t1")
expect("t2", 0x5F)
xor("t2", "t0", "t1")
expect("t2", 0x5A)
xori("t2", "t2", 0x0A)
expect("t2", 0x50)
ori("t2", "zero", 0x123)
andi("t2", "t2", 0x23)
expect("t2", 0x23)
li("t0", 1)
slli("t1", "t0", 5)
expect("t1", 32)
srli("t1", "t1", 2)
expect("t1", 8)
li("t0", 0xFFFFFFF0)
srai("t1", "t0", 2)
expect("t1", 0xFFFFFFFC)
slti("t1", "t0", 1)
expect("t1", 1)
sltiu("t1", "t0", 1)
expect("t1", 0)
slt("t1", "t0", "zero")
expect("t1", 1)
sltu("t1", "t0", "zero")
expect("t1", 0)
li("t0", BRAM_BASE + 0x300)
li("t1", 0x12345678)
sw("t1", 0, "t0")
lw("t2", 0, "t0")
expect("t2", 0x12345678)
li("t1", 0x000000AA)
sb("t1", 1, "t0")
lbu("t2", 1, "t0")
expect("t2", 0xAA)
lb("t2", 1, "t0")
expect("t2", 0xFFFFFFAA)
li("t1", 0x00008001)
sh("t1", 2, "t0")
lhu("t2", 2, "t0")
expect("t2", 0x8001)
lh("t2", 2, "t0")
expect("t2", 0xFFFF8001)
li("t0", 3)
li("t1", 7)
blt("t0", "t1", "branch_ok1")
j("isa_fail")
label("branch_ok1")
bge("t1", "t0", "branch_ok2")
j("isa_fail")
label("branch_ok2")
bltu("t0", "t1", "branch_ok3")
j("isa_fail")
label("branch_ok3")
bgeu("t1", "t0", "branch_ok4")
j("isa_fail")
label("branch_ok4")
# 用 auipc + jalr 构造一次寄存器间接跳转；如果跳转失败会落到 isa_fail。
auipc("t0", 0)
addi("t0", "t0", 16)
jalr("zero", 0, "t0")
j("isa_fail")
addi("a0", "zero", 0)
ret()

# RV32M 乘除法扩展自检。覆盖乘法、无符号高位乘法、有符号/无符号除法和取余。
label("run_m_tests")
li("t0", 7)
li("t1", 6)
mul("t2", "t0", "t1")
expect("t2", 42)
li("t0", 0xFFFFFFFF)
li("t1", 2)
mulhu("t2", "t0", "t1")
expect("t2", 1)
li("t0", 42)
li("t1", 5)
div("t2", "t0", "t1")
expect("t2", 8)
rem("t2", "t0", "t1")
expect("t2", 2)
li("t0", 0xFFFFFFF6)
li("t1", 3)
div("t2", "t0", "t1")
expect("t2", 0xFFFFFFFD)
rem("t2", "t0", "t1")
expect("t2", 0xFFFFFFFF)
li("t0", 17)
li("t1", 5)
divu("t2", "t0", "t1")
expect("t2", 3)
remu("t2", "t0", "t1")
expect("t2", 2)
ret()

# ISA/M 扩展自检失败处理。读取 CPU 暴露的分支调试寄存器并通过 UART 打印，
# 方便定位是否是分支、比较或流水线 forwarding/stall 出问题。
label("isa_fail")
li("t0", DEBUG_BASE)
lw("s2", 0, "t0")
lw("s3", 4, "t0")
lw("s4", 8, "t0")
lw("s5", 12, "t0")
puts_label("msg_isa_fail")
puts_label("msg_dbg_pc")
addi("a0", "s2", 0)
call("print_hex")
puts_label("msg_dbg_srca")
addi("a0", "s3", 0)
call("print_hex")
puts_label("msg_dbg_srcb")
addi("a0", "s4", 0)
call("print_hex")
puts_label("msg_dbg_info")
addi("a0", "s5", 0)
call("print_hex")
label("isa_fail_halt")
j("isa_fail_halt")

# DDR 自检：先等 MIG/DDR calibration done，再向 DDR 数据窗口写两个固定 pattern，
# 读回比较。通过说明 DDR status、D-Cache/DDR path 和基本读写链路可用。
label("ddr_test")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
li("t0", DDR_STATUS_BASE)
label("ddr_wait")
lw("t1", 0, "t0")
andi("t1", "t1", 1)
beq("t1", "zero", "ddr_wait")
li("t0", DDR_BASE)
li("t1", 0x11223344)
sw("t1", 0, "t0")
li("t1", 0xA5A55A5A)
sw("t1", 4, "t0")
lw("t2", 0, "t0")
expect("t2", 0x11223344, "ddr_fail")
lw("t2", 4, "t0")
expect("t2", 0xA5A55A5A, "ddr_fail")
puts_label("msg_ddr_ok")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
ret()

label("ddr_fail")
puts_label("msg_ddr_fail")
j("ddr_fail")

# D-Cache 自检：在 DDR 上预置三个 word，清空 D-Cache 统计后读三处地址。
# 预期前三次读是 miss，最后重复读同一地址是 hit，因此统计应为 hit=1、
# miss=3、replacement=0。数据和计数都正确才打印 CACHE READY。
label("cache_test")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
li("t0", DDR_BASE + 0x110)
li("t1", 0x01020304)
sw("t1", 0, "t0")
li("t1", 0x11121314)
sw("t1", 0x40, "t0")
li("t1", 0x21222324)
sw("t1", 0x80, "t0")
li("t3", CACHE_BASE)
li("t1", 1)
sw("t1", 0x1c, "t3")
lw("t1", 0, "t0")
expect("t1", 0x01020304, "cache_fail")
lw("t1", 0x40, "t0")
expect("t1", 0x11121314, "cache_fail")
lw("t1", 0x80, "t0")
expect("t1", 0x21222324, "cache_fail")
lw("t1", 0x80, "t0")
expect("t1", 0x21222324, "cache_fail")
lw("t1", 4, "t3")
expect("t1", 1, "cache_fail")
lw("t1", 8, "t3")
expect("t1", 3, "cache_fail")
lw("t1", 12, "t3")
expect("t1", 0, "cache_fail")
puts_label("msg_cache_ready")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
ret()

label("cache_fail")
puts_label("msg_cache_fail")
j("cache_fail")

# FP32 MMIO 协处理器自检。通过 MMIO 写入两个单精度正数和操作选择：
# op=0 做加法 1.5 + 2.25 = 3.75，op=1 做乘法 1.5 * 2.0 = 3.0。
# 结果按 IEEE754 bit pattern 比较。
label("fp_test")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
li("t0", FP_BASE)
li("t1", 0x3FC00000)
sw("t1", 0, "t0")
li("t1", 0x40100000)
sw("t1", 4, "t0")
li("t1", 0)
sw("t1", 8, "t0")
wait_fp_ready("fp_wait_add")
lw("t2", 12, "t0")
expect("t2", 0x40700000, "fp_fail")
li("t1", 0x3FC00000)
sw("t1", 0, "t0")
li("t1", 0x40000000)
sw("t1", 4, "t0")
li("t1", 1)
sw("t1", 8, "t0")
wait_fp_ready("fp_wait_mul")
lw("t2", 12, "t0")
expect("t2", 0x40400000, "fp_fail")
puts_label("msg_fp_ok")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
ret()

label("fp_fail")
puts_label("msg_fp_fail")
j("fp_fail")

# UART shell 主循环。命令解析为了节省 ROM 空间，只看命令第一个字符，
# 部分命令再检查后续关键字符。例如 "perf clear" 和 "pc" 都能触发清零。
label("shell_loop")
call("getchar")
addi("s0", "a0", 0)
call("consume_line")
li("t0", ord("h"))
beq("s0", "t0", "cmd_help")
li("t0", ord("m"))
beq("s0", "t0", "cmd_mem")
li("t0", ord("p"))
beq("s0", "t0", "cmd_perf_dispatch")
li("t0", ord("b"))
beq("s0", "t0", "cmd_bench_dispatch")
li("t0", ord("c"))
beq("s0", "t0", "cmd_cache")
li("t0", ord("f"))
beq("s0", "t0", "cmd_fp")
li("t0", ord("l"))
beq("s0", "t0", "cmd_led")
li("t0", ord("r"))
beq("s0", "t0", "cmd_run")
li("t0", ord("n"))
beq("s0", "t0", "cmd_pclr")
li("t0", ord("a"))
beq("s0", "t0", "cmd_accept_dispatch")
li("t0", ord("e"))
beq("s0", "t0", "cmd_bmem")
li("t0", ord("g"))
beq("s0", "t0", "cmd_bbr")
li("t0", ord("i"))
beq("s0", "t0", "cmd_int_dispatch")
li("t0", ord("o"))
beq("s0", "t0", "cmd_intoff")
li("t0", ord("t"))
beq("s0", "t0", "cmd_intstat")
j("cmd_help")

# help：打印当前 ROM 支持的命令列表。
label("cmd_help")
puts_label("msg_help")
call("print_prompt")
j("shell_loop")

label("cmd_accept_dispatch")
li("t0", CMD_BUF + 1)
lbu("t1", 0, "t0")
li("t2", ord("c"))
beq("t1", "t2", "cmd_accept_subdispatch")
j("cmd_balu")

label("cmd_accept_subdispatch")
li("t0", CMD_BUF + 7)
lbu("t1", 0, "t0")
li("t2", ord("c"))
beq("t1", "t2", "cmd_accept_clear")
j("cmd_accept")

# mem/cache/fp：手动重复运行启动阶段的 DDR、D-Cache、FP 自检。
label("cmd_mem")
call("ddr_test")
call("print_prompt")
j("shell_loop")

label("cmd_cache")
call("cache_test")
call("print_prompt")
j("shell_loop")

label("cmd_fp")
call("fp_test")
call("print_prompt")
j("shell_loop")

# led：写 GPIO MMIO，点亮 LED0，用于确认 CPU 到 GPIO 的 MMIO 写链路和板上 LED。
label("cmd_led")
li("t0", GPIO_BASE)
li("t1", 1)
sw("t1", 0, "t0")
puts_label("msg_ok")
call("print_prompt")
j("shell_loop")

# run：执行一个很小的分支循环，主要用于产生可观察的分支/退休指令活动。
label("cmd_run")
li("t0", 64)
label("run_loop")
addi("t0", "t0", -1)
bne("t0", "zero", "run_loop")
puts_label("msg_demo")
call("print_prompt")
j("shell_loop")

# perf：直接读取性能计数器 MMIO 并打印。输出值是十六进制。
label("cmd_perf")
print_perf_field("msg_cycles", 0)
print_perf_field("msg_retired", 4)
print_perf_field("msg_branch", 8)
print_perf_field("msg_misp", 12)
print_perf_field("msg_stall", 16)
print_perf_field("msg_stall_lu", 20)
print_perf_field("msg_stall_md", 24)
print_perf_field("msg_stall_dc", 28)
print_perf_field("msg_stall_if", 32)
print_perf_field("msg_stall_ddr", 36)
print_perf_field("msg_flush_br", 40)
print_perf_field("msg_flush_tr", 44)
print_perf_field("msg_forwards", 48)
call("print_prompt")
j("shell_loop")

# perf 命令分派：如果命令中出现 clear 的关键字符，就转到性能计数器清零。
label("cmd_perf_dispatch")
li("t0", CMD_BUF + 1)
lbu("t1", 0, "t0")
li("t2", ord("c"))
beq("t1", "t2", "cmd_pclr")
li("t0", CMD_BUF + 5)
lbu("t1", 0, "t0")
li("t2", ord("c"))
beq("t1", "t2", "cmd_pclr")
j("cmd_perf")

# bench 命令分派：支持 bench alu / bench mem / bench branch，也保留 a/e/g 简写入口。
label("cmd_bench_dispatch")
li("t0", CMD_BUF + 1)
lbu("t1", 0, "t0")
li("t2", ord("a"))
beq("t1", "t2", "cmd_balu")
li("t2", ord("m"))
beq("t1", "t2", "cmd_bmem")
li("t2", ord("b"))
beq("t1", "t2", "cmd_bbr")
li("t0", CMD_BUF + 6)
lbu("t1", 0, "t0")
li("t2", ord("a"))
beq("t1", "t2", "cmd_balu")
li("t2", ord("m"))
beq("t1", "t2", "cmd_bmem")
li("t2", ord("b"))
beq("t1", "t2", "cmd_bbr")
j("cmd_help")

# perf clear：向 PERF_BASE+0x1c 写 1。perf_mmio.v 用这个写操作清零所有计数器。
label("cmd_pclr")
li("t0", PERF_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
puts_label("msg_ok")
call("print_prompt")
j("shell_loop")

# bench alu：清零性能计数器后运行 1000 轮算术/逻辑/乘法混合循环，
# 结束后先快照再打印，用于观察 ALU/M 扩展和流水线基础性能。
label("cmd_balu")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
li("t0", PERF_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
li("s0", 1000)
li("s1", 0)
label("balu_loop")
addi("t0", "s1", 7)
sub("t1", "t0", "s0")
and_("t2", "t0", "t1")
or_("t3", "t2", "t1")
xor("t4", "t3", "t2")
slli("t5", "t4", 2)
mul("s1", "t5", "t0")
addi("s0", "s0", -1)
bne("s0", "zero", "balu_loop")
snapshot_perf()
print_snapshot_field("msg_balu", 0)
print_snapshot_tail(skip_offsets={0})
lw("ra", 0, "sp")
addi("sp", "sp", 4)
call("print_prompt")
j("shell_loop")

# bench mem：清零 perf 和 D-Cache 统计，顺序写 256 个 word 到 DDR，再顺序读回。
# 输出 cycles/stalls/misses 等，用于观察 DDR 和 D-Cache 行为。
label("cmd_bmem")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
li("t0", PERF_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
li("t0", CACHE_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
li("t0", DDR_BASE)
li("s0", 256)
li("s1", 0)
label("bmem_write")
sw("s1", 0, "t0")
addi("t0", "t0", 4)
addi("s1", "s1", 1)
addi("s0", "s0", -1)
bne("s0", "zero", "bmem_write")
li("t0", DDR_BASE)
li("s0", 256)
label("bmem_read")
lw("t1", 0, "t0")
addi("t0", "t0", 4)
addi("s0", "s0", -1)
bne("s0", "zero", "bmem_read")
snapshot_perf()
snapshot_cache_stats()
print_snapshot_field("msg_bmem", 0)
print_snapshot_tail(skip_offsets={0})
print_snapshot_field("msg_misses", SNAP_CACHE_MISSES)
lw("ra", 0, "sp")
addi("sp", "sp", 4)
call("print_prompt")
j("shell_loop")

# bench branch：运行大量固定模式分支，重点打印分支数和误预测数，
# 用于观察 branch predictor 和 flush 相关计数。
label("cmd_bbr")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
li("t0", PERF_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
li("s0", 200)
label("bbr_outer")
li("s1", 8)
label("bbr_inner")
beq("zero", "zero", "bbr_l1")
label("bbr_l1")
bne("zero", "zero", "bbr_l2")
label("bbr_l2")
andi("t2", "s1", 1)
beq("t2", "zero", "bbr_l3")
label("bbr_l3")
addi("s1", "s1", -1)
bne("s1", "zero", "bbr_inner")
addi("s0", "s0", -1)
bne("s0", "zero", "bbr_outer")
snapshot_perf()
print_snapshot_field("msg_bbr", 8)
print_snapshot_field("msg_misp", 12)
print_snapshot_tail(skip_offsets={8, 12})
lw("ra", 0, "sp")
addi("sp", "sp", 4)
call("print_prompt")
j("shell_loop")

# int on：设置 mtvec，打开 machine external interrupt，启动 timer。
# 中断处理函数会增加 tick 计数并翻转 LED1。
label("cmd_inton")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
la("t0", "irq_handler")
csrrw("zero", CSR_MTVEC, "t0")
li("t0", MIE_MEIE)
csrrs("zero", CSR_MIE, "t0")
li("t0", MSTATUS_MIE)
csrrs("zero", CSR_MSTATUS, "t0")
li("t0", TIMER_BASE)
li("t1", 1)
sw("t1", 0x0c, "t0")
li("t1", 0x7)
sw("t1", 0x08, "t0")
puts_label("msg_int_on")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
call("print_prompt")
j("shell_loop")

# int 命令分派：int 默认等同 int on；int stat 打印 tick/pending；int off 关中断。
label("cmd_int_dispatch")
li("t0", CMD_BUF + 1)
lbu("t1", 0, "t0")
beq("t1", "zero", "cmd_inton")
li("t0", CMD_BUF + 4)
lbu("t1", 0, "t0")
li("t2", ord("s"))
beq("t1", "t2", "cmd_intstat")
li("t2", ord("o"))
beq("t1", "t2", "cmd_int_o_dispatch")
j("cmd_inton")

label("cmd_int_o_dispatch")
li("t0", CMD_BUF + 5)
lbu("t1", 0, "t0")
li("t2", ord("f"))
beq("t1", "t2", "cmd_intoff")
j("cmd_inton")

# int off：清除 mstatus.MIE，停止 CPU 响应中断。
label("cmd_intoff")
li("t0", MSTATUS_MIE)
csrrc("zero", CSR_MSTATUS, "t0")
puts_label("msg_int_off")
call("print_prompt")
j("shell_loop")

# int stat：打印 BRAM 中的 tick 计数和 IRQ pending 状态，验证 timer/IRQ 链路。
label("cmd_intstat")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
puts_label("msg_tick")
li("t0", BRAM_BASE + 0x400)
lw("a0", 0, "t0")
call("print_hex")
puts_label("msg_pending")
li("t0", IRQ_BASE)
lw("a0", 0, "t0")
call("print_hex")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
call("print_prompt")
j("shell_loop")

# accept clear：关闭验收面板，恢复普通 GPIO LED 和空白数码管。
label("cmd_accept_clear")
li("t0", ACCEPT_BASE)
sw("zero", 0, "t0")
sw("zero", 4, "t0")
sw("zero", 8, "t0")
sw("zero", 12, "t0")
puts_label("msg_ok")
call("print_prompt")
j("shell_loop")

# accept_set_status(a0=mask)：将通过位并入验收状态寄存器。
label("accept_set_status")
li("t0", ACCEPT_BASE)
lw("t1", 4, "t0")
or_("t1", "t1", "a0")
sw("t1", 4, "t0")
ret()

# accept_set_fail(a0=mask)：记录失败位，最终用于 BAD0xxxx 显示。
label("accept_set_fail")
li("t0", ACCEPT_BASE)
lw("t1", 12, "t0")
or_("t1", "t1", "a0")
sw("t1", 12, "t0")
ret()

# accept_store_slot(a0=index, a1=packed digits/raw hex, a2=decimal-point mask)。
label("accept_store_slot")
li("t0", ACCEPT_BASE + 0x40)
slli("t1", "a0", 2)
add("t0", "t0", "t1")
sw("a1", 0, "t0")
li("t0", ACCEPT_BASE + 0x80)
add("t0", "t0", "t1")
sw("a2", 0, "t0")
ret()

# 加强版一键验收。进入 shell 已经意味着启动阶段的 ISA/M/DDR/Cache/FP
# 自检通过；这里再次运行外设自检，并加入 IRQ、benchmark 和派生指标。
label("cmd_accept")
li("t0", ACCEPT_BASE)
li("t1", 1)
sw("t1", 0, "t0")
sw("zero", 4, "t0")
sw("zero", 8, "t0")
sw("zero", 12, "t0")
li("t1", 0xACCE0001)
sw("t1", 0x40, "t0")
puts_label("msg_accept_header")
puts_label("msg_accept_clock")

puts_label("msg_pass_rv32i")
li("a0", 1 << 0)
call("accept_set_status")
puts_label("msg_pass_rv32m")
li("a0", 1 << 1)
call("accept_set_status")

call("ddr_test")
puts_label("msg_pass_ddr")
li("a0", 1 << 2)
call("accept_set_status")
call("cache_test")
puts_label("msg_pass_dcache")
li("a0", 1 << 3)
call("accept_set_status")

li("t0", CACHE_BASE)
lw("t1", 0x20, "t0")
lw("t2", 0x28, "t0")
beq("t1", "zero", "accept_icache_fail")
beq("t2", "zero", "accept_icache_fail")
puts_label("msg_pass_icache")
li("a0", 1 << 4)
call("accept_set_status")
j("accept_icache_done")
label("accept_icache_fail")
puts_label("msg_fail_icache")
li("a0", 1 << 4)
call("accept_set_fail")
label("accept_icache_done")

call("fp_test")
puts_label("msg_pass_fp_add")
li("a0", 1 << 5)
call("accept_set_status")
puts_label("msg_pass_fp_mul")
li("a0", 1 << 6)
call("accept_set_status")
li("a0", 0x0B)
li("a1", 0x40700000)
li("a2", 0)
call("accept_store_slot")
li("a0", 0x0C)
li("a1", 0x40400000)
li("a2", 0)
call("accept_store_slot")

# Timer/IRQ 自检：短 compare、机器外部中断、ISR tick 和 mret。
li("t0", BRAM_BASE + 0x400)
sw("zero", 0, "t0")
la("t0", "irq_handler")
csrrw("zero", CSR_MTVEC, "t0")
li("t0", MIE_MEIE)
csrrs("zero", CSR_MIE, "t0")
li("t0", MSTATUS_MIE)
csrrs("zero", CSR_MSTATUS, "t0")
li("t0", TIMER_BASE)
sw("zero", 0, "t0")
li("t1", 64)
sw("t1", 4, "t0")
li("t1", 7)
sw("t1", 8, "t0")
li("s6", 10000)
label("accept_irq_wait")
li("t2", BRAM_BASE + 0x400)
lw("t3", 0, "t2")
bne("t3", "zero", "accept_irq_pass")
addi("s6", "s6", -1)
bne("s6", "zero", "accept_irq_wait")
sw("zero", 8, "t0")
li("t1", MSTATUS_MIE)
csrrc("zero", CSR_MSTATUS, "t1")
puts_label("msg_fail_timer")
li("a0", 1 << 7)
call("accept_set_fail")
j("accept_irq_done")
label("accept_irq_pass")
sw("zero", 8, "t0")
li("t1", MSTATUS_MIE)
csrrc("zero", CSR_MSTATUS, "t1")
puts_label("msg_pass_timer")
li("a0", 1 << 7)
call("accept_set_status")
li("a0", 0x0D)
addi("a1", "t3", 0)
li("a2", 0)
call("accept_store_slot")
label("accept_irq_done")

# GPIO 写入和回读。
li("t0", GPIO_BASE)
li("t1", 0x0100)
sw("t1", 0, "t0")
lw("t2", 0, "t0")
bne("t1", "t2", "accept_gpio_fail")
li("a0", 1 << 8)
call("accept_set_status")
j("accept_gpio_done")
label("accept_gpio_fail")
li("a0", 1 << 8)
call("accept_set_fail")
label("accept_gpio_done")

# ALU benchmark。
li("t0", PERF_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
li("s0", 1000)
li("s1", 0)
label("accept_alu_loop")
addi("t0", "s1", 7)
sub("t1", "t0", "s0")
and_("t2", "t0", "t1")
or_("t3", "t2", "t1")
xor("t4", "t3", "t2")
slli("t5", "t4", 2)
mul("s1", "t5", "t0")
addi("s0", "s0", -1)
bne("s0", "zero", "accept_alu_loop")
snapshot_perf()
li("a0", 1 << 9)
call("accept_set_status")
li("a0", 1 << 10)
call("accept_set_status")
puts_label("msg_accept_alu")
li("t0", SNAP_BASE)
lw("s2", 0, "t0")
lw("s3", 4, "t0")
addi("a0", "s2", 0)
call("print_u32_dec")
puts_label("msg_accept_retired_inline")
addi("a0", "s3", 0)
call("print_u32_dec")
puts_label("msg_accept_cpi_inline")
li("t0", 1000)
mul("s4", "s2", "t0")
divu("s4", "s4", "s3")
addi("a0", "s4", 0)
call("print_fixed3")
puts_label("msg_accept_ipc_inline")
li("t0", 1000)
mul("s5", "s3", "t0")
divu("s5", "s5", "s2")
addi("a0", "s5", 0)
call("print_fixed3")
puts_label("msg_accept_mips_inline")
li("t0", 10000)
mul("s6", "s3", "t0")
divu("s6", "s6", "s2")
addi("a0", "s6", 0)
call("print_fixed2")
puts_label("msg_accept_mips_tail")
addi("a0", "s4", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 2)
li("a2", 8)
call("accept_store_slot")
addi("a0", "s6", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 3)
li("a2", 4)
call("accept_store_slot")

# Memory benchmark 与完整 D/I-Cache 统计。
li("t0", PERF_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
li("t0", CACHE_BASE)
sw("t1", 0x1c, "t0")
li("t0", DDR_BASE + 0x1000)
li("s0", 64)
li("s1", 0)
label("accept_mem_write")
sw("s1", 0, "t0")
addi("t0", "t0", 4)
addi("s1", "s1", 1)
addi("s0", "s0", -1)
bne("s0", "zero", "accept_mem_write")
li("t0", DDR_BASE + 0x1000)
li("s0", 64)
label("accept_mem_read")
lw("t1", 0, "t0")
addi("t0", "t0", 4)
addi("s0", "s0", -1)
bne("s0", "zero", "accept_mem_read")
snapshot_perf()
snapshot_cache_stats()
li("a0", 1 << 11)
call("accept_set_status")
puts_label("msg_accept_mem")
li("t0", SNAP_BASE)
lw("s2", 0, "t0")
lw("s3", 4, "t0")
addi("a0", "s2", 0)
call("print_u32_dec")
puts_label("msg_accept_retired_inline")
addi("a0", "s3", 0)
call("print_u32_dec")
puts_label("msg_accept_cpi_inline")
li("t0", 1000)
mul("s4", "s2", "t0")
divu("s4", "s4", "s3")
addi("a0", "s4", 0)
call("print_fixed3")
call("print_crlf")
addi("a0", "s4", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 4)
li("a2", 8)
call("accept_store_slot")

puts_label("msg_accept_dcache")
li("t0", SNAP_BASE)
lw("s2", SNAP_CACHE_ACCESS, "t0")
lw("s3", SNAP_CACHE_HITS, "t0")
lw("s4", SNAP_CACHE_MISSES, "t0")
lw("s5", SNAP_CACHE_REPLACEMENTS, "t0")
addi("a0", "s2", 0)
call("print_u32_dec")
puts_label("msg_accept_hits_inline")
addi("a0", "s3", 0)
call("print_u32_dec")
puts_label("msg_accept_misses_inline")
addi("a0", "s4", 0)
call("print_u32_dec")
puts_label("msg_accept_repl_inline")
addi("a0", "s5", 0)
call("print_u32_dec")
puts_label("msg_accept_rate_inline")
li("t0", 10000)
mul("s6", "s3", "t0")
divu("s6", "s6", "s2")
addi("a0", "s6", 0)
call("print_fixed2")
puts_label("msg_percent_tail")
addi("a0", "s6", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 5)
li("a2", 4)
call("accept_store_slot")
addi("a0", "s4", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 6)
li("a2", 0)
call("accept_store_slot")
addi("a0", "s5", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 7)
li("a2", 0)
call("accept_store_slot")

# Branch benchmark 和预测准确率。
li("t0", PERF_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
li("s0", 100)
label("accept_branch_outer")
li("s1", 8)
label("accept_branch_inner")
beq("zero", "zero", "accept_branch_l1")
label("accept_branch_l1")
bne("zero", "zero", "accept_branch_l2")
label("accept_branch_l2")
andi("t2", "s1", 1)
beq("t2", "zero", "accept_branch_l3")
label("accept_branch_l3")
addi("s1", "s1", -1)
bne("s1", "zero", "accept_branch_inner")
addi("s0", "s0", -1)
bne("s0", "zero", "accept_branch_outer")
snapshot_perf()
snapshot_cache_stats()
li("a0", 1 << 12)
call("accept_set_status")
puts_label("msg_accept_branch")
li("t0", SNAP_BASE)
lw("s2", 8, "t0")
lw("s3", 12, "t0")
addi("a0", "s2", 0)
call("print_u32_dec")
puts_label("msg_accept_misp_inline")
addi("a0", "s3", 0)
call("print_u32_dec")
puts_label("msg_accept_accuracy_inline")
sub("s4", "s2", "s3")
li("t0", 10000)
mul("s4", "s4", "t0")
divu("s4", "s4", "s2")
addi("a0", "s4", 0)
call("print_fixed2")
puts_label("msg_percent_tail")
addi("a0", "s4", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 8)
li("a2", 4)
call("accept_store_slot")
addi("a0", "s3", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 9)
li("a2", 0)
call("accept_store_slot")

puts_label("msg_accept_icache")
li("t0", SNAP_BASE)
lw("s2", SNAP_ICACHE_ACCESS, "t0")
lw("s3", SNAP_ICACHE_HITS, "t0")
lw("s4", SNAP_ICACHE_MISSES, "t0")
addi("a0", "s2", 0)
call("print_u32_dec")
puts_label("msg_accept_hits_inline")
addi("a0", "s3", 0)
call("print_u32_dec")
puts_label("msg_accept_misses_inline")
addi("a0", "s4", 0)
call("print_u32_dec")
puts_label("msg_accept_rate_inline")
li("t0", 10000)
mul("s5", "s4", "t0")
divu("s5", "s5", "s2")
li("t0", 10000)
sub("s5", "t0", "s5")
addi("a0", "s5", 0)
call("print_fixed2")
puts_label("msg_percent_tail")
addi("a0", "s5", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 0x0A)
li("a2", 4)
call("accept_store_slot")

li("a0", 1 << 13)
call("accept_set_status")
li("a0", 1 << 14)
call("accept_set_status")

# Forward/stall 数码管槽位取最后一次 benchmark 快照。
li("t0", SNAP_BASE)
lw("s2", 48, "t0")
addi("a0", "s2", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 0x0E)
li("a2", 0)
call("accept_store_slot")
lw("s2", 16, "t0")
addi("a0", "s2", 0)
call("pack_bcd8")
addi("a1", "a0", 0)
li("a0", 0x0F)
li("a2", 0)
call("accept_store_slot")

li("t0", ACCEPT_BASE)
lw("t1", 4, "t0")
sw("t1", 0x44, "t0")
li("t2", 0x7fff)
bne("t1", "t2", "accept_final_fail")
li("a0", 0x8000)
call("accept_set_status")
li("t0", ACCEPT_BASE)
li("t1", 0xffff)
sw("t1", 0x44, "t0")
li("t1", 0xACCE5500)
sw("t1", 0x40, "t0")
puts_label("msg_accept_status_pass")
puts_label("msg_accept_pass")
j("accept_finish")

label("accept_final_fail")
li("t2", 0x7fff)
xor("t3", "t1", "t2")
sw("t3", 12, "t0")
li("t4", 0xBAD00000)
or_("t4", "t4", "t3")
sw("t4", 0x40, "t0")
puts_label("msg_accept_status")
addi("a0", "t1", 0)
call("print_hex")
puts_label("msg_accept_fail")

label("accept_finish")
li("t0", ACCEPT_BASE)
lw("t1", 0, "t0")
ori("t1", "t1", 2)
sw("t1", 0, "t0")
call("print_prompt")
j("shell_loop")

# Timer 中断处理函数。为了保持 ISR 短小，只保存会用到的临时寄存器：
# 1) BRAM tick 计数 +1；2) 翻转 LED1；3) 写 timer ack 清中断；4) mret 返回。
label("irq_handler")
addi("sp", "sp", -16)
sw("t0", 0, "sp")
sw("t1", 4, "sp")
sw("t2", 8, "sp")
li("t0", BRAM_BASE + 0x400)
lw("t1", 0, "t0")
addi("t1", "t1", 1)
sw("t1", 0, "t0")
li("t0", GPIO_BASE)
lw("t1", 0, "t0")
li("t2", 2)
xor("t1", "t1", "t2")
sw("t1", 0, "t0")
li("t0", TIMER_BASE)
sw("zero", 0, "t0")
li("t1", 1)
sw("t1", 0x0c, "t0")
lw("t0", 0, "sp")
lw("t1", 4, "sp")
lw("t2", 8, "sp")
addi("sp", "sp", 16)
mret()

# 打印 shell 提示符 rv32>。
label("print_prompt")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
puts_label("msg_prompt")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
ret()

# puts(a0)：从 a0 指向的 NUL 结尾字符串逐字节输出到 UART。
label("puts")
addi("sp", "sp", -8)
sw("ra", 4, "sp")
sw("s0", 0, "sp")
addi("s0", "a0", 0)
label("puts_loop")
lbu("a0", 0, "s0")
beq("a0", "zero", "puts_done")
call("putchar")
addi("s0", "s0", 1)
j("puts_loop")
label("puts_done")
lw("s0", 0, "sp")
lw("ra", 4, "sp")
addi("sp", "sp", 8)
ret()

# putchar(a0)：阻塞式 UART 发送。先轮询 STATUS.tx_ready，再写 TXDATA。
label("putchar")
li("t0", UART_BASE)
label("putchar_wait")
lw("t1", UART_STATUS, "t0")
andi("t1", "t1", 1)
beq("t1", "zero", "putchar_wait")
sw("a0", UART_TXDATA, "t0")
ret()

# getchar() -> a0：阻塞式 UART 接收。先轮询 STATUS.rx_valid，再读 RXDATA。
label("getchar")
li("t0", UART_BASE)
label("getchar_wait")
lw("t1", UART_STATUS, "t0")
andi("t1", "t1", 2)
beq("t1", "zero", "getchar_wait")
lw("a0", UART_RXDATA, "t0")
andi("a0", "a0", 0xFF)
ret()

# consume_line：shell 已经读到首字符 s0，这里继续读到 CR/LF，
# 同时把整行存入 CMD_BUF，供 perf clear / bench xxx / int stat 这类命令二次判断。
label("consume_line")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
li("t3", CMD_BUF)
li("t4", 32)
label("consume_clear_loop")
sb("zero", 0, "t3")
addi("t3", "t3", 1)
addi("t4", "t4", -1)
bne("t4", "zero", "consume_clear_loop")
li("t3", CMD_BUF)
sb("s0", 0, "t3")
addi("t3", "t3", 1)
li("t2", 13)
beq("s0", "t2", "consume_done")
li("t2", 10)
beq("s0", "t2", "consume_done")
label("consume_loop")
call("getchar")
li("t2", 13)
beq("a0", "t2", "consume_done")
li("t2", 10)
beq("a0", "t2", "consume_done")
sb("a0", 0, "t3")
addi("t3", "t3", 1)
j("consume_loop")
label("consume_done")
li("t2", 0)
sb("t2", 0, "t3")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
ret()

# print_hex(a0)：把 32-bit 值打印成 8 个大写十六进制字符，并追加 CRLF。
label("print_hex")
addi("sp", "sp", -12)
sw("ra", 8, "sp")
sw("s0", 4, "sp")
sw("s1", 0, "sp")
addi("s0", "a0", 0)
li("s1", 8)
label("hex_loop")
srli("a0", "s0", 28)
andi("a0", "a0", 0xF)
li("t1", 10)
blt("a0", "t1", "hex_digit")
addi("a0", "a0", ord("A") - 10)
j("hex_emit")
label("hex_digit")
addi("a0", "a0", ord("0"))
label("hex_emit")
call("putchar")
slli("s0", "s0", 4)
addi("s1", "s1", -1)
bne("s1", "zero", "hex_loop")
li("a0", 13)
call("putchar")
li("a0", 10)
call("putchar")
lw("s1", 0, "sp")
lw("s0", 4, "sp")
lw("ra", 8, "sp")
addi("sp", "sp", 12)
ret()

# print_crlf：供组合字段输出在行末追加换行。
label("print_crlf")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
li("a0", 13)
call("putchar")
li("a0", 10)
call("putchar")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
ret()

# print_u32_dec(a0)：无符号十进制输出，不自动换行。
label("print_u32_dec")
addi("sp", "sp", -32)
sw("ra", 28, "sp")
sw("s0", 24, "sp")
sw("s1", 20, "sp")
sw("s2", 16, "sp")
addi("s0", "a0", 0)
li("s1", 0)
addi("s2", "sp", 0)
bne("s0", "zero", "print_dec_collect")
li("t0", ord("0"))
sb("t0", 0, "s2")
addi("s2", "s2", 1)
li("s1", 1)
j("print_dec_emit")
label("print_dec_collect")
li("t0", 10)
remu("t1", "s0", "t0")
divu("s0", "s0", "t0")
addi("t1", "t1", ord("0"))
sb("t1", 0, "s2")
addi("s2", "s2", 1)
addi("s1", "s1", 1)
bne("s0", "zero", "print_dec_collect")
label("print_dec_emit")
addi("s2", "s2", -1)
lbu("a0", 0, "s2")
call("putchar")
addi("s1", "s1", -1)
bne("s1", "zero", "print_dec_emit")
lw("s2", 16, "sp")
lw("s1", 20, "sp")
lw("s0", 24, "sp")
lw("ra", 28, "sp")
addi("sp", "sp", 32)
ret()

# print_fixed3/2：输入分别为放大 1000/100 倍的定点数。
label("print_fixed3")
addi("sp", "sp", -8)
sw("ra", 4, "sp")
sw("s0", 0, "sp")
li("t0", 1000)
remu("s0", "a0", "t0")
divu("a0", "a0", "t0")
call("print_u32_dec")
li("a0", ord("."))
call("putchar")
li("t0", 100)
divu("t1", "s0", "t0")
addi("a0", "t1", ord("0"))
call("putchar")
li("t0", 100)
remu("s0", "s0", "t0")
li("t0", 10)
divu("t1", "s0", "t0")
addi("a0", "t1", ord("0"))
call("putchar")
li("t0", 10)
remu("t1", "s0", "t0")
addi("a0", "t1", ord("0"))
call("putchar")
lw("s0", 0, "sp")
lw("ra", 4, "sp")
addi("sp", "sp", 8)
ret()

label("print_fixed2")
addi("sp", "sp", -8)
sw("ra", 4, "sp")
sw("s0", 0, "sp")
li("t0", 100)
remu("s0", "a0", "t0")
divu("a0", "a0", "t0")
call("print_u32_dec")
li("a0", ord("."))
call("putchar")
li("t0", 10)
divu("t1", "s0", "t0")
addi("a0", "t1", ord("0"))
call("putchar")
li("t0", 10)
remu("t1", "s0", "t0")
addi("a0", "t1", ord("0"))
call("putchar")
lw("s0", 0, "sp")
lw("ra", 4, "sp")
addi("sp", "sp", 8)
ret()

# pack_bcd8(a0)：把二进制整数转换成八位压缩 BCD，供数码管直接显示。
label("pack_bcd8")
addi("t0", "a0", 0)
li("t1", 0)
li("t2", 0)
li("t3", 8)
li("t4", 10)
label("pack_bcd8_loop")
remu("t5", "t0", "t4")
sll("t5", "t5", "t2")
or_("t1", "t1", "t5")
divu("t0", "t0", "t4")
addi("t2", "t2", 4)
addi("t3", "t3", -1)
bne("t3", "zero", "pack_bcd8_loop")
addi("a0", "t1", 0)
ret()


def bytes_label(name, text):
    # 把 Python 字符串按小端 32-bit word 填入 ROM，并给这段字符串打 label。
    # 程序中的 puts_label 会通过 la 找到这些字符串的 ROM 地址。
    while len(prog) * 4 % 4:
        emit(0, "pad")
    labels[name] = len(prog) * 4
    data = text.encode("ascii") + b"\0"
    display_text = text.encode("unicode_escape").decode("ascii")
    for idx in range(0, len(data), 4):
        chunk = data[idx:idx + 4]
        word = 0
        for bidx, val in enumerate(chunk):
            word |= val << (8 * bidx)
        emit(word, f'.ascii "{display_text}"')


# 串口输出文本常量。启动日志和 shell 命令输出都来自这里。
bytes_label("msg_banner", "BUPT RISC-V CPU PROJECT\r\n")
bytes_label("msg_isa_pass", "RV32I ISA PASS\r\n")
bytes_label("msg_m_pass", "M EXT PASS\r\n")
bytes_label("msg_isa_fail", "RV32I ISA FAIL\r\n")
bytes_label("msg_ddr_ok", "DDR TEST OK\r\n")
bytes_label("msg_ddr_fail", "DDR TEST FAIL\r\n")
bytes_label("msg_cache_ready", "CACHE READY\r\n")
bytes_label("msg_cache_fail", "CACHE FAIL\r\n")
bytes_label("msg_fp_ok", "FP TEST OK\r\n")
bytes_label("msg_fp_fail", "FP TEST FAIL\r\n")
bytes_label("msg_perf_ready", "PERF READY\r\n")
bytes_label("msg_prompt", "rv32> ")
bytes_label("msg_help", "help accept accept clear mem perf perf clear bench alu bench mem bench branch cache fp led run int on off stat\r\n")
bytes_label("msg_ok", "OK\r\n")
bytes_label("msg_demo", "demo started\r\n")
bytes_label("msg_cycles", "cycles=")
bytes_label("msg_retired", "retired=")
bytes_label("msg_branch", "branches=")
bytes_label("msg_misp", "mispredicts=")
bytes_label("msg_stall", "stalls=")
bytes_label("msg_stall_lu", "stall_lu=")
bytes_label("msg_stall_md", "stall_md=")
bytes_label("msg_stall_dc", "stall_dc=")
bytes_label("msg_stall_if", "stall_if=")
bytes_label("msg_stall_ddr", "stall_ddr=")
bytes_label("msg_flush_br", "flush_br=")
bytes_label("msg_flush_tr", "flush_tr=")
bytes_label("msg_forwards", "forwards=")
bytes_label("msg_balu", "BALU cycles=")
bytes_label("msg_bmem", "BMEM cycles=")
bytes_label("msg_bbr", "BBR branches=")
bytes_label("msg_misses", "misses=")
bytes_label("msg_int_on", "INT ON\r\n")
bytes_label("msg_int_off", "INT OFF\r\n")
bytes_label("msg_tick", "tick=")
bytes_label("msg_pending", "pending=")
bytes_label("msg_dbg_pc", "branch_pc=")
bytes_label("msg_dbg_srca", "branch_srca=")
bytes_label("msg_dbg_srcb", "branch_srcb=")
bytes_label("msg_dbg_info", "branch_info=")

bytes_label("msg_accept_header", "=== BUPT B ACCEPTANCE V1 ===\r\n")
bytes_label("msg_accept_clock", "CLOCK 100.000 MHz\r\n")
bytes_label("msg_pass_rv32i", "[PASS] RV32I\r\n")
bytes_label("msg_pass_rv32m", "[PASS] RV32M\r\n")
bytes_label("msg_pass_ddr", "[PASS] DDR\r\n")
bytes_label("msg_pass_dcache", "[PASS] DCACHE LRU\r\n")
bytes_label("msg_pass_icache", "[PASS] ICACHE\r\n")
bytes_label("msg_fail_icache", "[FAIL] ICACHE\r\n")
bytes_label("msg_pass_fp_add", "[PASS] FP32 ADD result=0x40700000\r\n")
bytes_label("msg_pass_fp_mul", "[PASS] FP32 MUL result=0x40400000\r\n")
bytes_label("msg_pass_timer", "[PASS] TIMER IRQ\r\n")
bytes_label("msg_fail_timer", "[FAIL] TIMER IRQ\r\n")
bytes_label("msg_accept_alu", "ALU cycles=")
bytes_label("msg_accept_mem", "MEM cycles=")
bytes_label("msg_accept_dcache", "DCACHE accesses=")
bytes_label("msg_accept_branch", "BRANCH branches=")
bytes_label("msg_accept_icache", "ICACHE accesses=")
bytes_label("msg_accept_retired_inline", " retired=")
bytes_label("msg_accept_cpi_inline", " CPI=")
bytes_label("msg_accept_ipc_inline", " IPC=")
bytes_label("msg_accept_mips_inline", " throughput=")
bytes_label("msg_accept_mips_tail", " MIPS\r\n")
bytes_label("msg_accept_hits_inline", " hits=")
bytes_label("msg_accept_misses_inline", " misses=")
bytes_label("msg_accept_repl_inline", " replacements=")
bytes_label("msg_accept_rate_inline", " hit_rate=")
bytes_label("msg_accept_misp_inline", " mispredicts=")
bytes_label("msg_accept_accuracy_inline", " accuracy=")
bytes_label("msg_percent_tail", "%\r\n")
bytes_label("msg_accept_status", "ACCEPT_STATUS=")
bytes_label("msg_accept_status_pass", "ACCEPT_STATUS=FFFF\r\n")
bytes_label("msg_accept_pass", "ACCEPTANCE PASS\r\n")
bytes_label("msg_accept_fail", "ACCEPTANCE FAIL\r\n")

# 两个地址相差 0x400，映射到 I-Cache 的同一 index。场景 6 在两处之间
# 反复跳转，稳定触发 refill/ifetch stall；切换场景后会回到分派器。
pad_to(0x3000)
label("pipeline_demo_icache_a")
li("t0", PANEL_BASE)
lw("t1", 0, "t0")
srli("t1", "t1", 3)
andi("t1", "t1", 0x0F)
li("t2", 6)
beq("t1", "t2", "pipeline_demo_icache_a_run")
j("pipeline_demo_dispatch")
label("pipeline_demo_icache_a_run")
li("t0", BRAM_BASE + 0x480)
lw("t1", 0, "t0")
addi("t1", "t1", 1)
sw("t1", 0, "t0")
li("t0", ACCEPT_BASE)
sw("t1", 8, "t0")
j("pipeline_demo_icache_b")

pad_to(0x3400)
label("pipeline_demo_icache_b")
li("t0", PANEL_BASE)
lw("t1", 0, "t0")
srli("t1", "t1", 3)
andi("t1", "t1", 0x0F)
li("t2", 6)
beq("t1", "t2", "pipeline_demo_icache_b_run")
j("pipeline_demo_dispatch")
label("pipeline_demo_icache_b_run")
li("t0", BRAM_BASE + 0x480)
lw("t1", 0, "t0")
addi("t1", "t1", 1)
sw("t1", 0, "t0")
li("t0", ACCEPT_BASE)
sw("t1", 8, "t0")
j("pipeline_demo_icache_a")

# 第二遍解析：此时所有代码和字符串 label 都已经确定，可以回填 branch/jal/la。
# 注意 listing 里仍保留原始伪汇编文本，真正写入 mem/listing 的机器码从 prog 取。
for index, kind, target, a, b, funct3 in fixups:
    here = index * 4
    dest = labels[target]
    if kind == "branch":
        off = dest - here
        if (off & 1) or not (-4096 <= off <= 4094):
            raise SystemExit(f"branch out of range at 0x{here:04x}: {target} offset={off}")
        prog[index] = benc(off, b, a, funct3)
    elif kind == "jal":
        off = dest - here
        if (off & 1) or not (-(1 << 20) <= off <= ((1 << 20) - 2)):
            raise SystemExit(f"jal out of range at 0x{here:04x}: {target} offset={off}")
        prog[index] = jenc(off, a)
    elif kind in ("la_hi", "la_lo"):
        hi = (dest + 0x800) >> 12
        lo = dest - ((hi & 0xFFFFF) << 12)
        if kind == "la_hi":
            prog[index] = u((hi & 0xFFFFF) << 12, a, 0x37)
        else:
            prog[index] = i(lo, a, 0, a, 0x13)

if len(prog) > BOOT_WORDS:
    raise SystemExit(f"boot image too large: {len(prog)} words")

# ROM 固定 4096 word；未使用空间补 0，保证 boot_rom.v 读入文件长度稳定。
while len(prog) < BOOT_WORDS:
    prog.append(0)

# 输出两个文件：
# 1) bupt_riscv_boot.mem 给硬件 Boot ROM 使用。
# 2) gen_bupt_boot.lst 给人看，便于把 ROM 地址、机器码和伪汇编对应起来。
repo = Path(__file__).resolve().parents[2]
mem_path = repo / "src" / "bupt_riscv" / "bupt_riscv_boot.mem"
lst_path = repo / "software" / "bupt_riscv" / "gen_bupt_boot.lst"
mem_path.write_text("\n".join(f"{word:08x}" for word in prog) + "\n", encoding="ascii")

with lst_path.open("w", encoding="utf-8") as f:
    for addr, word, asm in listing:
        if addr is None:
            f.write(f"{asm}\n")
        else:
            actual = prog[addr // 4]
            f.write(f"{addr:08x}: {actual:08x}  {asm}\n")

print(mem_path)
print(lst_path)
