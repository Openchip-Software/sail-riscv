#include "common/encoding.h"

# Test for IME integer matrix multiply-accumulate (vmmacc.vv).
#
# Geometry used here:
#   SEW=32, LMUL=1, lambda=2, VL=4
#   VLEN=256 => M_tile=4, K_eff=2, N_tile=2, EMUL_C=2
#
# We check a signed case (negative A/B elements) and verify that the active
# first two columns of the C tile are updated while tail columns remain 0.
#
# A_tile (4x2, row-major):
#   [ -1,  2,
#      3, -4,
#      5,  6,
#     -7,  8 ]
# B_tile^T is a K_eff x N tile stored column-major as specified by
# mat_B_idx(k, j) = tile_reg_idx(j * K_eff + k, ...):
#   column 0: [  9,  11]
#   column 1: [ -10,  12]
# C init (4x4 physical tile, row-major): all zeros
#
# Expected active results C += A * B^T:
#   row0: [  13,   34]
#   row1: [ -17,  -78]
#   row2: [ 111,   22]
#   row3: [  25,  166]
# Tail columns j>=2 remain 0.

.global main
main:
    mv t6, ra

    # Enable vector extension.
    li t0, MSTATUS_VS
    csrs mstatus, t0

    # --- Load the initial C tile into v16 as an EMUL_C=2 group ---
    # vtype: lambda=2, SEW=32, LMUL=2, ta, ma
    li t0, 0x20000000000000D1 # lambda=2, SEW=32, LMUL=2, ta, ma
    la a0, c_init
    li a1, 16
    vsetvl t2, a1, t0
    vle32.v v16, (a0)

    # --- Load A tile into v8 as LMUL=1 ---
    li t0, 0x20000000000000D0 # lambda=2, SEW=32, LMUL=1, ta, ma
    la a0, a_tile
    li a1, 8
    vsetvl t2, a1, t0
    vle32.v v8, (a0)

    # --- Load B tile^T into v12 as LMUL=1 ---
    la a0, b_tile
    li a1, 4
    vsetvl t2, a1, t0
    vle32.v v12, (a0)

    # --- Execute vmmacc.vv v16, v8, v12 ---
    # Encoding: funct6=0x38, vm=1, vs2=12, vs1=8, funct3=0, vd=16, opcode=0x57
    # .word 0xe2c40857
    li a1, 4
    vsetvl t2, a1, t0
    .word 0xe2c40857

    # --- Store the C tile back out of v16 ---
    li t0, 0x20000000000000D1
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse32.v v16, (a0)

    # --- Verify active columns in architectural tile-register order.
    # With EMUL_C=2 and lambda=2, the active N=2 columns are the first
    # eight SEW=32 elements of the register group; inactive physical
    # columns remain zero in the second half.
    la a0, c_out

    lw t0, 0(a0)
    li t1, 13
    bne t0, t1, fail
    lw t0, 4(a0)
    li t1, 34
    bne t0, t1, fail
    lw t0, 8(a0)
    li t1, -17
    bne t0, t1, fail
    lw t0, 12(a0)
    li t1, -78
    bne t0, t1, fail

    lw t0, 16(a0)
    li t1, 111
    bne t0, t1, fail
    lw t0, 20(a0)
    li t1, 22
    bne t0, t1, fail
    lw t0, 24(a0)
    li t1, 25
    bne t0, t1, fail
    lw t0, 28(a0)
    li t1, 166
    bne t0, t1, fail

    # Inactive physical columns stay untouched.
    lw t0, 32(a0)
    li t1, 0
    bne t0, t1, fail
    lw t0, 60(a0)
    li t1, 0
    bne t0, t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

.balign 64
a_tile:
    .word -1, 2, 3, -4, 5, 6, -7, 8
b_tile:
    .word 9, 11, -10, 12
c_init:
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
c_out:
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
