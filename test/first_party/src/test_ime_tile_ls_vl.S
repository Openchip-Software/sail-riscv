#include "common/encoding.h"

# VL=0 is legal for all tile loads/stores, including the transposing
# forms. A VL that is not a multiple of lambda * LMUL, even one below
# lambda * LMUL, does not trap
# (pending IME TG rule: largest multiple of lambda * LMUL that fits VL).
#
# Geometry: VLEN=256, SEW=32, LMUL=1, lambda=2 (L2) => linesize=2; LD=2.
#
# 1. VL=3: vmtl.v, vmttl.v, vmts.v and vmtts.v do not trap.
# 2. VL=4: vmtl.v does not trap (control).
# 3. VL=0: vmttl.v and vmtts.v do not trap.
# 4. VL=1 (below one line): vmttl.v and vmtts.v do not trap.

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0

    la a0, buf
    li a1, 2

    # ---- 1. VL = 3 (partial line) ----
    vsetivli t0, 3, e32, m1, ta, ma
    li t1, 3
    bne t0, t1, fail

    li s1, 0
    # vmtl.v v8, (a0), a1, L2
    .word 0x52b57407
    bnez s1, fail

    # vmttl.v v8, (a0), a1, L2
    .word 0x56b57407
    bnez s1, fail

    # vmts.v v8, (a0), a1, L2
    .word 0x52b57427
    bnez s1, fail

    # vmtts.v v8, (a0), a1, L2
    .word 0x56b57427
    bnez s1, fail

    # ---- 2. VL = 4 (two whole lines) ----
    vsetivli t0, 4, e32, m1, ta, ma
    li s1, 0
    # vmtl.v v8, (a0), a1, L2
    .word 0x52b57407
    bnez s1, fail

    # ---- 3. VL = 0 (no lines) ----
    vsetivli t0, 0, e32, m1, ta, ma
    li s1, 0
    # vmttl.v v8, (a0), a1, L2
    .word 0x56b57407
    bnez s1, fail

    # vmtts.v v8, (a0), a1, L2
    .word 0x56b57427
    bnez s1, fail

    # ---- 4. VL = 1 (partial line only) ----
    vsetivli t0, 1, e32, m1, ta, ma
    # vmttl.v v8, (a0), a1, L2
    .word 0x56b57407
    bnez s1, fail

    # vmtts.v v8, (a0), a1, L2
    .word 0x56b57427
    bnez s1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

# Record mcause in s1 and skip the trapping instruction.
.balign 4
trap_handler:
    csrr s1, mcause
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

.balign 64
buf:
    .fill 64, 1, 0
