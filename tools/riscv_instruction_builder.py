#!/usr/bin/env python3
"""Small GUI boot-ROM builder for the BUPT RV32I project.

The tool is intentionally dependency-free: it uses Tkinter from the Python
standard library and writes the same .mem format consumed by boot_rom.v.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, ttk


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
DDR_BASE = 0x80000000
BRAM_BASE = 0x00010000


REG = {f"x{i}": i for i in range(32)}
REG.update(
    {
        "zero": 0,
        "ra": 1,
        "sp": 2,
        "gp": 3,
        "tp": 4,
        "t0": 5,
        "t1": 6,
        "t2": 7,
        "s0": 8,
        "fp": 8,
        "s1": 9,
        "a0": 10,
        "a1": 11,
        "a2": 12,
        "a3": 13,
        "a4": 14,
        "a5": 15,
        "a6": 16,
        "a7": 17,
        "s2": 18,
        "s3": 19,
        "s4": 20,
        "s5": 21,
        "s6": 22,
        "s7": 23,
        "s8": 24,
        "s9": 25,
        "s10": 26,
        "s11": 27,
        "t3": 28,
        "t4": 29,
        "t5": 30,
        "t6": 31,
    }
)

REGISTER_CHOICES = [f"x{i}" for i in range(32)] + [
    "zero",
    "ra",
    "sp",
    "gp",
    "tp",
    "t0",
    "t1",
    "t2",
    "s0",
    "s1",
    "a0",
    "a1",
    "a2",
    "a3",
    "a4",
    "a5",
    "a6",
    "a7",
    "s2",
    "s3",
    "s4",
    "s5",
    "s6",
    "s7",
    "s8",
    "s9",
    "s10",
    "s11",
    "t3",
    "t4",
    "t5",
    "t6",
]

CSR_NAMES = {
    "mstatus": 0x300,
    "mie": 0x304,
    "mtvec": 0x305,
    "mepc": 0x341,
    "mcause": 0x342,
    "mip": 0x344,
}

ADDRESS_NAMES = {
    "GPIO_BASE": GPIO_BASE,
    "UART_BASE": UART_BASE,
    "TIMER_BASE": TIMER_BASE,
    "IRQ_BASE": IRQ_BASE,
    "DDR_STATUS_BASE": DDR_STATUS_BASE,
    "PERF_BASE": PERF_BASE,
    "CACHE_BASE": CACHE_BASE,
    "FP_BASE": FP_BASE,
    "DEBUG_BASE": DEBUG_BASE,
    "DDR_BASE": DDR_BASE,
    "BRAM_BASE": BRAM_BASE,
}


def parse_int(text: str) -> int:
    value = text.strip()
    if value in ADDRESS_NAMES:
        return ADDRESS_NAMES[value]
    if value in CSR_NAMES:
        return CSR_NAMES[value]
    if not value:
        raise ValueError("missing integer")
    return int(value, 0)


def reg_num(name: str) -> int:
    key = name.strip()
    if key not in REG:
        raise ValueError(f"unknown register: {name}")
    return REG[key]


def r_type(funct7: int, rs2: str, rs1: str, funct3: int, rd: str, opcode: int = 0x33) -> int:
    return (
        ((funct7 & 0x7F) << 25)
        | (reg_num(rs2) << 20)
        | (reg_num(rs1) << 15)
        | ((funct3 & 7) << 12)
        | (reg_num(rd) << 7)
        | opcode
    )


def i_type(imm: int, rs1: str, funct3: int, rd: str, opcode: int) -> int:
    return (
        ((imm & 0xFFF) << 20)
        | (reg_num(rs1) << 15)
        | ((funct3 & 7) << 12)
        | (reg_num(rd) << 7)
        | opcode
    )


def s_type(imm: int, rs2: str, rs1: str, funct3: int) -> int:
    return (
        (((imm >> 5) & 0x7F) << 25)
        | (reg_num(rs2) << 20)
        | (reg_num(rs1) << 15)
        | ((funct3 & 7) << 12)
        | ((imm & 0x1F) << 7)
        | 0x23
    )


def b_type(imm: int, rs2: str, rs1: str, funct3: int) -> int:
    return (
        (((imm >> 12) & 1) << 31)
        | (((imm >> 5) & 0x3F) << 25)
        | (reg_num(rs2) << 20)
        | (reg_num(rs1) << 15)
        | ((funct3 & 7) << 12)
        | (((imm >> 1) & 0xF) << 8)
        | (((imm >> 11) & 1) << 7)
        | 0x63
    )


def u_type(imm: int, rd: str, opcode: int) -> int:
    return (imm & 0xFFFFF000) | (reg_num(rd) << 7) | opcode


def j_type(imm: int, rd: str) -> int:
    return (
        (((imm >> 20) & 1) << 31)
        | (((imm >> 1) & 0x3FF) << 21)
        | (((imm >> 11) & 1) << 20)
        | (((imm >> 12) & 0xFF) << 12)
        | (reg_num(rd) << 7)
        | 0x6F
    )


@dataclass
class InstructionSpec:
    name: str
    category: str
    fmt: str
    fields: tuple[str, ...]
    note: str = ""


SPECS: dict[str, InstructionSpec] = {
    # Pseudo/directives
    "label": InstructionSpec("label", "Directive", "label name", ("label",), "Defines a target address."),
    "nop": InstructionSpec("nop", "Pseudo", "nop", (), "Expands to addi zero,zero,0."),
    "li": InstructionSpec("li", "Pseudo", "li rd, imm32", ("rd", "imm"), "Expands to lui/addi if needed."),
    "j": InstructionSpec("j", "Pseudo", "j label", ("target",), "Expands to jal zero,label."),
    "call": InstructionSpec("call", "Pseudo", "call label", ("target",), "Expands to jal ra,label."),
    "ret": InstructionSpec("ret", "Pseudo", "ret", (), "Expands to jalr zero,0(ra)."),
    # RV32I R type
    "add": InstructionSpec("add", "R", "add rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "sub": InstructionSpec("sub", "R", "sub rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "sll": InstructionSpec("sll", "R", "sll rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "slt": InstructionSpec("slt", "R", "slt rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "sltu": InstructionSpec("sltu", "R", "sltu rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "xor": InstructionSpec("xor", "R", "xor rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "srl": InstructionSpec("srl", "R", "srl rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "sra": InstructionSpec("sra", "R", "sra rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "or": InstructionSpec("or", "R", "or rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "and": InstructionSpec("and", "R", "and rd, rs1, rs2", ("rd", "rs1", "rs2")),
    # RV32M
    "mul": InstructionSpec("mul", "M", "mul rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "mulh": InstructionSpec("mulh", "M", "mulh rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "mulhsu": InstructionSpec("mulhsu", "M", "mulhsu rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "mulhu": InstructionSpec("mulhu", "M", "mulhu rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "div": InstructionSpec("div", "M", "div rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "divu": InstructionSpec("divu", "M", "divu rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "rem": InstructionSpec("rem", "M", "rem rd, rs1, rs2", ("rd", "rs1", "rs2")),
    "remu": InstructionSpec("remu", "M", "remu rd, rs1, rs2", ("rd", "rs1", "rs2")),
    # RV32I I type
    "addi": InstructionSpec("addi", "I", "addi rd, rs1, imm12", ("rd", "rs1", "imm")),
    "slti": InstructionSpec("slti", "I", "slti rd, rs1, imm12", ("rd", "rs1", "imm")),
    "sltiu": InstructionSpec("sltiu", "I", "sltiu rd, rs1, imm12", ("rd", "rs1", "imm")),
    "xori": InstructionSpec("xori", "I", "xori rd, rs1, imm12", ("rd", "rs1", "imm")),
    "ori": InstructionSpec("ori", "I", "ori rd, rs1, imm12", ("rd", "rs1", "imm")),
    "andi": InstructionSpec("andi", "I", "andi rd, rs1, imm12", ("rd", "rs1", "imm")),
    "slli": InstructionSpec("slli", "I-shift", "slli rd, rs1, shamt", ("rd", "rs1", "shamt")),
    "srli": InstructionSpec("srli", "I-shift", "srli rd, rs1, shamt", ("rd", "rs1", "shamt")),
    "srai": InstructionSpec("srai", "I-shift", "srai rd, rs1, shamt", ("rd", "rs1", "shamt")),
    "jalr": InstructionSpec("jalr", "I", "jalr rd, offset(rs1)", ("rd", "offset", "rs1")),
    # Loads
    "lb": InstructionSpec("lb", "Load", "lb rd, offset(rs1)", ("rd", "offset", "rs1")),
    "lh": InstructionSpec("lh", "Load", "lh rd, offset(rs1)", ("rd", "offset", "rs1")),
    "lw": InstructionSpec("lw", "Load", "lw rd, offset(rs1)", ("rd", "offset", "rs1")),
    "lbu": InstructionSpec("lbu", "Load", "lbu rd, offset(rs1)", ("rd", "offset", "rs1")),
    "lhu": InstructionSpec("lhu", "Load", "lhu rd, offset(rs1)", ("rd", "offset", "rs1")),
    # Stores
    "sb": InstructionSpec("sb", "Store", "sb rs2, offset(rs1)", ("rs2", "offset", "rs1")),
    "sh": InstructionSpec("sh", "Store", "sh rs2, offset(rs1)", ("rs2", "offset", "rs1")),
    "sw": InstructionSpec("sw", "Store", "sw rs2, offset(rs1)", ("rs2", "offset", "rs1")),
    # U/J/B
    "lui": InstructionSpec("lui", "U", "lui rd, imm20", ("rd", "imm20")),
    "auipc": InstructionSpec("auipc", "U", "auipc rd, imm20", ("rd", "imm20")),
    "jal": InstructionSpec("jal", "J", "jal rd, label", ("rd", "target")),
    "beq": InstructionSpec("beq", "B", "beq rs1, rs2, label", ("rs1", "rs2", "target")),
    "bne": InstructionSpec("bne", "B", "bne rs1, rs2, label", ("rs1", "rs2", "target")),
    "blt": InstructionSpec("blt", "B", "blt rs1, rs2, label", ("rs1", "rs2", "target")),
    "bge": InstructionSpec("bge", "B", "bge rs1, rs2, label", ("rs1", "rs2", "target")),
    "bltu": InstructionSpec("bltu", "B", "bltu rs1, rs2, label", ("rs1", "rs2", "target")),
    "bgeu": InstructionSpec("bgeu", "B", "bgeu rs1, rs2, label", ("rs1", "rs2", "target")),
    # CSR/system
    "csrrw": InstructionSpec("csrrw", "CSR", "csrrw rd, csr, rs1", ("rd", "csr", "rs1")),
    "csrrs": InstructionSpec("csrrs", "CSR", "csrrs rd, csr, rs1", ("rd", "csr", "rs1")),
    "csrrc": InstructionSpec("csrrc", "CSR", "csrrc rd, csr, rs1", ("rd", "csr", "rs1")),
    "csrrwi": InstructionSpec("csrrwi", "CSR-imm", "csrrwi rd, csr, imm5", ("rd", "csr", "imm")),
    "csrrsi": InstructionSpec("csrrsi", "CSR-imm", "csrrsi rd, csr, imm5", ("rd", "csr", "imm")),
    "csrrci": InstructionSpec("csrrci", "CSR-imm", "csrrci rd, csr, imm5", ("rd", "csr", "imm")),
    "mret": InstructionSpec("mret", "System", "mret", ()),
}

OPCODE_TITLES = {
    "add": "加法",
    "addi": "立即数加法",
    "and": "按位与",
    "andi": "立即数按位与",
    "auipc": "PC 加高位立即数",
    "beq": "相等分支",
    "bge": "大于等于分支",
    "bgeu": "无符号大于等于分支",
    "blt": "小于分支",
    "bltu": "无符号小于分支",
    "bne": "不等分支",
    "call": "调用标签",
    "csrrc": "CSR 清位",
    "csrrci": "CSR 立即数清位",
    "csrrs": "CSR 置位",
    "csrrsi": "CSR 立即数置位",
    "csrrw": "CSR 写入",
    "csrrwi": "CSR 立即数写入",
    "div": "有符号除法",
    "divu": "无符号除法",
    "j": "无条件跳转",
    "jal": "跳转并链接",
    "jalr": "寄存器跳转并链接",
    "label": "定义标签",
    "lb": "读字节",
    "lbu": "读无符号字节",
    "lh": "读半字",
    "lhu": "读无符号半字",
    "li": "加载立即数",
    "lui": "加载高位立即数",
    "lw": "读字",
    "mret": "机器模式异常返回",
    "mul": "乘法低 32 位",
    "mulh": "有符号乘法高 32 位",
    "mulhsu": "有符号乘无符号高 32 位",
    "mulhu": "无符号乘法高 32 位",
    "nop": "空操作",
    "or": "按位或",
    "ori": "立即数按位或",
    "rem": "有符号取余",
    "remu": "无符号取余",
    "ret": "函数返回",
    "sb": "写字节",
    "sh": "写半字",
    "sll": "逻辑左移",
    "slli": "立即数逻辑左移",
    "slt": "有符号小于置位",
    "slti": "立即数有符号小于置位",
    "sltiu": "立即数无符号小于置位",
    "sltu": "无符号小于置位",
    "sra": "算术右移",
    "srai": "立即数算术右移",
    "srl": "逻辑右移",
    "srli": "立即数逻辑右移",
    "sub": "减法",
    "sw": "写字",
    "xor": "按位异或",
    "xori": "立即数按位异或",
}

OPCODE_DETAILS = {
    "add": "rd = rs1 + rs2。用于两个寄存器整数相加。",
    "addi": "rd = rs1 + imm。最常用的立即数运算，也常用于给寄存器赋小常数。",
    "and": "rd = rs1 & rs2。逐位与操作，常用于掩码。",
    "andi": "rd = rs1 & imm。用立即数作为掩码。",
    "auipc": "rd = PC + (imm20 << 12)。常用于生成与当前 PC 相关的地址。",
    "beq": "如果 rs1 == rs2，则跳转到目标标签。",
    "bge": "有符号比较，如果 rs1 >= rs2，则跳转。",
    "bgeu": "无符号比较，如果 rs1 >= rs2，则跳转。",
    "blt": "有符号比较，如果 rs1 < rs2，则跳转。",
    "bltu": "无符号比较，如果 rs1 < rs2，则跳转。",
    "bne": "如果 rs1 != rs2，则跳转到目标标签。",
    "call": "伪指令，展开为 jal ra,label，用于调用子程序。",
    "csrrc": "读取 CSR 到 rd，并用 rs1 中为 1 的位清除 CSR。",
    "csrrci": "读取 CSR 到 rd，并用 imm5 清除 CSR 中对应位。",
    "csrrs": "读取 CSR 到 rd，并用 rs1 中为 1 的位置位 CSR。",
    "csrrsi": "读取 CSR 到 rd，并用 imm5 置位 CSR 中对应位。",
    "csrrw": "读取 CSR 到 rd，并把 rs1 写入 CSR。",
    "csrrwi": "读取 CSR 到 rd，并把 imm5 写入 CSR。",
    "div": "有符号整数除法，rd = rs1 / rs2。",
    "divu": "无符号整数除法，rd = rs1 / rs2。",
    "j": "伪指令，展开为 jal x0,label，只跳转不保存返回地址。",
    "jal": "跳转到标签，并把返回地址写入 rd。",
    "jalr": "跳转到 rs1 + offset，并把返回地址写入 rd。",
    "label": "定义一个跳转目标地址，本身不生成机器码。",
    "lb": "从内存读取 8 位有符号字节，符号扩展到 rd。",
    "lbu": "从内存读取 8 位无符号字节，零扩展到 rd。",
    "lh": "从内存读取 16 位有符号半字，符号扩展到 rd。",
    "lhu": "从内存读取 16 位无符号半字，零扩展到 rd。",
    "li": "伪指令，用一条 addi 或 lui+addi 把 32 位常数放入 rd。",
    "lui": "rd = imm20 << 12。常用于构造 32 位常数的高 20 位。",
    "lw": "从内存读取 32 位字到 rd。",
    "mret": "从机器模式异常/中断返回，PC 回到 mepc。",
    "mul": "有符号/无符号低位乘法，rd 取乘积低 32 位。",
    "mulh": "有符号乘法，rd 取乘积高 32 位。",
    "mulhsu": "rs1 有符号、rs2 无符号乘法，rd 取乘积高 32 位。",
    "mulhu": "无符号乘法，rd 取乘积高 32 位。",
    "nop": "伪指令，展开为 addi x0,x0,0，不改变状态。",
    "or": "rd = rs1 | rs2。逐位或操作。",
    "ori": "rd = rs1 | imm。立即数逐位或。",
    "rem": "有符号整数取余，rd = rs1 % rs2。",
    "remu": "无符号整数取余，rd = rs1 % rs2。",
    "ret": "伪指令，展开为 jalr x0,0(ra)，从子程序返回。",
    "sb": "把 rs2 的低 8 位写入内存。",
    "sh": "把 rs2 的低 16 位写入内存。",
    "sll": "rd = rs1 << rs2[4:0]。逻辑左移。",
    "slli": "rd = rs1 << shamt。立即数逻辑左移。",
    "slt": "有符号比较，rs1 < rs2 时 rd=1，否则 rd=0。",
    "slti": "有符号比较，rs1 < imm 时 rd=1，否则 rd=0。",
    "sltiu": "无符号比较，rs1 < imm 时 rd=1，否则 rd=0。",
    "sltu": "无符号比较，rs1 < rs2 时 rd=1，否则 rd=0。",
    "sra": "算术右移，保留符号位。",
    "srai": "立即数算术右移，保留符号位。",
    "srl": "逻辑右移，高位补 0。",
    "srli": "立即数逻辑右移，高位补 0。",
    "sub": "rd = rs1 - rs2。两个寄存器整数相减。",
    "sw": "把 rs2 的 32 位数据写入内存。",
    "xor": "rd = rs1 ^ rs2。逐位异或。",
    "xori": "rd = rs1 ^ imm。立即数逐位异或。",
}

ORDERED_INSTRUCTIONS = sorted(SPECS.keys())
OPCODE_DISPLAY_VALUES = [f"{name}（{OPCODE_TITLES.get(name, '指令')}）" for name in ORDERED_INSTRUCTIONS]
DISPLAY_TO_OPCODE = {display: name for display, name in zip(OPCODE_DISPLAY_VALUES, ORDERED_INSTRUCTIONS)}


@dataclass
class ProgramEntry:
    name: str
    args: dict[str, str]

    def display(self) -> str:
        spec = SPECS[self.name]
        values = {field: self.args.get(field, "") for field in spec.fields}
        if self.name == "label":
            return f"{values['label']}:"
        if not spec.fields:
            return self.name
        if self.name in {"lb", "lh", "lw", "lbu", "lhu"}:
            return f"{self.name} {values['rd']},{values['offset']}({values['rs1']})"
        if self.name in {"sb", "sh", "sw"}:
            return f"{self.name} {values['rs2']},{values['offset']}({values['rs1']})"
        if self.name == "jalr":
            return f"jalr {values['rd']},{values['offset']}({values['rs1']})"
        if self.name in {"beq", "bne", "blt", "bge", "bltu", "bgeu"}:
            return f"{self.name} {values['rs1']},{values['rs2']},{values['target']}"
        if self.name in {"j", "call"}:
            return f"{self.name} {values['target']}"
        if self.name == "li":
            return f"li {values['rd']},{values['imm']}"
        if self.name == "jal":
            return f"jal {values['rd']},{values['target']}"
        if "csr" in spec.fields:
            parts = [values[field] for field in spec.fields]
            return f"{self.name} " + ",".join(parts)
        return f"{self.name} " + ",".join(values[field] for field in spec.fields)


class Assembler:
    def __init__(self, entries: list[ProgramEntry]):
        self.entries = entries
        self.prog: list[int] = []
        self.labels: dict[str, int] = {}
        self.fixups: list[tuple[int, str, str, str, str | None, int | None]] = []
        self.listing: list[tuple[int | None, int | None, str]] = []

    def pc(self) -> int:
        return len(self.prog) * 4

    def emit(self, word: int, asm: str) -> None:
        self.prog.append(word & 0xFFFFFFFF)
        self.listing.append((self.pc() - 4, word & 0xFFFFFFFF, asm))

    def define_label(self, name: str) -> None:
        if not name:
            raise ValueError("label name is empty")
        if name in self.labels:
            raise ValueError(f"duplicate label: {name}")
        self.labels[name] = self.pc()
        self.listing.append((None, None, f"{name}:"))

    def assemble(self) -> tuple[list[int], str]:
        for entry in self.entries:
            self.assemble_entry(entry)
        self.resolve_fixups()
        if len(self.prog) > BOOT_WORDS:
            raise ValueError(f"boot image too large: {len(self.prog)} words")
        padded = self.prog + [0] * (BOOT_WORDS - len(self.prog))
        listing_lines = []
        for addr, _word, asm in self.listing:
            if addr is None:
                listing_lines.append(asm)
            else:
                listing_lines.append(f"{addr:08x}: {self.prog[addr // 4]:08x}  {asm}")
        return padded, "\n".join(listing_lines) + "\n"

    def assemble_entry(self, entry: ProgramEntry) -> None:
        name = entry.name
        a = entry.args
        if name == "label":
            self.define_label(a["label"].strip())
        elif name == "nop":
            self.emit(i_type(0, "zero", 0, "zero", 0x13), "nop")
        elif name == "li":
            self.emit_li(a["rd"], parse_int(a["imm"]))
        elif name == "j":
            self.fixups.append((len(self.prog), "jal", a["target"].strip(), "zero", None, None))
            self.emit(0, f"j {a['target']}")
        elif name == "call":
            self.fixups.append((len(self.prog), "jal", a["target"].strip(), "ra", None, None))
            self.emit(0, f"call {a['target']}")
        elif name == "ret":
            self.emit(i_type(0, "ra", 0, "zero", 0x67), "ret")
        elif name in R_FUNCTS:
            funct7, funct3 = R_FUNCTS[name]
            self.emit(r_type(funct7, a["rs2"], a["rs1"], funct3, a["rd"]), entry.display())
        elif name in I_FUNCTS:
            funct3 = I_FUNCTS[name]
            self.emit(i_type(parse_int(a["imm"]), a["rs1"], funct3, a["rd"], 0x13), entry.display())
        elif name in SHIFT_IMM:
            funct7, funct3 = SHIFT_IMM[name]
            shamt = parse_int(a["shamt"]) & 0x1F
            self.emit(i_type((funct7 << 5) | shamt, a["rs1"], funct3, a["rd"], 0x13), entry.display())
        elif name in LOAD_FUNCTS:
            self.emit(i_type(parse_int(a["offset"]), a["rs1"], LOAD_FUNCTS[name], a["rd"], 0x03), entry.display())
        elif name in STORE_FUNCTS:
            self.emit(s_type(parse_int(a["offset"]), a["rs2"], a["rs1"], STORE_FUNCTS[name]), entry.display())
        elif name == "lui":
            self.emit(u_type(parse_int(a["imm20"]) << 12, a["rd"], 0x37), entry.display())
        elif name == "auipc":
            self.emit(u_type(parse_int(a["imm20"]) << 12, a["rd"], 0x17), entry.display())
        elif name == "jalr":
            self.emit(i_type(parse_int(a["offset"]), a["rs1"], 0, a["rd"], 0x67), entry.display())
        elif name == "jal":
            self.fixups.append((len(self.prog), "jal", a["target"].strip(), a["rd"], None, None))
            self.emit(0, entry.display())
        elif name in BRANCH_FUNCTS:
            self.fixups.append((len(self.prog), "branch", a["target"].strip(), a["rs1"], a["rs2"], BRANCH_FUNCTS[name]))
            self.emit(0, entry.display())
        elif name in CSR_FUNCTS:
            csr = parse_int(a["csr"])
            if name in {"csrrwi", "csrrsi", "csrrci"}:
                imm = parse_int(a["imm"]) & 0x1F
                self.emit(((csr & 0xFFF) << 20) | (imm << 15) | (CSR_FUNCTS[name] << 12) | (reg_num(a["rd"]) << 7) | 0x73, entry.display())
            else:
                self.emit(((csr & 0xFFF) << 20) | (reg_num(a["rs1"]) << 15) | (CSR_FUNCTS[name] << 12) | (reg_num(a["rd"]) << 7) | 0x73, entry.display())
        elif name == "mret":
            self.emit(0x30200073, "mret")
        else:
            raise ValueError(f"unsupported instruction: {name}")

    def emit_li(self, rd: str, value: int) -> None:
        value &= 0xFFFFFFFF
        hi = (value + 0x800) >> 12
        lo = value - ((hi & 0xFFFFF) << 12)
        if hi & 0xFFFFF:
            self.emit(u_type((hi & 0xFFFFF) << 12, rd, 0x37), f"li {rd},0x{value:08x}  # lui")
            if lo:
                self.emit(i_type(lo, rd, 0, rd, 0x13), f"li {rd},0x{value:08x}  # addi {lo}")
        else:
            self.emit(i_type(lo, "zero", 0, rd, 0x13), f"li {rd},{value}")

    def resolve_fixups(self) -> None:
        for index, kind, target, a, b, funct3 in self.fixups:
            if target not in self.labels:
                raise ValueError(f"unknown label target: {target}")
            here = index * 4
            dest = self.labels[target]
            off = dest - here
            if kind == "branch":
                if off % 2:
                    raise ValueError(f"unaligned branch target: {target}")
                self.prog[index] = b_type(off, b or "zero", a, funct3 or 0)
            elif kind == "jal":
                if off % 2:
                    raise ValueError(f"unaligned jal target: {target}")
                self.prog[index] = j_type(off, a)


R_FUNCTS = {
    "add": (0x00, 0),
    "sub": (0x20, 0),
    "sll": (0x00, 1),
    "slt": (0x00, 2),
    "sltu": (0x00, 3),
    "xor": (0x00, 4),
    "srl": (0x00, 5),
    "sra": (0x20, 5),
    "or": (0x00, 6),
    "and": (0x00, 7),
    "mul": (0x01, 0),
    "mulh": (0x01, 1),
    "mulhsu": (0x01, 2),
    "mulhu": (0x01, 3),
    "div": (0x01, 4),
    "divu": (0x01, 5),
    "rem": (0x01, 6),
    "remu": (0x01, 7),
}
I_FUNCTS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_IMM = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOAD_FUNCTS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORE_FUNCTS = {"sb": 0, "sh": 1, "sw": 2}
BRANCH_FUNCTS = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}
CSR_FUNCTS = {"csrrw": 1, "csrrs": 2, "csrrc": 3, "csrrwi": 5, "csrrsi": 6, "csrrci": 7}


class BuilderApp:
    """Modern Chinese UI shell for the existing boot-ROM assembler."""

    UI_FONT = ("Microsoft YaHei UI", 10)
    UI_FONT_BOLD = ("Microsoft YaHei UI", 10, "bold")
    TITLE_FONT = ("Microsoft YaHei UI", 21, "bold")
    SECTION_FONT = ("Microsoft YaHei UI", 12, "bold")
    CODE_FONT = ("Consolas", 10)

    FIELD_LABELS = {
        "rd": "目标寄存器 rd",
        "rs1": "源寄存器 rs1",
        "rs2": "源寄存器 rs2",
        "imm": "立即数 imm",
        "offset": "偏移量 offset",
        "imm20": "高 20 位 imm20",
        "shamt": "移位量 shamt",
        "target": "目标标签 target",
        "label": "标签名 label",
        "csr": "CSR 寄存器",
    }

    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("BUPT RISC-V Instruction Studio")
        self.root.geometry("1260x800")
        self.root.minsize(1060, 680)

        self.repo = Path(__file__).resolve().parents[1]
        self.entries: list[ProgramEntry] = []
        self.field_vars: dict[str, tk.StringVar] = {}
        self.field_widgets: dict[str, ttk.Widget] = {}
        self.clear_pending = False

        self.instr_var = tk.StringVar(value=self.opcode_display("addi"))
        self.format_var = tk.StringVar()
        self.note_var = tk.StringVar()
        self.status_var = tk.StringVar(value="就绪")
        self.word_count_var = tk.StringVar(value=f"0 / {BOOT_WORDS} words")

        self.mem_path = self.repo / "src" / "bupt_riscv" / "bupt_riscv_boot.mem"
        self.lst_path = self.repo / "software" / "bupt_riscv" / "gen_bupt_boot.lst"

        self.configure_style()
        self.build_ui()
        self.on_instruction_change()
        self.refresh_tree()
        self.set_status("就绪：程序列表为空，可添加指令或加载 LED 示例。")

    def configure_style(self) -> None:
        self.colors = {
            "bg": "#edf2f7",
            "surface": "#ffffff",
            "surface_2": "#f8fafc",
            "ink": "#172033",
            "muted": "#5f6f86",
            "subtle": "#8a97aa",
            "line": "#d7e0eb",
            "blue": "#2563eb",
            "blue_dark": "#1d4ed8",
            "blue_soft": "#eaf2ff",
            "green": "#047857",
            "red": "#be123c",
            "red_soft": "#fff1f2",
            "status": "#e7eef8",
        }

        self.root.configure(bg=self.colors["bg"])
        style = ttk.Style()
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass

        style.configure(".", font=self.UI_FONT, background=self.colors["bg"], foreground=self.colors["ink"])
        style.configure("Shell.TFrame", background=self.colors["bg"])
        style.configure("Header.TFrame", background=self.colors["surface"], borderwidth=1, relief="solid")
        style.configure("Card.TFrame", background=self.colors["surface"], borderwidth=1, relief="solid")
        style.configure("Inner.TFrame", background=self.colors["surface"])
        style.configure("HeaderTitle.TLabel", background=self.colors["surface"], foreground=self.colors["ink"], font=self.TITLE_FONT)
        style.configure("HeaderSub.TLabel", background=self.colors["surface"], foreground=self.colors["muted"], font=self.UI_FONT)
        style.configure("Counter.TLabel", background=self.colors["blue_soft"], foreground=self.colors["blue"], padding=(14, 8), font=self.UI_FONT_BOLD)
        style.configure("Section.TLabel", background=self.colors["surface"], foreground=self.colors["ink"], font=self.SECTION_FONT)
        style.configure("Hint.TLabel", background=self.colors["surface"], foreground=self.colors["muted"], font=self.UI_FONT)
        style.configure("Field.TLabel", background=self.colors["surface"], foreground=self.colors["muted"], font=("Microsoft YaHei UI", 9, "bold"))
        style.configure("Format.TLabel", background=self.colors["blue_soft"], foreground=self.colors["blue"], padding=(13, 10), font=self.CODE_FONT)
        style.configure("Empty.TLabel", background=self.colors["surface"], foreground=self.colors["subtle"], font=("Microsoft YaHei UI", 12))

        style.configure("TEntry", padding=(9, 7), fieldbackground="#ffffff", bordercolor=self.colors["line"], lightcolor=self.colors["line"], darkcolor=self.colors["line"])
        style.configure("TCombobox", padding=(9, 7), fieldbackground="#ffffff", bordercolor=self.colors["line"], lightcolor=self.colors["line"], darkcolor=self.colors["line"])
        style.configure("TSpinbox", padding=(9, 7), fieldbackground="#ffffff", bordercolor=self.colors["line"], lightcolor=self.colors["line"], darkcolor=self.colors["line"])

        style.configure("TButton", padding=(13, 8), borderwidth=0, font=self.UI_FONT)
        style.map("TButton", background=[("active", "#e8eef8")])
        style.configure("Primary.TButton", background=self.colors["blue"], foreground="#ffffff", padding=(16, 10), borderwidth=0, font=self.UI_FONT_BOLD)
        style.map("Primary.TButton", background=[("active", self.colors["blue_dark"])], foreground=[("active", "#ffffff")])
        style.configure("Soft.TButton", background=self.colors["blue_soft"], foreground=self.colors["blue"], padding=(13, 8), borderwidth=0)
        style.map("Soft.TButton", background=[("active", "#dbeafe")])
        style.configure("Danger.TButton", background=self.colors["red_soft"], foreground=self.colors["red"], padding=(13, 8), borderwidth=0)
        style.map("Danger.TButton", background=[("active", "#ffe4e6")])

        style.configure(
            "Program.Treeview",
            background="#ffffff",
            fieldbackground="#ffffff",
            foreground=self.colors["ink"],
            bordercolor=self.colors["line"],
            rowheight=36,
            font=self.CODE_FONT,
        )
        style.configure(
            "Program.Treeview.Heading",
            background="#eef3f8",
            foreground="#475467",
            font=("Microsoft YaHei UI", 10, "bold"),
            padding=(8, 8),
        )
        style.map("Program.Treeview", background=[("selected", "#dbeafe")], foreground=[("selected", self.colors["ink"])])

    def build_ui(self) -> None:
        shell = ttk.Frame(self.root, padding=18, style="Shell.TFrame")
        shell.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        shell.columnconfigure(0, weight=1)
        shell.rowconfigure(1, weight=1)

        header = ttk.Frame(shell, padding=(20, 16), style="Header.TFrame")
        header.grid(row=0, column=0, sticky="ew", pady=(0, 14))
        header.columnconfigure(0, weight=1)
        ttk.Label(header, text="BUPT RISC-V Instruction Studio", style="HeaderTitle.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(
            header,
            text="面向 Nexys4 RISC-V CPU 课程设计的启动 ROM 可视化编辑器",
            style="HeaderSub.TLabel",
        ).grid(row=1, column=0, sticky="w", pady=(5, 0))
        ttk.Label(header, textvariable=self.word_count_var, style="Counter.TLabel").grid(row=0, column=1, rowspan=2, sticky="e")

        content = tk.PanedWindow(
            shell,
            orient=tk.HORIZONTAL,
            sashwidth=8,
            sashrelief=tk.FLAT,
            bg=self.colors["bg"],
            bd=0,
            showhandle=False,
        )
        content.grid(row=1, column=0, sticky="nsew")

        builder = ttk.Frame(content, padding=20, style="Card.TFrame", width=320)
        builder.columnconfigure(0, weight=1)

        ttk.Label(builder, text="指令构建器", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(builder, text="选择操作码，填写当前指令需要的字段，然后加入程序。", style="Hint.TLabel", wraplength=300).grid(
            row=1, column=0, sticky="w", pady=(4, 16)
        )

        ttk.Label(builder, text="操作码 Opcode", style="Field.TLabel").grid(row=2, column=0, sticky="w")
        opcode = ttk.Combobox(builder, textvariable=self.instr_var, values=OPCODE_DISPLAY_VALUES, state="readonly", width=30)
        opcode.grid(row=3, column=0, sticky="ew", pady=(6, 14))
        opcode.bind("<<ComboboxSelected>>", lambda _event: self.on_instruction_change())

        ttk.Label(builder, text="指令格式 Format", style="Field.TLabel").grid(row=4, column=0, sticky="w")
        ttk.Label(builder, textvariable=self.format_var, style="Format.TLabel").grid(row=5, column=0, sticky="ew", pady=(6, 8))
        ttk.Label(builder, textvariable=self.note_var, style="Hint.TLabel", wraplength=300).grid(row=6, column=0, sticky="w")

        self.fields_frame = ttk.Frame(builder, style="Inner.TFrame")
        self.fields_frame.grid(row=7, column=0, sticky="ew", pady=(16, 8))
        self.fields_frame.columnconfigure(0, weight=0)

        actions = ttk.Frame(builder, style="Inner.TFrame")
        actions.grid(row=8, column=0, sticky="ew", pady=(4, 0))
        actions.columnconfigure(0, weight=1)
        ttk.Button(actions, text="添加指令", command=self.add_instruction, style="Primary.TButton").grid(row=0, column=0, sticky="ew")

        two = ttk.Frame(actions, style="Inner.TFrame")
        two.grid(row=1, column=0, sticky="ew", pady=(10, 0))
        two.columnconfigure(0, weight=1)
        two.columnconfigure(1, weight=1)
        ttk.Button(two, text="重置字段", command=self.reset_fields).grid(row=0, column=0, sticky="ew", padx=(0, 8))
        ttk.Button(two, text="插入标签", command=lambda: self.set_opcode("label"), style="Soft.TButton").grid(row=0, column=1, sticky="ew")
        ttk.Button(actions, text="加载 LED 示例", command=self.load_template).grid(row=2, column=0, sticky="ew", pady=(10, 0))
        ttk.Button(actions, text="操作码说明", command=self.open_opcode_reference, style="Soft.TButton").grid(
            row=3, column=0, sticky="ew", pady=(10, 0)
        )

        program = ttk.Frame(content, padding=20, style="Card.TFrame")
        program.columnconfigure(0, weight=1)
        program.rowconfigure(2, weight=1)
        content.add(builder, minsize=270, width=330)
        content.add(program, minsize=520)
        self.main_pane = content
        ttk.Label(program, text="程序预览", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(program, text="地址会随指令增删和 li 展开自动更新。", style="Hint.TLabel").grid(row=1, column=0, sticky="w", pady=(4, 14))

        table_wrap = ttk.Frame(program, style="Inner.TFrame")
        table_wrap.grid(row=2, column=0, sticky="nsew")
        table_wrap.columnconfigure(0, weight=1)
        table_wrap.rowconfigure(0, weight=1)

        columns = ("idx", "addr", "asm")
        self.tree = ttk.Treeview(table_wrap, columns=columns, show="headings", height=16, style="Program.Treeview")
        self.tree.heading("idx", text="#")
        self.tree.heading("addr", text="Address")
        self.tree.heading("asm", text="Assembly")
        self.tree.column("idx", width=44, minwidth=44, anchor=tk.E, stretch=False)
        self.tree.column("addr", width=126, minwidth=104, anchor=tk.E, stretch=False)
        self.tree.column("asm", width=360, minwidth=240, anchor=tk.W, stretch=False)
        self.tree.grid(row=0, column=0, sticky="nsew")
        self.tree.tag_configure("odd", background="#f8fafc")
        self.tree.tag_configure("label", foreground=self.colors["green"])

        scroll = ttk.Scrollbar(table_wrap, orient=tk.VERTICAL, command=self.tree.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.tree.configure(yscrollcommand=scroll.set)
        self.empty_label = ttk.Label(table_wrap, text="还没有指令，先从左侧添加一条。", style="Empty.TLabel")

        program_actions = ttk.Frame(program, style="Inner.TFrame")
        program_actions.grid(row=3, column=0, sticky="ew", pady=(14, 0))
        ttk.Button(program_actions, text="删除", command=self.delete_selected, style="Danger.TButton", width=10).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(program_actions, text="上移", command=lambda: self.move_selected(-1), width=10).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(program_actions, text="下移", command=lambda: self.move_selected(1), width=10).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(program_actions, text="预览 listing", command=self.preview_listing, style="Soft.TButton", width=16).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(program_actions, text="清空", command=self.clear_program, style="Danger.TButton", width=10).pack(side=tk.RIGHT)

        output = ttk.Frame(shell, padding=18, style="Card.TFrame")
        output.grid(row=2, column=0, sticky="ew", pady=(14, 0))
        output.columnconfigure(1, weight=1)
        ttk.Label(output, text="输出文件", style="Section.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 12))

        self.mem_var = tk.StringVar(value=str(self.mem_path))
        self.lst_var = tk.StringVar(value=str(self.lst_path))
        ttk.Label(output, text="MEM", style="Field.TLabel").grid(row=1, column=0, sticky="w", padx=(0, 12), pady=4)
        ttk.Entry(output, textvariable=self.mem_var).grid(row=1, column=1, sticky="ew", padx=(0, 10), pady=4)
        ttk.Button(output, text="浏览", command=lambda: self.pick_path(self.mem_var, ".mem"), width=12).grid(row=1, column=2, pady=4)
        ttk.Label(output, text="LST", style="Field.TLabel").grid(row=2, column=0, sticky="w", padx=(0, 12), pady=4)
        ttk.Entry(output, textvariable=self.lst_var).grid(row=2, column=1, sticky="ew", padx=(0, 10), pady=4)
        ttk.Button(output, text="浏览", command=lambda: self.pick_path(self.lst_var, ".lst"), width=12).grid(row=2, column=2, pady=4)
        ttk.Button(output, text="生成 .mem 和 .lst", command=self.generate_files, style="Primary.TButton").grid(
            row=3, column=1, columnspan=2, sticky="e", pady=(12, 0)
        )

        self.status_label = tk.Label(
            shell,
            textvariable=self.status_var,
            anchor="w",
            bg=self.colors["status"],
            fg=self.colors["muted"],
            padx=14,
            pady=9,
            font=self.UI_FONT,
        )
        self.status_label.grid(row=3, column=0, sticky="ew", pady=(12, 0))

    def opcode_display(self, name: str) -> str:
        return f"{name}（{OPCODE_TITLES.get(name, '指令')}）"

    def current_opcode(self) -> str:
        value = self.instr_var.get()
        return DISPLAY_TO_OPCODE.get(value, value)

    def opcode_reference_text(self, opcode: str) -> str:
        spec = SPECS[opcode]
        fields = "、".join(spec.fields) if spec.fields else "无"
        lines = [
            f"{opcode}（{OPCODE_TITLES.get(opcode, '指令')}）",
            "",
            f"格式：{spec.fmt}",
            f"字段：{fields}",
            "",
            f"功能：{OPCODE_DETAILS.get(opcode, '暂无说明。')}",
        ]
        address_note = self.address_note_for_opcode(opcode)
        if address_note:
            lines.extend(["", f"地址/立即数说明：{address_note}"])
        if opcode in {"label", "li", "j", "call", "ret", "nop"}:
            lines.extend(["", "注意：这是工具层伪指令或辅助项，不是 CPU 直接执行的原生 opcode；生成时会展开为真实机器指令。"])
        return "\n".join(lines)

    def open_opcode_reference(self) -> None:
        if hasattr(self, "opcode_ref_window") and self.opcode_ref_window.winfo_exists():
            self.opcode_ref_window.lift()
            self.opcode_ref_window.focus_force()
            return

        win = tk.Toplevel(self.root)
        self.opcode_ref_window = win
        win.title("操作码说明")
        win.geometry("780x540")
        win.minsize(620, 430)
        win.configure(bg=self.colors["bg"])

        root = ttk.Frame(win, padding=14, style="Shell.TFrame")
        root.pack(fill=tk.BOTH, expand=True)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(2, weight=1)

        ttk.Label(root, text="搜索操作码", style="Field.TLabel").grid(row=0, column=0, sticky="w", padx=(0, 12), pady=(0, 8))
        search_var = tk.StringVar()
        search_entry = ttk.Entry(root, textvariable=search_var, width=22)
        search_entry.grid(row=1, column=0, sticky="new", padx=(0, 12))

        listbox = tk.Listbox(
            root,
            width=30,
            exportselection=False,
            activestyle="none",
            bg="#ffffff",
            fg=self.colors["ink"],
            selectbackground="#dbeafe",
            selectforeground=self.colors["ink"],
            relief=tk.FLAT,
            highlightthickness=1,
            highlightbackground=self.colors["line"],
            font=self.UI_FONT,
        )
        listbox.grid(row=2, column=0, sticky="nsew", padx=(0, 12), pady=(8, 0))

        text_frame = tk.Frame(root, bg="#ffffff", highlightbackground=self.colors["line"], highlightthickness=1)
        text_frame.grid(row=0, column=1, rowspan=3, sticky="nsew")
        text_frame.columnconfigure(0, weight=1)
        text_frame.rowconfigure(0, weight=1)

        detail_text = tk.Text(
            text_frame,
            wrap=tk.WORD,
            width=1,
            bd=0,
            padx=16,
            pady=14,
            bg="#ffffff",
            fg=self.colors["ink"],
            font=self.UI_FONT,
            relief=tk.FLAT,
            cursor="arrow",
        )
        detail_text.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(text_frame, orient=tk.VERTICAL, command=detail_text.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        detail_text.configure(yscrollcommand=scroll.set, state=tk.DISABLED)

        current_items: list[str] = []

        def set_detail(opcode: str) -> None:
            detail_text.configure(state=tk.NORMAL)
            detail_text.delete("1.0", tk.END)
            detail_text.insert("1.0", self.opcode_reference_text(opcode))
            detail_text.configure(state=tk.DISABLED)
            detail_text.yview_moveto(0)

        def refill() -> None:
            query = search_var.get().strip().lower()
            listbox.delete(0, tk.END)
            current_items.clear()
            for display, opcode in zip(OPCODE_DISPLAY_VALUES, ORDERED_INSTRUCTIONS):
                haystack = f"{opcode} {OPCODE_TITLES.get(opcode, '')}".lower()
                if query and query not in haystack:
                    continue
                current_items.append(opcode)
                listbox.insert(tk.END, display)
            if current_items:
                selected = self.current_opcode()
                index = current_items.index(selected) if selected in current_items else 0
                listbox.selection_set(index)
                listbox.activate(index)
                listbox.see(index)
                set_detail(current_items[index])
            else:
                detail_text.configure(state=tk.NORMAL)
                detail_text.delete("1.0", tk.END)
                detail_text.insert("1.0", "没有找到匹配的操作码。")
                detail_text.configure(state=tk.DISABLED)

        def on_select(_event: tk.Event | None = None) -> None:
            sel = listbox.curselection()
            if sel:
                set_detail(current_items[sel[0]])

        def on_mousewheel(event: tk.Event) -> str:
            units = -3 if event.delta > 0 else 3
            detail_text.yview_scroll(units, "units")
            return "break"

        search_var.trace_add("write", lambda *_args: refill())
        listbox.bind("<<ListboxSelect>>", on_select)
        detail_text.bind("<MouseWheel>", on_mousewheel)

        refill()
        search_entry.focus_set()

    def address_note_for_opcode(self, opcode: str) -> str:
        fields = SPECS[opcode].fields
        if opcode in LOAD_FUNCTS or opcode in STORE_FUNCTS or opcode == "jalr":
            return (
                "地址写法：这类指令使用 offset(rs1) 形式。rs1 必须是寄存器，不是地址文本。"
                "如果要访问 GPIO_BASE、UART_BASE 这类绝对地址，先用 li 把地址放入寄存器，"
                "例如 li x4,GPIO_BASE，然后使用 0(x4)。"
            )
        if "target" in fields:
            return "地址写法：跳转/分支目标请填写 label 名称，而不是直接填写十六进制地址。先插入 label，再跳转到它。"
        if "imm" in fields or "imm20" in fields:
            return "立即数/地址字段可以填写十进制、0x 十六进制，也可以填写 GPIO_BASE、UART_BASE、BRAM_BASE 等快捷名。"
        return ""

    def set_status(self, text: str, kind: str = "info") -> None:
        palette = {
            "info": self.colors["muted"],
            "success": self.colors["green"],
            "error": self.colors["red"],
        }
        backgrounds = {
            "info": self.colors["status"],
            "success": "#e8f7ef",
            "error": "#fff1f2",
        }
        self.status_var.set(text)
        if hasattr(self, "status_label"):
            self.status_label.configure(
                fg=palette.get(kind, self.colors["muted"]),
                bg=backgrounds.get(kind, self.colors["status"]),
            )

    def friendly_error(self, exc: Exception) -> str:
        msg = str(exc)
        if "invalid literal for int()" in msg:
            return "数字或地址快捷名无效。可输入十进制、0x 十六进制，或 GPIO_BASE 这类快捷名。"
        if "missing integer" in msg:
            return "缺少数字、立即数或地址。"
        if "unknown register" in msg:
            return "未知寄存器，请使用 x0-x31 或 zero/ra/sp/a0 等别名。"
        if "unknown label target" in msg:
            return "跳转目标标签不存在，请先插入对应 label。"
        if "duplicate label" in msg:
            return "标签名重复，请换一个 label。"
        if "label name is empty" in msg:
            return "标签名不能为空。"
        if "Permission denied" in msg:
            return "输出路径没有写入权限。"
        if "No such file or directory" in msg:
            return "输出路径不存在。"
        return msg

    def reset_fields(self) -> None:
        self.on_instruction_change()
        self.set_status("已重置当前操作码的字段。")

    def set_opcode(self, name: str) -> None:
        self.instr_var.set(self.opcode_display(name))
        self.on_instruction_change()

    def on_instruction_change(self) -> None:
        for child in self.fields_frame.winfo_children():
            child.destroy()
        self.field_vars.clear()
        self.field_widgets.clear()

        opcode = self.current_opcode()
        spec = SPECS[opcode]
        self.format_var.set(spec.fmt)
        self.note_var.set(spec.note)

        if not spec.fields:
            ttk.Label(self.fields_frame, text="这条指令不需要操作数。", style="Hint.TLabel").grid(row=0, column=0, sticky="w")
            return

        for row, field in enumerate(spec.fields):
            ttk.Label(self.fields_frame, text=self.FIELD_LABELS.get(field, field), style="Field.TLabel").grid(
                row=row * 2, column=0, sticky="w", pady=(0, 5)
            )
            var = tk.StringVar()
            if field in {"rd", "rs1", "rs2"}:
                var.set({"rd": "x1", "rs1": "x0", "rs2": "x0"}[field])
                widget: ttk.Widget = ttk.Combobox(self.fields_frame, textvariable=var, values=REGISTER_CHOICES, width=12)
            elif field == "csr":
                var.set("mstatus")
                widget = ttk.Combobox(self.fields_frame, textvariable=var, values=list(CSR_NAMES.keys()) + [hex(v) for v in CSR_NAMES.values()], width=14)
            elif field == "label":
                var.set("start")
                widget = ttk.Entry(self.fields_frame, textvariable=var, width=18)
            elif field == "target":
                var.set("done")
                widget = ttk.Entry(self.fields_frame, textvariable=var, width=18)
            elif field in {"imm", "offset", "imm20"}:
                var.set("0")
                values = list(ADDRESS_NAMES.keys()) + ["0", "1", "4", "8", "12", "0x10000000", "0x80000000"]
                widget = ttk.Combobox(self.fields_frame, textvariable=var, values=values, width=16)
            elif field == "shamt":
                var.set("1")
                widget = ttk.Spinbox(self.fields_frame, textvariable=var, from_=0, to=31, width=10)
            else:
                var.set("")
                widget = ttk.Entry(self.fields_frame, textvariable=var, width=18)
            widget.grid(row=row * 2 + 1, column=0, sticky="w", pady=(0, 11))
            self.field_vars[field] = var
            self.field_widgets[field] = widget

    def add_instruction(self) -> None:
        try:
            name = self.current_opcode()
            spec = SPECS[name]
            args = {field: self.field_vars[field].get().strip() for field in spec.fields}
            entry = ProgramEntry(name, args)
            Assembler(self.entries + [entry]).assemble()
            self.entries.append(entry)
            self.clear_pending = False
            self.refresh_tree()
            self.set_status(f"已添加：{entry.display()}", "success")
        except Exception as exc:
            self.set_status(f"指令无效：{self.friendly_error(exc)}", "error")

    def refresh_tree(self) -> None:
        for item in self.tree.get_children():
            self.tree.delete(item)
        try:
            Assembler(self.entries).assemble()
            addr_map = self.compute_entry_addresses()
            for idx, entry in enumerate(self.entries):
                addr_text = "" if entry.name == "label" else f"{addr_map[idx]:08x}"
                tags = ("label",) if entry.name == "label" else (("odd",) if idx % 2 else ())
                self.tree.insert("", tk.END, iid=str(idx), values=(idx, addr_text, entry.display()), tags=tags)
        except Exception:
            pc = 0
            for idx, entry in enumerate(self.entries):
                addr_text = "" if entry.name == "label" else f"{pc:08x}"
                tags = ("label",) if entry.name == "label" else (("odd",) if idx % 2 else ())
                self.tree.insert("", tk.END, iid=str(idx), values=(idx, addr_text, entry.display()), tags=tags)
                pc += self.entry_word_count(entry) * 4
        self.update_word_count()
        self.update_empty_state()

    def update_empty_state(self) -> None:
        if self.entries:
            self.empty_label.place_forget()
        else:
            self.empty_label.place(relx=0.5, rely=0.48, anchor=tk.CENTER)

    def update_word_count(self) -> None:
        used = sum(self.entry_word_count(entry) for entry in self.entries)
        self.word_count_var.set(f"{used} / {BOOT_WORDS} words")

    def compute_entry_addresses(self) -> list[int]:
        addrs = []
        pc = 0
        for entry in self.entries:
            addrs.append(pc)
            pc += self.entry_word_count(entry) * 4
        return addrs

    def entry_word_count(self, entry: ProgramEntry) -> int:
        if entry.name == "label":
            return 0
        if entry.name == "li":
            value = parse_int(entry.args["imm"]) & 0xFFFFFFFF
            hi = (value + 0x800) >> 12
            lo = value - ((hi & 0xFFFFF) << 12)
            return 2 if (hi & 0xFFFFF) and lo else 1
        return 1

    def selected_index(self) -> int | None:
        sel = self.tree.selection()
        return int(sel[0]) if sel else None

    def delete_selected(self) -> None:
        idx = self.selected_index()
        if idx is None:
            self.set_status("请先选择要删除的指令。")
            return
        removed = self.entries[idx].display()
        del self.entries[idx]
        self.clear_pending = False
        self.refresh_tree()
        self.set_status(f"已删除：{removed}", "success")

    def move_selected(self, delta: int) -> None:
        idx = self.selected_index()
        if idx is None:
            self.set_status("请先选择要移动的指令。")
            return
        new_idx = idx + delta
        if new_idx < 0 or new_idx >= len(self.entries):
            self.set_status("已经到达列表边界。")
            return
        self.entries[idx], self.entries[new_idx] = self.entries[new_idx], self.entries[idx]
        self.clear_pending = False
        self.refresh_tree()
        self.tree.selection_set(str(new_idx))
        self.set_status("指令顺序已更新。", "success")

    def clear_program(self) -> None:
        if not self.entries:
            self.set_status("程序列表已经是空的。")
            return
        if not self.clear_pending:
            self.clear_pending = True
            self.set_status("再次点击“清空”将删除当前程序列表。", "error")
            return
        self.entries.clear()
        self.clear_pending = False
        self.refresh_tree()
        self.set_status("程序列表已清空。", "success")

    def load_template(self) -> None:
        self.entries = [
            ProgramEntry("li", {"rd": "x1", "imm": "5"}),
            ProgramEntry("li", {"rd": "x2", "imm": "7"}),
            ProgramEntry("add", {"rd": "x3", "rs1": "x1", "rs2": "x2"}),
            ProgramEntry("li", {"rd": "x4", "imm": "GPIO_BASE"}),
            ProgramEntry("sw", {"rs2": "x3", "offset": "0", "rs1": "x4"}),
            ProgramEntry("label", {"label": "done"}),
            ProgramEntry("j", {"target": "done"}),
        ]
        self.clear_pending = False
        self.refresh_tree()
        self.set_status("已加载 LED 示例：5 + 7 -> LED", "success")

    def preview_listing(self) -> None:
        try:
            _words, listing = Assembler(self.entries).assemble()
        except Exception as exc:
            self.set_status(f"汇编失败：{self.friendly_error(exc)}", "error")
            return
        win = tk.Toplevel(self.root)
        win.title("Listing 预览")
        win.geometry("900x540")
        win.configure(bg="#0f172a")
        text = tk.Text(win, bg="#0f172a", fg="#dbeafe", insertbackground="#ffffff", font=self.CODE_FONT, padx=16, pady=14, relief=tk.FLAT)
        text.pack(fill=tk.BOTH, expand=True)
        text.insert("1.0", listing)
        text.configure(state=tk.DISABLED)

    def pick_path(self, var: tk.StringVar, suffix: str) -> None:
        path = filedialog.asksaveasfilename(
            initialdir=str(self.repo),
            defaultextension=suffix,
            filetypes=[(suffix.upper(), f"*{suffix}"), ("All files", "*.*")],
        )
        if path:
            var.set(path)
            self.set_status("输出路径已更新。", "success")

    def generate_files(self) -> None:
        try:
            words, listing = Assembler(self.entries).assemble()
            mem_text = self.mem_var.get().strip()
            lst_text = self.lst_var.get().strip()
            if not mem_text or not lst_text:
                raise ValueError("Output path not found.")
            mem_path = Path(mem_text)
            lst_path = Path(lst_text)
            mem_path.parent.mkdir(parents=True, exist_ok=True)
            lst_path.parent.mkdir(parents=True, exist_ok=True)
            mem_path.write_text("\n".join(f"{word:08x}" for word in words) + "\n", encoding="ascii")
            lst_path.write_text(listing, encoding="utf-8")
            self.clear_pending = False
            self.set_status(f"生成成功：已写入 {mem_path.name} 和 {lst_path.name}", "success")
            self.root.update_idletasks()
        except Exception as exc:
            self.set_status(f"生成失败：{self.friendly_error(exc)}", "error")
            self.root.update_idletasks()


def enable_dpi_awareness() -> None:
    """Make Tk render crisply on Windows display scaling."""
    try:
        import ctypes

        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            ctypes.windll.user32.SetProcessDPIAware()
    except Exception:
        pass


def configure_tk_scaling(root: tk.Tk) -> None:
    try:
        root.tk.call("tk", "scaling", root.winfo_fpixels("1i") / 72.0)
    except tk.TclError:
        pass


def main() -> None:
    enable_dpi_awareness()
    root = tk.Tk()
    configure_tk_scaling(root)
    BuilderApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
