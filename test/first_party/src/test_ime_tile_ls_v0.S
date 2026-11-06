#include "common/encoding.h"

# A masked tile load whose destination overlaps the mask register v0 raises
# an illegal-instruction exception. Masked tile stores may read from v0.
#
# Geometry: VLEN=256, SEW=32, LMUL=1, VL=4, lambda=1 (L1), LD=4.
#
# 1. vmtl.v and vmttl.v with vd=v0, vm=0 trap with mcause=2.
# 2. vmtl.v with vd=v8, vm=0 does not trap (control).
# 3. vmts.v and vmtts.v with vs3=v0, vm=0 do not trap (control).

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0

    la a0, buf
    li a1, 4

    vsetivli t0, 4, e32, m1, ta, ma
    li t1, 4
    bne t0, t1, fail

    # ---- 1. Masked loads into v0 ----
    li t1, CAUSE_ILLEGAL_INSTRUCTION

    li s1, 0
    # vmtl.v v0, (a0), a1, L1, v0.t
    .word 0x30b57007
    bne s1, t1, fail

    li s1, 0
    # vmttl.v v0, (a0), a1, L1, v0.t
    .word 0x34b57007
    bne s1, t1, fail

    # ---- 2. Masked load into v8 ----
    li s1, 0
    # vmtl.v v8, (a0), a1, L1, v0.t
    .word 0x30b57407
    bnez s1, fail

    # ---- 3. Masked stores from v0 ----
    # vmts.v v0, (a0), a1, L1, v0.t
    .word 0x30b57027
    bnez s1, fail

    # vmtts.v v0, (a0), a1, L1, v0.t
    .word 0x34b57027
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
