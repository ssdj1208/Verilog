#!/usr/bin/env python3
"""Generate the BUPT RV32I boot ROM image."""
from pathlib import Path

BOOT_WORDS = 4096

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
DDR_BASE = 0x80000000
BRAM_BASE = 0x00010000
CMD_BUF = BRAM_BASE + 0x500
SNAP_BASE = BRAM_BASE + 0x600
SNAP_CACHE_MISSES = 0x30

UART_TXDATA = 0x0
UART_RXDATA = 0x4
UART_STATUS = 0x8

REG = {f"x{i}": i for i in range(32)}
REG.update({
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21,
    "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
})

prog = []
labels = {}
fixups = []
listing = []


def pc():
    return len(prog) * 4


def label(name):
    labels[name] = pc()
    listing.append((None, None, f"{name}:"))


def emit(word, asm):
    prog.append(word & 0xFFFFFFFF)
    listing.append((pc() - 4, word & 0xFFFFFFFF, asm))


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
    fixups.append((len(prog), "jal", target, rd, None, None))
    emit(0, f"jal {rd},{target}")


def j(target): jal("zero", target)
def call(target): jal("ra", target)
def ret(): jalr("zero", 0, "ra")


# CSR addresses (machine mode)
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
    return ((csr & 0xFFF) << 20) | (REG[rs1] << 15) | ((funct3 & 7) << 12) | (REG[rd] << 7) | 0x73

def csrrw(rd, csr, rs1): emit(_csr(csr, rs1, 1, rd), f"csrrw {rd},{csr:#x},{rs1}")
def csrrs(rd, csr, rs1): emit(_csr(csr, rs1, 2, rd), f"csrrs {rd},{csr:#x},{rs1}")
def csrrc(rd, csr, rs1): emit(_csr(csr, rs1, 3, rd), f"csrrc {rd},{csr:#x},{rs1}")
def csrrwi(rd, csr, imm): emit(((csr & 0xFFF) << 20) | ((imm & 0x1F) << 15) | (5 << 12) | (REG[rd] << 7) | 0x73, f"csrrwi {rd},{csr:#x},{imm}")
def csrrsi(rd, csr, imm): emit(((csr & 0xFFF) << 20) | ((imm & 0x1F) << 15) | (6 << 12) | (REG[rd] << 7) | 0x73, f"csrrsi {rd},{csr:#x},{imm}")
def csrrci(rd, csr, imm): emit(((csr & 0xFFF) << 20) | ((imm & 0x1F) << 15) | (7 << 12) | (REG[rd] << 7) | 0x73, f"csrrci {rd},{csr:#x},{imm}")
def mret(): emit(0x30200073, "mret")


def li(rd, value):
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
    fixups.append((len(prog), "la_hi", target, rd, None, None))
    emit(0, f"lui {rd},%hi({target})")
    fixups.append((len(prog), "la_lo", target, rd, None, None))
    emit(0, f"addi {rd},{rd},%lo({target})")


def expect(reg, value, fail_label="isa_fail"):
    li("t6", value)
    bne(reg, "t6", fail_label)


def puts_label(name):
    la("a0", name)
    call("puts")


def wait_fp_ready(label_name):
    label(label_name)
    lw("t2", 16, "t0")
    beq("t2", "zero", label_name)


def print_perf_field(msg_label, offset):
    puts_label(msg_label)
    li("t0", PERF_BASE)
    lw("a0", offset, "t0")
    call("print_hex")


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
]


def snapshot_perf():
    li("t0", PERF_BASE)
    li("t1", SNAP_BASE)
    for _, offset in PERF_SNAPSHOT_FIELDS:
        lw("t2", offset, "t0")
        sw("t2", offset, "t1")


def snapshot_cache_misses():
    li("t0", CACHE_BASE)
    lw("t2", 8, "t0")
    li("t1", SNAP_BASE)
    sw("t2", SNAP_CACHE_MISSES, "t1")


