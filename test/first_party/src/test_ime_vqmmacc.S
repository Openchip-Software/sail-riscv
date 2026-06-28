#include "common/encoding.h"

# Test for IME quad-widening integer matrix multiply-accumulate (vqmmacc.vv,
# W=4). Each A/B input element is SEW/4 bits wide, four packed per SEW-bit
# storage element; C accumulates at SEW. Geometry per row follows the spec:
#   K_eff = lambda * 4 * LMUL          (logical dot-product depth)
#   storage_K = lambda * LMUL          (SEW-wide storage elements along K)
#   M = VLEN / (SEW * lambda), N = VL / storage_K, EMUL_C = VLEN / (SEW*lambda^2)
# VLEN=256. VL must be a multiple of lambda*LMUL. SEW=8 (EEW=2) is reserved, so
# only SEW in {16,32,64} (EEW in {4,8,16}) is exercised.
#
# The four rows cover all signedness combinations via altfmt_A/altfmt_B and the
# three valid widths, prioritizing the Int8->Int32 vqwmmacc/Ozaki-style path:
#   Row A: Int8 ->Int32 signed/signed     (altfmt_A=0, altfmt_B=0)
#   Row B: Int8 ->Int32 unsigned/signed   (altfmt_A=1, altfmt_B=0)
#   Row C: Int4 ->Int16 unsigned/unsigned (altfmt_A=1, altfmt_B=1)
#   Row D: Int16->Int64 signed/unsigned   (altfmt_A=0, altfmt_B=1)
#
# Encoding for every row is vqmmacc.vv v16, v8, v12 (vd=16, vs1=8, vs2=12,
# vm=1): funct6=0x3a, OPIVV. .word 0xeac40857.
#
# C active outputs land at the architectural tile-register flat indices given by
# mat_C_idx; the expected constants below are produced by a scalar reference
# mirroring the Sail int_gemm helper.

.global main
main:
    mv t6, ra

    # Enable vector extension.
    li t0, MSTATUS_VS
    csrs mstatus, t0

    # ===================================================================
    # Row A: Int8->Int32, signed/signed
    #   SEW=32, lambda=2, LMUL=1, VL=4 => M=4, N=2, K_eff=8, storage_K=2,
    #   EMUL_C=2. Active C is the 4x2 row-major block at flat indices 0..7.
    # ===================================================================
    # Load C init (EMUL_C=2 group) as SEW=32, LMUL=2.
    li t0, 0x20000000000000D1
    la a0, c_zero
    li a1, 16
    vsetvl t2, a1, t0
    vle32.v v16, (a0)
    # Load A (LMUL=1) and B (LMUL=1) at SEW=32, lambda=2.
    li t0, 0x20000000000000D0
    la a0, a_rowA
    li a1, 8
    vsetvl t2, a1, t0
    vle32.v v8, (a0)
    la a0, b_rowA
    li a1, 4
    vsetvl t2, a1, t0
    vle32.v v12, (a0)
    # Compute: VL=4 => N=2 active columns.
    li a1, 4
    vsetvl t2, a1, t0
    .word 0xeac40857
    # Store C and check active outputs (word offsets = flat*4).
    li t0, 0x20000000000000D1
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse32.v v16, (a0)

    la a0, c_out
    lw t0, 0(a0);  li t1, 2;   bne t0, t1, fail
    lw t0, 4(a0);  li t1, 1;   bne t0, t1, fail
    lw t0, 8(a0);  li t1, 10;  bne t0, t1, fail
    lw t0, 12(a0); li t1, 8;   bne t0, t1, fail
    lw t0, 16(a0); li t1, 12;  bne t0, t1, fail
    lw t0, 20(a0); li t1, 8;   bne t0, t1, fail
    lw t0, 24(a0); li t1, -1;  bne t0, t1, fail
    lw t0, 28(a0); li t1, 11;  bne t0, t1, fail
    # Tail column (flat 8) stays zero.
    lw t0, 32(a0); li t1, 0;   bne t0, t1, fail

    # ===================================================================
    # Row B: Int8->Int32, unsigned A / signed B (mixed sign)
    #   SEW=32, lambda=2, LMUL=1, VL=4 => M=4, N=2, K_eff=8, storage_K=2,
    #   EMUL_C=2. altfmt_A=1 (unsigned), altfmt_B=0 (signed); A packs an
    #   unsigned 200 (0xC8) and B packs a signed -1 (0xff).
    # ===================================================================
    li t0, 0x24000000000000D1
    la a0, c_zero
    li a1, 16
    vsetvl t2, a1, t0
    vle32.v v16, (a0)
    li t0, 0x24000000000000D0
    la a0, a_rowB
    li a1, 8
    vsetvl t2, a1, t0
    vle32.v v8, (a0)
    la a0, b_rowB
    li a1, 4
    vsetvl t2, a1, t0
    vle32.v v12, (a0)
    li a1, 4
    vsetvl t2, a1, t0
    .word 0xeac40857
    li t0, 0x24000000000000D1
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse32.v v16, (a0)

    la a0, c_out
    lw t0, 0(a0);  li t1, 201; bne t0, t1, fail
    lw t0, 4(a0);  li t1, 399; bne t0, t1, fail
    lw t0, 8(a0);  li t1, 5;   bne t0, t1, fail
    lw t0, 12(a0); li t1, 2;   bne t0, t1, fail
    lw t0, 16(a0); li t1, 10;  bne t0, t1, fail
    lw t0, 20(a0); li t1, 20;  bne t0, t1, fail
    lw t0, 24(a0); li t1, 2;   bne t0, t1, fail
    lw t0, 28(a0); li t1, 1;   bne t0, t1, fail
    # Tail column (flat 8) stays zero.
    lw t0, 32(a0); li t1, 0;   bne t0, t1, fail

    # ===================================================================
    # Row C: Int4->Int16, unsigned/unsigned
    #   SEW=16, lambda=2, LMUL=1, VL=2 => M=8, N=1, K_eff=8, storage_K=2,
    #   EMUL_C=4. Active C is the 8x1 column at flat indices 0,2,...,14.
    #   altfmt_A=altfmt_B=1; exercises packed 4-bit (nibble) lanes, four per
    #   halfword, including unsigned values >= 8 (0xf nibbles).
    # ===================================================================
    li t0, 0x26000000000000CA
    la a0, c_zero
    li a1, 64
    vsetvl t2, a1, t0
    vle16.v v16, (a0)
    li t0, 0x26000000000000C8
    la a0, a_rowC
    li a1, 16
    vsetvl t2, a1, t0
    vle16.v v8, (a0)
    la a0, b_rowC
    li a1, 2
    vsetvl t2, a1, t0
    vle16.v v12, (a0)
    li a1, 2
    vsetvl t2, a1, t0
    .word 0xeac40857
    li t0, 0x26000000000000CA
    la a0, c_out
    li a1, 64
    vsetvl t2, a1, t0
    vse16.v v16, (a0)

    la a0, c_out
    lh t0, 0(a0);  li t1, 36; bne t0, t1, fail
    lh t0, 4(a0);  li t1, 8;  bne t0, t1, fail
    lh t0, 8(a0);  li t1, 2;  bne t0, t1, fail
    lh t0, 12(a0); li t1, 30; bne t0, t1, fail
    lh t0, 16(a0); li t1, 1;  bne t0, t1, fail
    lh t0, 20(a0); li t1, 9;  bne t0, t1, fail
    lh t0, 24(a0); li t1, 1;  bne t0, t1, fail
    lh t0, 28(a0); li t1, 4;  bne t0, t1, fail
    # Tail element (flat 1) stays zero.
    lh t0, 2(a0);  li t1, 0;  bne t0, t1, fail

    # ===================================================================
    # Row D: Int16->Int64, signed A / unsigned B (mixed sign)
    #   SEW=64, lambda=2, LMUL=1, VL=4 => M=2, N=2, K_eff=8, storage_K=2,
    #   EMUL_C=1. Active C is the 2x2 block at flat indices 0..3.
    #   altfmt_A=0 (signed), altfmt_B=1 (unsigned); B packs an unsigned
    #   32769 (0x8001) read positive.
    # ===================================================================
    li t0, 0x22000000000000D8
    la a0, c_zero
    li a1, 4
    vsetvl t2, a1, t0
    vle64.v v16, (a0)
    la a0, a_rowD
    li a1, 4
    vsetvl t2, a1, t0
    vle64.v v8, (a0)
    la a0, b_rowD
    li a1, 4
    vsetvl t2, a1, t0
    vle64.v v12, (a0)
    li a1, 4
    vsetvl t2, a1, t0
    .word 0xeac40857
    la a0, c_out
    li a1, 4
    vsetvl t2, a1, t0
    vse64.v v16, (a0)

    la a0, c_out
    ld t0, 0(a0);  li t1, 4;       bne t0, t1, fail
    ld t0, 8(a0);  li t1, 32769;   bne t0, t1, fail
    ld t0, 16(a0); li t1, 100;     bne t0, t1, fail
    ld t0, 24(a0); li t1, 3276900; bne t0, t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

