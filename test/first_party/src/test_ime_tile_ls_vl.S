#include "common/encoding.h"

# VL shall be a multiple of effective_lambda * LMUL; a VL that is not raises
# an illegal-instruction exception (spec S:2707-2720). VL=0 is a multiple of
# any linesize, so it stays a legal no-op.
#
# Geometry: VLEN=256, SEW=32, LMUL=1, lambda=2 (L2) => linesize=2; LD=2.
#
# 1. VL=3: vmtl.v, vmttl.v, vmts.v and vmtts.v trap with mcause=2.
# 2. VL=4: vmtl.v does not trap (control).
# 3. VL=0: vmttl.v and vmtts.v do not trap.
# 4. VL=1 (below one line): vmttl.v and vmtts.v trap with mcause=2.
# 5. VLEN=256, SEW=32: lambda=4 (L4) is not permissible (EMUL_C would be
#    256/(32*16), not an integer in {1,2,4,8,16}), so the exact
#    instruction-immediate lambda traps regardless of VL.

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
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

    li s1, 0
    # vmttl.v v8, (a0), a1, L2
    .word 0x56b57407
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

    li s1, 0
    # vmts.v v8, (a0), a1, L2
    .word 0x52b57427
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

    li s1, 0
    # vmtts.v v8, (a0), a1, L2
    .word 0x56b57427
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

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
    li s1, 0
    # vmttl.v v8, (a0), a1, L2
    .word 0x56b57407
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

    li s1, 0
    # vmtts.v v8, (a0), a1, L2
    .word 0x56b57427
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

    # ---- 5. lambda=4 is not permissible at SEW=32, VLEN=256 ----
    vsetivli t0, 4, e32, m1, ta, ma
    li s1, 0
    # vmtl.v v8, (a0), a1, L4
    .word 0x72b57407
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

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
