#include "common/encoding.h"

# Decode-gate regression test for the individual IME computational
# extensions (tbl-extensions). ime_member_only_override.json enables only
# Zvvi8mm (integer) and Zvvfp16mm (floating-point); every family flag
# (Zvvmm, Zvvfmm) and every microscaling extension stays at its default
# (false). Before the fix, the encdec `when` guards for IMEVMMACCTYPE and
# IMEVFMMACCTYPE accepted only Ext_Zvvmm / Ext_Zvvfmm, so neither
# instruction decoded at all under this configuration, and
# ime_vtype_fields_enabled() also ignored the individual extensions, so
# vtype.vlambda stayed forced to 0.
#
# Geometry: VLEN=256.
#
# (a) vsetvl requests lambda=2 at e8 and reads it back: with only Zvvi8mm
#     enabled, ime_int_base_any_enabled() now makes
#     ime_vtype_fields_enabled() true, so the lambda write rules apply
#     instead of forcing vlambda to 0.
# (b) vmmacc.vv at SEW=8, lambda=4, LMUL=1 (K_eff=4): decodes because
#     ime_int_base_any_enabled() is true, and ime_int_row_ok(1, 8) is true
#     because Zvvi8mm is enabled. A and B are all-ones, so C[0,0] = K_eff.
# (c) The same vmmacc.vv encoding at SEW=16: still decodes (same decode
#     guard), but ime_int_row_ok(1, 16) requires Ext_Zvvi16mm, which is not
#     enabled, so execute_ime_int_mmacc traps. This shows the per-cell
#     check in execute still rejects a cell the enabled member does not
#     cover.
# (d) vfmmacc.vv FP16 x FP16 -> FP16 at SEW=16, lambda=2, LMUL=1 (K_eff=2):
#     decodes because ime_fp_base_any_enabled() is true, and
#     ime_fp_base_row_ok(1, 16) is true because both inputs are FP16 and
#     Zvvfp16mm is enabled. A and B are all 1.0, so C[0,0] = 2.0 exactly
#     (no rounding).
# (e) The same vfmmacc.vv encoding with B reinterpreted as BF16
#     (altfmt_B = 1): still decodes, but ime_fp16bf16_ext_ok requires both
#     Zvvfp16mm and Zvvbf16mm for a mixed FP16/BF16 input pair, and
#     Zvvbf16mm is not enabled, so execute_ime_fp_engine traps.

.global main
main:
    mv s11, ra

    li t0, (MSTATUS_VS | MSTATUS_FS)
    csrs mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0

    # ---- (a) vsetvl lambda=2 request at e8, LMUL=1, reads back lambda=2 ----
    li a0, 1
    li t0, 0x20000000000000c0  # lambda=2, SEW=8, LMUL=1, ta, ma
    li a1, 1
    vsetvl t2, a1, t0
    csrr t1, vtype
    bne t1, t0, fail

    # ---- (b) vmmacc.vv SEW=8, lambda=4, LMUL=1: executes, C[0,0] = K_eff = 4 ----
    li a0, 2
    li a1, 32
    vsetvli t1, a1, e8, m1, ta, ma
    la t3, b_a8
    vle8.v v8, (t3)
    li a1, 32
    vsetvli t1, a1, e8, m1, ta, ma
    la t3, b_b8
    vle8.v v16, (t3)
    li a1, 64
    vsetvli t1, a1, e8, m2, ta, ma
    la t3, b_c8
    vle8.v v24, (t3)

    li t0, 0x30000000000000c0  # lambda=4, SEW=8, LMUL=1, ta, ma
    li a1, 4
    vsetvl t2, a1, t0
    li s1, 0
    # vmmacc.vv v24, v8, v16 (funct6=0x38, vm=1, vs2=16, vs1=8, vd=24)
    .word 0xe3040c57
    bnez s1, fail

    li a1, 64
    vsetvli t1, a1, e8, m2, ta, ma
    la t3, b_c8out
    vse8.v v24, (t3)
    lbu t0, 0(t3)
    li t1, 4
    bne t0, t1, fail

    # ---- (c) vmmacc.vv SEW=16: still decodes, traps (Zvvi16mm not enabled) ----
    li a0, 3
    li t0, 0x10000000000000c8  # lambda=1, SEW=16, LMUL=1, ta, ma
    li a1, 4
    vsetvl t2, a1, t0
    li s1, 0
    .word 0xe3040c57
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

    # ---- (d) vfmmacc.vv FP16 x FP16 -> FP16, SEW=16, lambda=2, LMUL=1: ----
    # ---- executes, C[0,0] = 2.0 (0x4000), K_eff = 2 terms of 1.0 * 1.0 ----
    li a0, 4
    li a1, 16
    vsetvli t1, a1, e16, m1, ta, ma
    la t3, d_a16
    vle16.v v8, (t3)
    li a1, 16
    vsetvli t1, a1, e16, m1, ta, ma
    la t3, d_b16
    vle16.v v16, (t3)
    li a1, 64
    vsetvli t1, a1, e16, m4, ta, ma
    la t3, d_c16
    vle16.v v24, (t3)

    li t0, 0x20000000000000c8  # lambda=2, SEW=16, LMUL=1, ta, ma
    li a1, 2
    vsetvl t2, a1, t0
    csrwi frm, 0
    csrw fflags, x0
    li s1, 0
    # vfmmacc.vv v24, v8, v16 (funct6=0x14, vm=1, vs2=16, vs1=8, vd=24)
    .word 0x53041c57
    bnez s1, fail

    li a1, 64
    vsetvli t1, a1, e16, m4, ta, ma
    la t3, d_c16out
    vse16.v v24, (t3)
    lh t0, 0(t3)
    li t1, 0x4000
    bne t0, t1, fail

    # ---- (e) vfmmacc.vv FP16 x BF16 -> FP16: still decodes, traps ----
    # ---- (mixed input pair needs Zvvbf16mm too) ----
    li a0, 5
    li t0, 0x22000000000000c8  # lambda=2, SEW=16, LMUL=1, altfmt_B=1, ta, ma
    li a1, 2
    vsetvl t2, a1, t0
    csrwi frm, 0
    csrw fflags, x0
    li s1, 0
    .word 0x53041c57
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

    li a0, 0
    mv ra, s11
    ret

fail:
    mv ra, s11
    ret

# Record mcause in s1 and skip the trapping instruction.
.balign 4
trap_handler:
    csrr s1, mcause
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

.balign 4
b_a8:
    .fill 32, 1, 1
b_b8:
    .fill 32, 1, 1
b_c8:
    .zero 64
b_c8out:
    .zero 64

d_a16:
    .fill 16, 2, 0x3c00
d_b16:
    .fill 16, 2, 0x3c00
d_c16:
    .zero 128
d_c16out:
    .zero 128