def print_snapshot_field(msg_label, offset):
    puts_label(msg_label)
    li("t0", SNAP_BASE)
    lw("a0", offset, "t0")
    call("print_hex")


def print_snapshot_tail(skip_offsets=()):
    skip = set(skip_offsets)
    for msg_label, offset in PERF_SNAPSHOT_FIELDS:
        if offset not in skip:
            print_snapshot_field(msg_label, offset)


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

label("pipeline_demo_entry")
li("s0", BRAM_BASE + 0x200)
li("s1", 0)
li("t0", 0x10)
sw("t0", 0, "s0")

label("pipeline_demo_loop")
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
j("pipeline_demo_loop")

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
auipc("t0", 0)
addi("t0", "t0", 16)
jalr("zero", 0, "t0")
j("isa_fail")
addi("a0", "zero", 0)
ret()

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
beq("s0", "t0", "cmd_balu")
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

label("cmd_help")
puts_label("msg_help")
call("print_prompt")
j("shell_loop")

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

label("cmd_led")
li("t0", GPIO_BASE)
li("t1", 1)
sw("t1", 0, "t0")
puts_label("msg_ok")
call("print_prompt")
j("shell_loop")

label("cmd_run")
li("t0", 64)
label("run_loop")
addi("t0", "t0", -1)
bne("t0", "zero", "run_loop")
puts_label("msg_demo")
call("print_prompt")
j("shell_loop")

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
call("print_prompt")
j("shell_loop")

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

label("cmd_cache_stats")
puts_label("msg_cache_hits")
li("t0", CACHE_BASE)
lw("a0", 4, "t0")
call("print_hex")
j("shell_loop")

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

label("cmd_pclr")
li("t0", PERF_BASE)
li("t1", 1)
sw("t1", 0x1c, "t0")
puts_label("msg_ok")
call("print_prompt")
j("shell_loop")

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
snapshot_cache_misses()
print_snapshot_field("msg_bmem", 0)
print_snapshot_tail(skip_offsets={0})
print_snapshot_field("msg_misses", SNAP_CACHE_MISSES)
lw("ra", 0, "sp")
addi("sp", "sp", 4)
call("print_prompt")
j("shell_loop")

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

label("cmd_intoff")
li("t0", MSTATUS_MIE)
csrrc("zero", CSR_MSTATUS, "t0")
puts_label("msg_int_off")
call("print_prompt")
j("shell_loop")

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
li("t1", 1)
sw("t1", 0x0c, "t0")
lw("t0", 0, "sp")
lw("t1", 4, "sp")
lw("t2", 8, "sp")
addi("sp", "sp", 16)
mret()

label("print_prompt")
addi("sp", "sp", -4)
sw("ra", 0, "sp")
puts_label("msg_prompt")
lw("ra", 0, "sp")
addi("sp", "sp", 4)
ret()

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

label("putchar")
li("t0", UART_BASE)
label("putchar_wait")
lw("t1", UART_STATUS, "t0")
andi("t1", "t1", 1)
beq("t1", "zero", "putchar_wait")
sw("a0", UART_TXDATA, "t0")
ret()

label("getchar")
li("t0", UART_BASE)
label("getchar_wait")
lw("t1", UART_STATUS, "t0")
andi("t1", "t1", 2)
beq("t1", "zero", "getchar_wait")
lw("a0", UART_RXDATA, "t0")
andi("a0", "a0", 0xFF)
ret()

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


def bytes_label(name, text):
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
bytes_label("msg_help", "help mem perf perf clear bench alu bench mem bench branch cache fp led run int on off stat\r\n")
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
bytes_label("msg_cache_hits", "cache_hits=")
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

for index, kind, target, a, b, funct3 in fixups:
    here = index * 4
    dest = labels[target]
    if kind == "branch":
        off = dest - here
        prog[index] = benc(off, b, a, funct3)
    elif kind == "jal":
        off = dest - here
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

while len(prog) < BOOT_WORDS:
    prog.append(0)

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
