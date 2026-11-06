#include "common/encoding.h"

# A zero value in rs2 selects the default leading dimension, not only
# rs2=x0. Here rs2=a1 holds 0.
#
# Geometry: VLEN=256, SEW=32, LMUL=1, lambda=2 (L2), VL=8.
# Default LD: lambda*LMUL=2 (order-preserving), VLEN/(SEW*lambda)=4
# (transposing). Memory offsets of tile elements 0..7:
#   order-preserving: [0,1,2,3,4,5,6,7]
#   transposing:      [0,4,1,5,2,6,3,7]
#
# 1. vmtl.v  loads  pat -> v8 = [0,1,2,3,4,5,6,7]
# 2. vmttl.v loads  pat -> v8 = [0,4,1,5,2,6,3,7]
# 3. vmts.v  stores v8=[0..7] -> out = [0,1,2,3,4,5,6,7]
# 4. vmtts.v stores v8=[0..7] -> out = [0,2,4,6,1,3,5,7]

# Fail unless the 8 words at \got equal the 8 words at \exp.
.macro CHECK8 got, exp
    la a2, \got
    la a3, \exp
    li t3, 8
1:
    lw t1, 0(a2)
    lw t2, 0(a3)
    bne t1, t2, fail
    addi a2, a2, 4
    addi a3, a3, 4
    addi t3, t3, -1
    bnez t3, 1b
.endm

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    vsetivli t0, 8, e32, m1, ta, ma
    li t1, 8
    bne t0, t1, fail

    la a0, pat
    li a1, 0
    la a4, chk

    # ---- 1. vmtl.v with rs2 holding 0 ----
    vmv.v.i v8, -1
    # vmtl.v v8, (a0), a1, L2
    .word 0x52b57407
    vse32.v v8, (a4)
    CHECK8 chk, exp_ordered

    # ---- 2. vmttl.v with rs2 holding 0 ----
    vmv.v.i v8, -1
    # vmttl.v v8, (a0), a1, L2
    .word 0x56b57407
    vse32.v v8, (a4)
    CHECK8 chk, exp_transposed

    # ---- 3. vmts.v with rs2 holding 0 ----
    vle32.v v8, (a0)
    la a0, out
    # vmts.v v8, (a0), a1, L2
    .word 0x52b57427
    CHECK8 out, exp_ordered

    # ---- 4. vmtts.v with rs2 holding 0 ----
    # vmtts.v v8, (a0), a1, L2
    .word 0x56b57427
    CHECK8 out, exp_stored_transposed

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

.balign 64
pat:
    .word 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
exp_ordered:
    .word 0, 1, 2, 3, 4, 5, 6, 7
exp_transposed:
    .word 0, 4, 1, 5, 2, 6, 3, 7
exp_stored_transposed:
    .word 0, 2, 4, 6, 1, 3, 5, 7
chk:
    .fill 32, 1, 0
out:
    .fill 64, 1, 0
