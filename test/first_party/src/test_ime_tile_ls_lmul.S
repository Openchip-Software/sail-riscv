#include "common/encoding.h"

# Tile loads/stores with LMUL > 1 must place tile element i at register-group
# element tile_reg_idx(i, LMUL, lambda, VLEN/SEW), not at element i.
#
# Geometry: VLEN=256, SEW=32, LMUL=2 => VLMAX=16; VL=16, lambda=1 (L1),
# LD=2.  linesize = lambda * LMUL = 2, so tile element i is memory element i
# and lands at group element (i % 2) * 8 + i / 2.
#
# 1. vmtl.v of 0..15 must give v8:v9 = 0,2,4,...,14,1,3,...,15.
# 2. vmts.v of v8:v9 = 0..15 (filled linearly) must store
#    0,8,1,9,2,10,...,7,15.
# 3. A masked vmtl.v with only even tile elements active must load them
#    into v8 (group elements 0..7) and leave v9 undisturbed: the mask is
#    indexed by tile element, and no other group element is written.

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    vsetivli t0, 16, e32, m2, ta, ma
    li t1, 16
    bne t0, t1, fail

    li a1, 2

    # ---- 1. vmtl.v ----
    vmv.v.i v8, -1
    la a0, seq
    # vmtl.v v8, (a0), a1, L1
    .word 0x32b57407
    la a2, dump
    vse32.v v8, (a2)
    la a3, exp_load
    call compare
    bnez a4, fail

    # ---- 2. vmts.v ----
    la a0, seq
    vle32.v v8, (a0)
    la a0, dump
    # vmts.v v8, (a0), a1, L1
    .word 0x32b57427
    la a2, dump
    la a3, exp_store
    call compare
    bnez a4, fail

    # ---- 3. masked vmtl.v ----
    vsetivli t0, 1, e16, m1, ta, ma
    li t0, 0x5555
    vmv.s.x v0, t0
    vsetivli t0, 16, e32, m2, ta, ma
    vmv.v.i v8, -1
    la a0, seq
    # vmtl.v v8, (a0), a1, L1, v0.t
    .word 0x30b57407
    la a2, dump
    vse32.v v8, (a2)
    la a3, exp_masked
    call compare
    bnez a4, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

# a4 = 0 iff the 16 words at a2 and a3 are equal.
compare:
    li a4, 0
    li t3, 16
1:  lw t1, 0(a2)
    lw t2, 0(a3)
    beq t1, t2, 2f
    li a4, 1
2:  addi a2, a2, 4
    addi a3, a3, 4
    addi t3, t3, -1
    bnez t3, 1b
    ret

.balign 64
seq:
    .word 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
exp_load:
    .word 0, 2, 4, 6, 8, 10, 12, 14, 1, 3, 5, 7, 9, 11, 13, 15
exp_store:
    .word 0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15
exp_masked:
    .word 0, 2, 4, 6, 8, 10, 12, 14, -1, -1, -1, -1, -1, -1, -1, -1
dump:
    .fill 64, 1, 0
