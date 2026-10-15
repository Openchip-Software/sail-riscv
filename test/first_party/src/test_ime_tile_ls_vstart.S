#include "common/encoding.h"

# Tile loads/stores must treat vstart like the base-V loads/stores: an
# out-of-bounds vstart (>= VLMAX) raises an illegal-instruction exception,
# and an in-bounds vstart resumes at element vstart.
#
# Geometry: VLEN=256, SEW=64, LMUL=1 => VLMAX=4; VL=4, lambda=1 (L1), LD=1.
#
# 1. With vstart=4, vmtl.v, vmttl.v, vmts.v and vmtts.v each trap with
#    mcause=2 and leave vstart unchanged.
# 2. With vstart=3, vmtl.v loads only element 3, leaves elements 0-2
#    undisturbed, and resets vstart to 0.

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0

    vsetivli t0, 4, e64, m1, ta, ma
    li t1, 4
    bne t0, t1, fail

    la a0, src_buf
    li a1, 1

    # ---- 1. vstart = VLMAX ----
    li s2, 4
    csrw vstart, s2
    li s1, 0
    # vmtl.v v8, (a0), a1, L1
    .word 0x32b57407
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail
    csrr t0, vstart
    bne t0, s2, fail

    li s1, 0
    # vmttl.v v8, (a0), a1, L1
    .word 0x36b57407
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail
    csrr t0, vstart
    bne t0, s2, fail

    li s1, 0
    # vmts.v v8, (a0), a1, L1
    .word 0x32b57427
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail
    csrr t0, vstart
    bne t0, s2, fail

    li s1, 0
    # vmtts.v v8, (a0), a1, L1
    .word 0x36b57427
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail
    csrr t0, vstart
    bne t0, s2, fail

    # ---- 2. vstart = 3 ----
    csrw vstart, zero
    vmv.v.i v8, -1
    li t0, 3
    csrw vstart, t0
    li s1, 0
    # vmtl.v v8, (a0), a1, L1
    .word 0x32b57407
    bnez s1, fail
    csrr t0, vstart
    bnez t0, fail

    la a2, dst_buf
    vse64.v v8, (a2)
    li t2, -1
    ld t0, 0(a2)
    bne t0, t2, fail
    ld t0, 8(a2)
    bne t0, t2, fail
    ld t0, 16(a2)
    bne t0, t2, fail
    li t2, 4
    ld t0, 24(a2)
    bne t0, t2, fail

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
src_buf:
    .dword 1, 2, 3, 4
dst_buf:
    .fill 32, 1, 0
