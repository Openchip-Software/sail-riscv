#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Generate the IME microscaling (MX) first-party tests.

An independent Python reference of the IME specification pseudocode
(fp_gemm, fp_scaled_gemm, int_scaled_gemm) computes the expected C tiles and
accrued fflags. Each generated test loads A, B, C and v0, runs one matrix
instruction (as a .word encoding), and compares the C register group bytes
and fflags. A failing test exits with the number of the failing case.

Disclosed FP profile mirrored here: G=1, psm=0 (exact), rnd=frm.

Usage:  ime_mx_gen.py [output_dir]      (default: this script's directory)
"""

import os
import random
import sys
from fractions import Fraction

import numpy as np

VLEN = 256
VLENB = VLEN // 8

# fflags bits.
NX, UF, OF, DZ, NV = 0x01, 0x02, 0x04, 0x08, 0x10

# RISC-V frm encodings.
RNE, RTZ, RDN, RUP, RMM = 0, 1, 2, 3, 4
RM_NAMES = {RNE: "rne", RTZ: "rtz", RDN: "rdn", RUP: "rup", RMM: "rmm"}

# Format: (width, exponent bits, mantissa bits).
FMT = {
    "e2m1": (4, 2, 1),
    "e4m3": (8, 4, 3),
    "e5m2": (8, 5, 2),
    "fp16": (16, 5, 10),
    "bf16": (16, 8, 7),
    "fp32": (32, 8, 23),
    "fp64": (64, 11, 52),
}
IEEE_SPECIALS = {"e5m2", "fp16", "bf16", "fp32", "fp64"}

E8M0_BIAS = 127
E8M0_NAN = 0xFF

# ---------------------------------------------------------------------------
# Exact FP values: ("nan",), ("inf", sign), ("fin", sign, Fraction >= 0).
# ---------------------------------------------------------------------------


def bias(fmt):
    return (1 << (FMT[fmt][1] - 1)) - 1


def decode(fmt, v):
    """Decode raw bits; returns (value, is_signaling_nan)."""
    width, eb, mb = FMT[fmt]
    sign = (v >> (width - 1)) & 1
    e = (v >> mb) & ((1 << eb) - 1)
    m = v & ((1 << mb) - 1)
    if fmt in IEEE_SPECIALS and e == (1 << eb) - 1:
        if m == 0:
            return ("inf", sign), False
        quiet = (m >> (mb - 1)) & 1
        return ("nan",), (not quiet and fmt != "e5m2")
    if fmt == "e4m3" and e == 15 and m == 7:
        return ("nan",), False
    if e == 0:
        return ("fin", sign, Fraction(m) * Fraction(2) ** (1 - bias(fmt) - mb)), False
    return ("fin", sign, Fraction((1 << mb) + m) * Fraction(2) ** (e - bias(fmt) - mb)), False


def mul(a, b, fl):
    if a[0] == "nan" or b[0] == "nan":
        return ("nan",)
    if a[0] == "inf" or b[0] == "inf":
        zero = (a[0] == "fin" and a[2] == 0) or (b[0] == "fin" and b[2] == 0)
        if zero:
            fl[0] |= NV
            return ("nan",)
        return ("inf", a[1] ^ b[1])
    return ("fin", a[1] ^ b[1], a[2] * b[2])


def add(a, b, rm, fl):
    if a[0] == "nan" or b[0] == "nan":
        return ("nan",)
    if a[0] == "inf" and b[0] == "inf":
        if a[1] == b[1]:
            return a
        fl[0] |= NV
        return ("nan",)
    if a[0] == "inf":
        return a
    if b[0] == "inf":
        return b
    va = -a[2] if a[1] else a[2]
    vb = -b[2] if b[1] else b[2]
    s = va + vb
    if s > 0:
        return ("fin", 0, s)
    if s < 0:
        return ("fin", 1, -s)
    if a[2] == 0 and b[2] == 0 and a[1] == b[1]:
        return ("fin", a[1], Fraction(0))
    return ("fin", 1 if rm == RDN else 0, Fraction(0))


def pack(fmt, sign, biased, frac):
    width, eb, mb = FMT[fmt]
    return (sign << (width - 1)) | (biased << mb) | frac


def canonical_nan(fmt):
    _, eb, mb = FMT[fmt]
    return pack(fmt, 0, (1 << eb) - 1, 1 << (mb - 1))


def round_int(sign, x, rm):
    """Round non-negative Fraction x to an integer; returns (r, inexact)."""
    r0 = x.numerator // x.denominator
    rem = x - r0
    if rem == 0:
        return r0, False
    half = Fraction(1, 2)
    if rm == RNE:
        up = rem > half or (rem == half and r0 % 2 == 1)
    elif rm == RDN:
        up = sign == 1
    elif rm == RUP:
        up = sign == 0
    elif rm == RMM:
        up = rem >= half
    else:
        up = False
    return r0 + (1 if up else 0), True


def floor_log2(x):
    e = x.numerator.bit_length() - x.denominator.bit_length()
    if Fraction(2) ** e > x:
        e -= 1
    if Fraction(2) ** (e + 1) <= x:
        e += 1
    return e


def rnd(fmt, x, rm, fl):
    """Round an exact value to an IEEE format; tininess after rounding."""
    _, eb, mb = FMT[fmt]
    emax_field = (1 << eb) - 1
    emin = 1 - bias(fmt)
    if x[0] == "nan":
        return canonical_nan(fmt)
    if x[0] == "inf":
        return pack(fmt, x[1], emax_field, 0)
    sign, mag = x[1], x[2]
    if mag == 0:
        return pack(fmt, sign, 0, 0)
    E = floor_log2(mag)
    r_unb, _ = round_int(sign, mag / Fraction(2) ** (E - mb), rm)
    tiny = (E + (1 if r_unb == 1 << (mb + 1) else 0)) < emin
    q = max(E, emin) - mb
    r, inexact = round_int(sign, mag / Fraction(2) ** q, rm)
    if r == 1 << (mb + 1):
        r >>= 1
        q += 1
    normal = r >= 1 << mb
    biased = q + mb + bias(fmt) if normal else 0
    frac = r - (1 << mb) if normal else r
    if biased >= emax_field:
        fl[0] |= OF | NX
        to_inf = rm in (RNE, RMM) or (rm == RUP and sign == 0) or (rm == RDN and sign == 1)
        if to_inf:
            return pack(fmt, sign, emax_field, 0)
        return pack(fmt, sign, emax_field - 1, (1 << mb) - 1)
    if inexact:
        fl[0] |= (UF | NX) if tiny else NX
    return pack(fmt, sign, biased, frac)


def dec_flags(fmt, v, fl):
    x, signaling = decode(fmt, v)
    if signaling:
        fl[0] |= NV
    return x


def fp_add(fmt, a, b, rm, fl):
    return rnd(fmt, add(dec_flags(fmt, a, fl), dec_flags(fmt, b, fl), rm, fl), rm, fl)


def fp_mul(fmt, a, b, rm, fl):
    return rnd(fmt, mul(dec_flags(fmt, a, fl), dec_flags(fmt, b, fl), fl), rm, fl)


def e8m0_decode(fmt, v, fl):
    if v == E8M0_NAN:
        return canonical_nan(fmt)
    return rnd(fmt, ("fin", 0, Fraction(2) ** (v - E8M0_BIAS)), RNE, fl)


def is_nan(fmt, v):
    return decode(fmt, v)[0][0] == "nan"


def self_check():
    """Cross-check rnd() against numpy round-to-nearest-even conversions."""
    rng = random.Random(1)
    for _ in range(20000):
        mant = rng.randrange(1, 1 << 60)
        exp = rng.randrange(-160, 40)
        x = Fraction(mant) * Fraction(2) ** exp
        d = float(x)
        if Fraction(d) != x:
            continue
        for fmt, npt, ut in (("fp16", np.float16, np.uint16), ("fp32", np.float32, np.uint32)):
            fl = [0]
            got = rnd(fmt, ("fin", 0, x), RNE, fl)
            with np.errstate(over="ignore"):
                want = int(np.array([d], dtype=npt).view(ut)[0])
            assert got == want, (fmt, x, hex(got), hex(want))
    for _ in range(5000):
        x = Fraction(rng.randrange(1, 1 << 200), 1 << rng.randrange(0, 400))
        fl = [0]
        got = rnd("fp64", ("fin", 0, x), RNE, fl)
        want = int(np.array([float(x)]).view(np.uint64)[0])
        assert got == want, (x, hex(got), hex(want))


# ---------------------------------------------------------------------------
# Tile geometry and register layout (tile_reg_idx / mat_*_idx).
# ---------------------------------------------------------------------------


def tile_reg_idx(i, group, lam, epr):
    linesize = lam * group
    line, e = divmod(i, linesize)
    return (e // lam) * epr + line * lam + e % lam


class Geom:
    def __init__(self, sew, W, lam, lmul, N):
        self.sew, self.W, self.lam, self.lmul, self.N = sew, W, lam, lmul, N
        self.eew_a = sew // W
        self.K = lam * W * lmul
        self.M = VLEN // (sew * lam)
        self.emul_c = self.M // lam
        self.epr_a = VLEN // self.eew_a
        self.epr_c = VLEN // sew
        self.vl = N * lam * lmul

    def a_idx(self, i, k):
        return tile_reg_idx(i * self.K + k, self.lmul, self.lam * self.W, self.epr_a)

    def b_idx(self, k, j):
        return tile_reg_idx(j * self.K + k, self.lmul, self.lam * self.W, self.epr_a)

    def c_idx(self, i, j):
        return tile_reg_idx(i * self.M + j, self.emul_c, self.lam, self.epr_c)


def put_elem(buf, eew, idx, v):
    """Store element idx of width eew (4..64) into a little-endian bytearray."""
    if eew == 4:
        b = idx // 2
        if idx % 2 == 0:
            buf[b] = (buf[b] & 0xF0) | (v & 0xF)
        else:
            buf[b] = (buf[b] & 0x0F) | ((v & 0xF) << 4)
        return
    nb = eew // 8
    buf[idx * nb:(idx + 1) * nb] = v.to_bytes(nb, "little")


def get_elem(buf, eew, idx):
    if eew == 4:
        b = buf[idx // 2]
        return b & 0xF if idx % 2 == 0 else b >> 4
    nb = eew // 8
    return int.from_bytes(buf[idx * nb:(idx + 1) * nb], "little")


# ---------------------------------------------------------------------------
# Reference GEMMs.
# ---------------------------------------------------------------------------


def block_scales(g, v0, i, j, s, fmt_c, rm, fl):
    R = g.lam * g.sew // 16
    pa = get_elem(v0, 16, i * R + s)
    pb = get_elem(v0, 16, j * R + s)
    sa = e8m0_decode(fmt_c, pa & 0xFF, fl)
    sb = e8m0_decode(fmt_c, pb >> 8, fl)
    blk = fp_mul(fmt_c, sa, sb, rm, fl)
    return blk, is_nan(fmt_c, blk)


def ref_fp_gemm(g, fa, fb, fc, scaled, bs16, rm, A, B, C, v0, fl):
    bsz = (16 if bs16 else 32) if scaled else g.K
    nblk = (g.K + bsz - 1) // bsz
    step_len = g.lam * g.W
    for j in range(g.N):
        for i in range(g.M):
            ci = g.c_idx(i, j)
            acc = get_elem(C, g.sew, ci)
            nan_out = False
            for s in range(nblk):
                blk = None
                if scaled:
                    blk, nan_out = block_scales(g, v0, i, j, s, fc, rm, fl)
                    if nan_out:
                        break
                blo, bhi = s * bsz, min(s * bsz + bsz, g.K) - 1
                for step in range(g.lmul):
                    slo = step * step_len
                    lo, hi = max(slo, blo), min(slo + step_len - 1, bhi)
                    if lo > hi:
                        continue
                    for g0 in range((lo - slo) // g.W, (hi - slo) // g.W + 1):
                        S = ("fin", 0, Fraction(0))
                        for k in range(slo + g0 * g.W, slo + g0 * g.W + g.W):
                            a = dec_flags(fa, get_elem(A, g.eew_a, g.a_idx(i, k)), fl)
                            b = dec_flags(fb, get_elem(B, g.eew_a, g.b_idx(k, j)), fl)
                            S = add(S, mul(a, b, fl), rm, fl)
                        term = rnd(fc, S, rm, fl)
                        if scaled:
                            term = fp_mul(fc, blk, term, rm, fl)
                        acc = fp_add(fc, acc, term, rm, fl)
            put_elem(C, g.sew, ci, canonical_nan(fc) if nan_out else acc)


def sext(v, bits):
    return v - (1 << bits) if v >> (bits - 1) else v


def ref_int_gemm(g, fc, bs16, rm, A, B, C, v0, fl):
    bsz = 16 if bs16 else 32
    nblk = (g.K + bsz - 1) // bsz
    for j in range(g.N):
        for i in range(g.M):
            ci = g.c_idx(i, j)
            acc = get_elem(C, g.sew, ci)
            nan_out = False
            for s in range(nblk):
                blk, nan_out = block_scales(g, v0, i, j, s, fc, rm, fl)
                if nan_out:
                    break
                dot = 0
                for k in range(s * bsz, min(s * bsz + bsz, g.K)):
                    a = sext(get_elem(A, g.eew_a, g.a_idx(i, k)), g.eew_a)
                    b = sext(get_elem(B, g.eew_a, g.b_idx(k, j)), g.eew_a)
                    dot += a * b
                xs = ("fin", 1 if dot < 0 else 0, Fraction(abs(dot)))
                acc = fp_add(fc, acc, fp_mul(fc, blk, rnd(fc, xs, rm, fl), rm, fl), rm, fl)
            put_elem(C, g.sew, ci, canonical_nan(fc) if nan_out else acc)


# ---------------------------------------------------------------------------
# Instruction encodings and vtype.
# ---------------------------------------------------------------------------

FUNCT6 = {
    "vfwmmacc": 0x15, "vfqmmacc": 0x16, "vf8wmmacc": 0x17,
    "vwmmacc": 0x39, "vqmmacc": 0x3a, "v8wmmacc": 0x3b,
    "vfmmacc": 0x14, "vmmacc": 0x38,
}
OPFVV, OPIVV = 1, 0
OP_V = 0x57
VS1, VS2, VD = 8, 16, 24


FP_OPS = ("vfwmmacc", "vfqmmacc", "vf8wmmacc", "vfmmacc")


def encode(op, vm, vs1=VS1, vs2=VS2, vd=VD):
    funct3 = OPFVV if op in FP_OPS else OPIVV
    return (FUNCT6[op] << 26) | (vm << 25) | (vs2 << 20) | (vs1 << 15) | (funct3 << 12) | (vd << 7) | OP_V


LAMBDA_FIELD = {1: 1, 2: 2, 4: 3, 8: 4, 16: 5, 32: 6, 64: 7}
SEW_FIELD = {8: 0, 16: 1, 32: 2, 64: 3}
LMUL_FIELD = {1: 0, 2: 1, 4: 2, 8: 3}


def vtype(sew, lmul, lam, bs16=False, alt_a=0, alt_b=0, alt=0):
    v = LMUL_FIELD[lmul] | (SEW_FIELD[sew] << 3)
    v |= alt << 8
    v |= LAMBDA_FIELD[lam] << 60
    v |= int(bs16) << 59
    v |= alt_a << 58
    v |= alt_b << 57
    return v


# ---------------------------------------------------------------------------
# Test cases.
# ---------------------------------------------------------------------------

# Representative row geometries (VLEN=256), chosen so that K_eff=64 spans
# two BS=32 blocks and four BS=16 blocks; N = M - 1 leaves one tail column.
GEOM = {
    (2, 16): dict(lam=4, lmul=8),
    (4, 16): dict(lam=4, lmul=4),
    (4, 32): dict(lam=2, lmul=8),
    (8, 32): dict(lam=2, lmul=4),
    (8, 64): dict(lam=1, lmul=8),
}

# Integer input instruction per W, and its FP-input sibling.
FP_OP = {2: "vfwmmacc", 4: "vfqmmacc", 8: "vf8wmmacc"}
INT_OP = {2: "vwmmacc", 4: "vqmmacc", 8: "v8wmmacc"}
INT_MNEMONIC = {2: "vfwimmacc", 4: "vfqimmacc", 8: "vf8wimmacc"}

C_FMT = {(16, 0): "fp16", (16, 1): "bf16", (32, 0): "fp32", (64, 0): "fp64"}
IN_FMT = {(4, 0): "e2m1", (8, 0): "e4m3", (8, 1): "e5m2"}


def snan(fmt):
    _, eb, mb = FMT[fmt]
    return pack(fmt, 0, (1 << eb) - 1, 1)


# Per C format: (max input magnitude, Int8 range, E8M0 scale spread around
# 2^0). Chosen so that sums round often but rarely overflow.
RANGES = {
    "fp16": (4, 16, 1),
    "bf16": (64, 128, 6),
    "fp32": (448, 128, 20),
    "fp64": (57344, 128, 60),
}


def rand_input(rng, fmt, limit):
    """A finite input encoding (no NaN/inf) with magnitude <= limit."""
    width = FMT[fmt][0]
    while True:
        v = rng.randrange(0, 1 << width)
        x, _ = decode(fmt, v)
        if x[0] == "fin" and x[2] <= limit:
            return v


def rand_int(rng, eew, int8_range):
    """A signed input of width eew as raw bits; Int8 limited to +-int8_range."""
    lim = (1 << (eew - 1)) if eew == 4 else int8_range
    return rng.randrange(-lim, lim) & ((1 << eew) - 1)


def rand_c(rng, fmt):
    """A finite C value of moderate magnitude."""
    x = ("fin", rng.randrange(2), Fraction(rng.randrange(0, 4096), rng.choice([1, 16, 256])))
    return rnd(fmt, x, RNE, [0])


class Case:
    def __init__(self, title, op, vm, g, vt, rm, A, B, C, v0, expect_c, expect_flags,
                 trap=False, insn=None, pre=(), vl=None):
        self.title, self.op, self.vm, self.g, self.vt, self.rm = title, op, vm, g, vt, rm
        self.A, self.B, self.C, self.v0 = A, B, C, v0
        self.expect_c, self.expect_flags, self.trap = expect_c, expect_flags, trap
        self.insn = insn if insn is not None else encode(op, vm)
        self.pre = list(pre)          # asm run right before the instruction
        self.vl = g.vl if vl is None else vl


def make_data(rng, g, in_fmt, fc, int_inputs=False):
    limit, int8_range, scale_spread = RANGES.get(fc, (4, 16, 1))
    scale_center = E8M0_BIAS
    A = bytearray(g.lmul * VLENB)
    B = bytearray(g.lmul * VLENB)
    C = bytearray(g.emul_c * VLENB)
    v0 = bytearray(VLENB)
    for i in range(g.M):
        for k in range(g.K):
            put_elem(A, g.eew_a, g.a_idx(i, k),
                     rand_int(rng, g.eew_a, int8_range) if int_inputs else rand_input(rng, in_fmt[0], limit))
    for j in range(g.M):
        for k in range(g.K):
            put_elem(B, g.eew_a, g.b_idx(k, j),
                     rand_int(rng, g.eew_a, int8_range) if int_inputs else rand_input(rng, in_fmt[1], limit))
    for i in range(g.M):
        for j in range(g.M):
            # Tail columns hold sNaN: touching them would raise NV.
            if fc in FMT:
                put_elem(C, g.sew, g.c_idx(i, j), rand_c(rng, fc) if j < g.N else snan(fc))
    for p in range(VLEN // 16):
        sa = scale_center + rng.randrange(-scale_spread, scale_spread + 1)
        sb = scale_center + rng.randrange(-scale_spread, scale_spread + 1)
        put_elem(v0, 16, p, sa | (sb << 8))
    return A, B, C, v0


def build_case(rng, W, sew, alts=(0, 0, 0), mode="bs32", rm=RNE, int_inputs=False,
               lam=None, lmul=None, N=None, mutate=None, trap=False, regs=(VS1, VS2, VD),
               pre=(), vl=None, op=None, note=""):
    """One test case. mode: 'vm1', 'bs32', or 'bs16'. A trap case expects an
    illegal-instruction exception and an unchanged C group."""
    alt_a, alt_b, alt = alts
    p = GEOM.get((W, sew), {})
    lam = lam or p["lam"]
    lmul = lmul or p["lmul"]
    M = VLEN // (sew * lam)
    g = Geom(sew, W, lam, lmul, M - 1 if N is None else N)
    fc = C_FMT.get((sew, alt), "none")
    if int_inputs:
        fa = fb = None
        A, B, C, v0 = make_data(rng, g, None, fc, int_inputs=True)
    else:
        fa, fb = IN_FMT.get((g.eew_a, alt_a), "e4m3"), IN_FMT.get((g.eew_a, alt_b), "e4m3")
        A, B, C, v0 = make_data(rng, g, (fa, fb), fc)
    if mutate:
        mutate(g, A, B, C, v0)
    scaled, bs16 = mode != "vm1", mode == "bs16"
    Cx, fl = bytearray(C), [0]
    if not trap and int_inputs:
        ref_int_gemm(g, fc, bs16, rm, A, B, Cx, v0, fl)
    elif not trap:
        ref_fp_gemm(g, fa, fb, fc, scaled, bs16, rm, A, B, Cx, v0, fl)
    if op is None:
        op = INT_OP[W] if int_inputs else FP_OP[W]
    name = INT_MNEMONIC[W] if int_inputs else op
    inputs = f"int{g.eew_a}" if int_inputs else f"{fa}x{fb}"
    title = f"{name} SEW={sew} {inputs}->{fc} {mode} {RM_NAMES.get(rm, rm)}"
    if note:
        title += f" [{note}]"
    vt = vtype(sew, lmul, lam, bs16, alt_a, alt_b, alt)
    vm = 0 if scaled else 1
    insn = encode(op, vm, *regs)
    return Case(title, op, vm, g, vt, rm, A, B, C, v0, Cx, fl[0], trap, insn, pre, vl)


def fp_case(rng, W, sew, alt_a, alt_b, alt, mode, rm):
    return build_case(rng, W, sew, (alt_a, alt_b, alt), mode, rm)


def int_case(rng, W, sew, alt, bs16, rm):
    return build_case(rng, W, sew, (0, 0, alt), "bs16" if bs16 else "bs32", rm, int_inputs=True)


# ---------------------------------------------------------------------------
# Assembly emission.
# ---------------------------------------------------------------------------

HEADER = """#include "common/encoding.h"

# GENERATED by ime_mx_gen.py -- do not edit; rerun the generator instead.
#
{doc}
#
# Each case loads A (v8 group), B (v16 group), C (v24 group) and the E8M0
# scale pairs (v0), sets vtype with vsetvl and frm, runs the instruction,
# and checks the C group bytes and fflags against the Python reference
# (G=1, psm=0, rnd=frm). Tail C columns hold sNaN and must stay unchanged
# without raising NV. A failure exits with the failing case number.

.global main
main:
    mv s11, ra

    li t0, (MSTATUS_VS | MSTATUS_FS)
    csrs mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0
"""

FOOTER = """
    li a0, 0
    mv ra, s11
    ret

fail:
    mv ra, s11
    ret

# Compare a4 bytes at a2 and a3; branch to fail with a0 = s10 on mismatch.
check_bytes:
1:
    beqz a4, 2f
    lbu t1, 0(a2)
    lbu t2, 0(a3)
    bne t1, t2, 3f
    addi a2, a2, 1
    addi a3, a3, 1
    addi a4, a4, -1
    j 1b
2:
    ret
3:
    mv a0, s10
    j fail

# Record mcause in s1 and skip the trapping instruction.
.balign 4
trap_handler:
    csrr s1, mcause
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret
"""


def load_group(lines, label, reg, nregs):
    lines.append(f"    li a1, {nregs * VLENB}")
    lines.append(f"    vsetvli t1, a1, e8, m{nregs}, ta, ma")
    lines.append(f"    la a0, {label}")
    lines.append(f"    vle8.v v{reg}, (a0)")


def emit_case(n, c, lines, data):
    g = c.g
    lines.append("")
    lines.append(f"    # ---- case {n}: {c.title} ----")
    lines.append(f"    li s10, {n}")
    load_group(lines, f"c{n}_a", VS1, g.lmul)
    load_group(lines, f"c{n}_b", VS2, g.lmul)
    load_group(lines, f"c{n}_c", VD, g.emul_c)
    load_group(lines, f"c{n}_v0", 0, 1)
    lines.append(f"    li t0, 0x{c.vt:016x}")
    lines.append(f"    li a1, {c.vl}")
    lines.append("    vsetvl t1, a1, t0")
    lines.append(f"    csrwi frm, {c.rm}")
    lines.append("    csrw fflags, x0")
    lines.append("    li s1, 0")
    lines.extend("    " + x for x in c.pre)
    lines.append(f"    .word 0x{c.insn:08x}")
    lines.append("    csrr s2, fflags")
    if c.trap:
        lines.append("    li t1, CAUSE_ILLEGAL_INSTRUCTION")
        lines.append("    mv a0, s10")
        lines.append("    bne s1, t1, fail")
    else:
        lines.append("    mv a0, s10")
        lines.append("    bnez s1, fail")
        lines.append(f"    li t1, 0x{c.expect_flags:x}")
        lines.append("    bne s2, t1, fail")
    lines.append(f"    li a1, {g.emul_c * VLENB}")
    lines.append(f"    vsetvli t1, a1, e8, m{g.emul_c}, ta, ma")
    lines.append("    la a2, c_out")
    lines.append(f"    vse8.v v{VD}, (a2)")
    lines.append(f"    la a3, c{n}_expect")
    lines.append(f"    li a4, {g.emul_c * VLENB}")
    lines.append("    jal check_bytes")

    for name, buf in (("a", c.A), ("b", c.B), ("c", c.C), ("v0", c.v0), ("expect", c.expect_c)):
        data.append(f"c{n}_{name}:")
        for off in range(0, len(buf), 16):
            data.append("    .byte " + ", ".join(f"0x{b:02x}" for b in buf[off:off + 16]))


def write_test(path, doc, cases):
    lines, data = [HEADER.format(doc=doc)], [".data", ".balign 64", "c_out:", "    .fill 256, 1, 0"]
    for n, c in enumerate(cases, start=1):
        emit_case(n, c, lines, data)
    lines.append(FOOTER)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n" + "\n".join(data) + "\n")


def doc_lines(text):
    return "\n".join("# " + t if t else "#" for t in text.strip("\n").split("\n"))


# ---------------------------------------------------------------------------
# Test files.
# ---------------------------------------------------------------------------

RMS = [RNE, RTZ, RDN, RUP, RMM]


def fp_family(rng, W, sew_rows, modes):
    """All (altfmt_A, altfmt_B, altfmt) rows of the given (SEW, input width)."""
    cases, n = [], 0
    for sew, in_alts, c_alts in sew_rows:
        for alt_a, alt_b in in_alts:
            for alt in c_alts:
                for mode in modes:
                    cases.append(fp_case(rng, W, sew, alt_a, alt_b, alt, mode, RMS[n % len(RMS)]))
                    n += 1
    return cases


OFP8_PAIRS = [(0, 0), (0, 1), (1, 0), (1, 1)]
ALL_MODES = ["vm1", "bs32", "bs16"]
MX_MODES = ["bs32", "bs16"]


E5M2_INF = 0x7C
E5M2_MAX = 0x7B


def set_scale(g, v0, m, s, scale_a=None, scale_b=None):
    """Overwrite the E8M0 scale pair for row/column m, block s."""
    R = g.lam * g.sew // 16
    pair = get_elem(v0, 16, m * R + s)
    if scale_a is not None:
        pair = (pair & 0xFF00) | scale_a
    if scale_b is not None:
        pair = (pair & 0x00FF) | (scale_b << 8)
    put_elem(v0, 16, m * R + s, pair)


def special_cases(rng):
    def nan_scale(g, A, B, C, v0):
        set_scale(g, v0, 0, 1, scale_a=E8M0_NAN)
        for k in range(32, 48):
            put_elem(A, g.eew_a, g.a_idx(0, k), E5M2_MAX)

    def scale_ovf(g, A, B, C, v0):
        set_scale(g, v0, 1, 0, scale_a=0xFE)

    def inf_times_zero(g, A, B, C, v0):
        put_elem(A, g.eew_a, g.a_idx(2, 0), E5M2_INF)
        put_elem(B, g.eew_a, g.b_idx(0, 0), 0x00)

    def tiny_scale(g, A, B, C, v0):
        for p in range(VLEN // 16):
            put_elem(v0, 16, p, 0x0000)

    def bf16_ovf(g, A, B, C, v0):
        set_scale(g, v0, 0, 0, scale_a=0xFE)
        set_scale(g, v0, 1, 0, scale_b=0xFE)

    e5 = (1, 1, 0)
    return [
        build_case(rng, 2, 16, e5, "bs16", RNE, mutate=nan_scale, note="nan-scale"),
        build_case(rng, 2, 16, e5, "bs32", RUP, mutate=scale_ovf, note="scale-ovf"),
        build_case(rng, 2, 16, e5, "vm1", RNE, mutate=inf_times_zero, note="inf*0"),
        build_case(rng, 2, 16, e5, "bs16", RTZ, mutate=inf_times_zero, note="inf*0"),
        build_case(rng, 4, 32, (0, 1, 0), "bs32", RNE, mutate=tiny_scale, note="tiny-scale"),
        build_case(rng, 2, 16, (0, 0, 1), "bs32", RNE, mutate=bf16_ovf, note="bf16-ovf"),
        build_case(rng, 4, 32, (1, 0, 0), "bs32", RDN, lmul=2, note="partial"),
        build_case(rng, 4, 32, (0, 0, 0), "bs32", RMM, int_inputs=True, lmul=2, note="partial"),
        build_case(rng, 8, 64, (0, 0, 0), "bs16", RNE, int_inputs=True, mutate=nan_scale_b, note="nan-scale-b"),
    ]


def nan_scale_b(g, A, B, C, v0):
    """E8M0 NaN as the B scale of column 1, block 3 (last block)."""
    set_scale(g, v0, 1, 3, scale_b=E8M0_NAN)


def illegal_cases(rng):
    T = dict(trap=True)
    return [
        build_case(rng, 2, 8, (0, 0, 0), "bs32", lam=2, lmul=1, note="SEW=8 OFP8 C deferred", **T),
        build_case(rng, 4, 16, (0, 0, 0), "bs32", lmul=8, note="control: BS=32, LMUL=8"),
        build_case(rng, 4, 16, (0, 0, 0), "bs16", lmul=8, note="BS=16 W*LMUL=32>SEW", **T),
        build_case(rng, 2, 16, (0, 0, 0), "bs32", regs=(0, VS2, VD), note="vs1=v0", **T),
        build_case(rng, 2, 16, (0, 0, 0), "bs32", regs=(VS1, 0, VD), note="vs2=v0", **T),
        build_case(rng, 2, 16, (0, 0, 0), "bs32", regs=(VS1, VS2, 0), note="vd=v0", **T),
        build_case(rng, 4, 16, (1, 0, 0), "bs32", note="OFP4 altfmt_A=1", **T),
        build_case(rng, 4, 32, (0, 0, 1), "bs32", note="FP32 C altfmt=1", **T),
        build_case(rng, 4, 32, (0, 0, 1), "vm1", note="FP32 C altfmt=1", **T),
        build_case(rng, 8, 64, (0, 0, 1), "bs16", note="FP64 C altfmt=1", **T),
        build_case(rng, 2, 16, (0, 1, 0), "bs32", int_inputs=True, note="MXINT unsigned B", **T),
        build_case(rng, 2, 32, (0, 0, 0), "bs32", int_inputs=True, lam=2, lmul=1, note="vfwimmacc SEW=32", **T),
        build_case(rng, 4, 64, (0, 0, 0), "bs32", int_inputs=True, lam=1, lmul=1, note="vfqimmacc SEW=64", **T),
        build_case(rng, 2, 32, (0, 0, 0), "bs32", lam=2, lmul=1, note="vfwmmacc FP16->FP32 MX", **T),
        build_case(rng, 2, 16, (0, 0, 0), "bs32", pre=["li t1, 1", "csrw vstart, t1"], note="vstart=1", **T),
        build_case(rng, 2, 16, (0, 0, 0), "bs32", vl=95, note="VL not a multiple", **T),
        build_case(rng, 2, 16, (0, 0, 0), "bs32", pre=["csrwi frm, 5"], note="frm=5", **T),
        build_case(rng, 2, 16, (0, 0, 0), "bs32", int_inputs=True, op="vmmacc", lam=2, lmul=1, note="vmmacc vm=0", **T),
        build_case(rng, 2, 16, (0, 0, 0), "bs32", op="vfmmacc", lam=2, lmul=1, note="vfmmacc vm=0", **T),
    ]


def gate_cases(rng):
    T = dict(trap=True)
    return [
        build_case(rng, 2, 16, (0, 0, 0), "bs32", note="Zvvxofp8fp16mm"),
        build_case(rng, 2, 16, (0, 0, 0), "bs16", note="needs Zvvxnofp8fp16mm", **T),
        build_case(rng, 2, 16, (1, 0, 0), "vm1", note="base implied by MX"),
        build_case(rng, 2, 16, (0, 0, 1), "bs32", note="needs Zvvxofp8bf16mm", **T),
        build_case(rng, 2, 16, (0, 0, 1), "vm1", note="base not implied", **T),
        build_case(rng, 4, 32, (0, 0, 0), "bs16", int_inputs=True, note="Zvvxni8fp32mm"),
        build_case(rng, 4, 32, (0, 0, 0), "bs32", int_inputs=True, note="implied Zvvxi8fp32mm"),
        build_case(rng, 4, 16, (0, 0, 0), "bs32", int_inputs=True, note="needs Zvvxi4fp16mm", **T),
        build_case(rng, 4, 32, (0, 0, 0), "vm1", int_inputs=True, op="vqmmacc", note="vqmmacc needs Zvvmm", **T),
        build_case(rng, 8, 64, (0, 0, 0), "vm1", note="vf8wmmacc needs Zvvfmm", **T),
        build_case(rng, 4, 32, (0, 0, 0), "vm1", note="vfqmmacc base not implied", **T),
    ]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    self_check()
    rng = random.Random(2026)

    files = {
        "test_ime_mx_vfwmmacc.S": (
            "vfwmmacc.vv (W=2), SEW=16: OFP8 E4M3/E5M2 (all A/B pairs) -> FP16/BF16,\n"
            "unscaled (vm=1) and MX with BS=32 and BS=16. lambda=4, LMUL=8, K_eff=64.",
            fp_family(rng, 2, [(16, OFP8_PAIRS, [0, 1])], ALL_MODES)),
        "test_ime_mx_vfqmmacc.S": (
            "vfqmmacc.vv (W=4): SEW=16 OFP4 E2M1 -> FP16/BF16 (lambda=4, LMUL=4) and\n"
            "SEW=32 OFP8 (all A/B pairs) -> FP32 (lambda=2, LMUL=8); unscaled (vm=1)\n"
            "and MX with BS=32 and BS=16. K_eff=64.",
            fp_family(rng, 4, [(16, [(0, 0)], [0, 1]), (32, OFP8_PAIRS, [0])], ALL_MODES)),
        "test_ime_mx_vf8wmmacc.S": (
            "vf8wmmacc.vv (W=8) MX: SEW=32 OFP4 E2M1 -> FP32 (lambda=2, LMUL=4) and\n"
            "SEW=64 OFP8 (all A/B pairs) -> FP64 (lambda=1, LMUL=8); BS=32 and\n"
            "BS=16. K_eff=64.",
            fp_family(rng, 8, [(32, [(0, 0)], [0]), (64, OFP8_PAIRS, [0])], MX_MODES)),
        "test_ime_mx_vfwimmacc.S": (
            "vfwimmacc.vv (vm=0 of vwmmacc, W=2), SEW=16: MXINT8 -> FP16/BF16,\n"
            "BS=32 and BS=16. lambda=4, LMUL=8, K_eff=64.",
            [int_case(rng, 2, 16, alt, bs16, RMS[n % 5])
             for n, (alt, bs16) in enumerate([(0, False), (0, True), (1, False), (1, True)])]),
        "test_ime_mx_vfqimmacc.S": (
            "vfqimmacc.vv (vm=0 of vqmmacc, W=4): SEW=16 MXINT4 -> FP16/BF16\n"
            "(lambda=4, LMUL=4) and SEW=32 MXINT8 -> FP32 (lambda=2, LMUL=8);\n"
            "BS=32 and BS=16. K_eff=64.",
            [int_case(rng, 4, sew, alt, bs16, RMS[n % 5])
             for n, (sew, alt, bs16) in enumerate([(16, 0, False), (16, 0, True), (16, 1, False),
                                                   (16, 1, True), (32, 0, False), (32, 0, True)])]),
        "test_ime_mx_vf8wimmacc.S": (
            "vf8wimmacc.vv (vm=0 of v8wmmacc, W=8): SEW=32 MXINT4 -> FP32\n"
            "(lambda=2, LMUL=4) and SEW=64 MXINT8 -> FP64 (lambda=1, LMUL=8);\n"
            "BS=32 and BS=16. K_eff=64.",
            [int_case(rng, 8, sew, 0, bs16, RMS[n % 5])
             for n, (sew, bs16) in enumerate([(32, False), (32, True), (64, False), (64, True)])]),
    }
    files["test_ime_mx_special.S"] = (
        "MX special values and block edge cases (see each case title):\n"
        "  nan-scale: E8M0 0xFF for A row 0, block 1 -> row 0 is the canonical NaN;\n"
        "    block 2 of row 0 would overflow FP16 (OF) but must not be evaluated.\n"
        "  scale-ovf: E8M0 0xFE (2^127) overflows FP16 -> +inf, OF|NX.\n"
        "  inf*0: E5M2 inf times 0 raises NV and gives NaN (vm=1 and vm=0).\n"
        "  tiny-scale: E8M0 0x00 pairs (2^-254) underflow FP32 to 0, UF|NX.\n"
        "  bf16-ovf: 0xFE x 0xFE = 2^254 overflows BF16.\n"
        "  partial: K_eff=16 is a single partial BS=32 block.",
        special_cases(rng))
    files["test_ime_mx_illegal.S"] = (
        "MX illegal encodings; each must raise illegal-instruction and leave C\n"
        "unchanged (see each case title). Legal controls are interleaved.",
        illegal_cases(rng))
    files["test_ime_mx_gate.S"] = (
        "MX extension gating with ime_mx_gate_override.json, which enables only\n"
        "Zvvxofp8fp16mm (BS=32) and Zvvxni8fp32mm (BS=16, implies BS=32). Base\n"
        "rows are legal only when implied by an enabled MX extension.",
        gate_cases(rng))
    for name, (doc, cases) in files.items():
        write_test(os.path.join(out, name), doc_lines(doc), cases)
        print(f"{name}: {len(cases)} cases")


if __name__ == "__main__":
    main()