.balign 64
# Shared zero source for C init and a scratch output buffer (128 bytes covers
# the largest C register group used by any row, Row C's EMUL_C=4 at SEW=16).
c_zero:
    .word 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 0
c_out:
    .word 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 0

.balign 64
# Row A: SEW=32 storage words, four signed Int8 lanes each (lane k occupies
# bits [k*8 + 7 : k*8], lane 0 the least-significant byte).
a_rowA:
    .word 0xfe02ff01, 0x01010101, 0x02020202, 0xff010000
    .word 0x00000003, 0xfc030201, 0x01fdfeff, 0x02020202
b_rowA:
    .word 0x01010101, 0xff010002, 0x0300ff02, 0x01010101

.balign 64
# Row B: SEW=32 storage words, four Int8 lanes each. A read unsigned (0xC8=200),
# B read signed.
a_rowB:
    .word 0x000001c8, 0x01010101, 0x02020202, 0x00000003
    .word 0x0000000a, 0x00000000, 0x01010101, 0x01010101
b_rowB:
    .word 0x00000001, 0x00000001, 0x0000ff02, 0x00000000

.balign 64
# Row C: SEW=16 storage halfwords, four Int4 (nibble) lanes each, read unsigned.
a_rowC:
    .half 0x4321, 0x8765, 0x1111, 0x1111
    .half 0x0002, 0x0000, 0x00ff, 0x0000
    .half 0x0001, 0x0000, 0x0333, 0x0000
    .half 0x0000, 0x1000, 0x0022, 0x0000
b_rowC:
    .half 0x1111, 0x1111

.balign 64
# Row D: SEW=64 storage dwords, four Int16 lanes each. A read signed, B read
# unsigned (0x8001=32769).
a_rowD:
    .dword 0xfffe0002ffff0001, 0x0001000100010001
    .dword 0x0000000000000064, 0x0000000000000000
b_rowD:
    .dword 0x0001000100010001, 0x0001000100010001
    .dword 0x0000000000008001, 0x0000000000000000
