#include "common/encoding.h"

# Test for IME double-widening integer matrix multiply-accumulate (vwmmacc.vv,
# W=2). Each A/B input element is SEW/2 bits wide, two packed per SEW-bit
# storage element; C accumulates at SEW. Geometry per row follows the spec:
#   K_eff = lambda * 2 * LMUL          (logical dot-product depth)
#   storage_K = lambda * LMUL          (SEW-wide storage elements along K)
#   M = VLEN / (SEW * lambda), N = VL / storage_K, EMUL_C = VLEN / (SEW*lambda^2)
# VLEN=256. VL must be a multiple of lambda*LMUL.
#
# All four W=2 integer rows are exercised, including Int4->Int8: the packed
# sub-element helper represents 4-bit lanes (two nibbles per byte), so no row
# is blocked on missing helper support.
#
# Encoding for every row is vwmmacc.vv v16, v8, v12 (vd=16, vs1=8, vs2=12,
# vm=1): funct6=0x39, OPIVV. .word 0xe6c40857.
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
    # Row A: Int16->Int32, signed/signed
    #   SEW=32, lambda=2, LMUL=1, VL=4 => M=4, N=2, K_eff=4, storage_K=2,
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
    .word 0xe6c40857
    # Store C and check active outputs (word offsets = flat*4).
    li t0, 0x20000000000000D1
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse32.v v16, (a0)

    la a0, c_out
    lw t0, 0(a0);  li t1, -44; bne t0, t1, fail
    lw t0, 4(a0);  li t1, -4;  bne t0, t1, fail
    lw t0, 8(a0);  li t1, 4;   bne t0, t1, fail
    lw t0, 12(a0); li t1, 16;  bne t0, t1, fail
    lw t0, 16(a0); li t1, 44;  bne t0, t1, fail
    lw t0, 20(a0); li t1, 4;   bne t0, t1, fail
    lw t0, 24(a0); li t1, 44;  bne t0, t1, fail
    lw t0, 28(a0); li t1, 0;   bne t0, t1, fail
    # Tail column (flat 8) stays zero.
    lw t0, 32(a0); li t1, 0;   bne t0, t1, fail

    # ===================================================================
    # Row B: Int8->Int16, signed A / unsigned B (mixed sign)
    #   SEW=16, lambda=4, LMUL=1, VL=4 => M=4, N=1, K_eff=8, storage_K=4,
    #   EMUL_C=1. Active C is the 4x1 column at flat indices 0,4,8,12.
    #   altfmt_A=0 (signed), altfmt_B=1 (unsigned); B packs an unsigned 200.
    # ===================================================================
    li t0, 0x32000000000000C8
    la a0, c_zero
    li a1, 16
    vsetvl t2, a1, t0
    vle16.v v16, (a0)
    la a0, a_rowB
    li a1, 16
    vsetvl t2, a1, t0
    vle16.v v8, (a0)
    la a0, b_rowB
    li a1, 4
    vsetvl t2, a1, t0
    vle16.v v12, (a0)
    li a1, 4
    vsetvl t2, a1, t0
    .word 0xe6c40857
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse16.v v16, (a0)

    la a0, c_out
    lh t0, 0(a0);  li t1, 1740; bne t0, t1, fail
    lh t0, 8(a0);  li t1, 188;  bne t0, t1, fail
    lh t0, 16(a0); li t1, 32;   bne t0, t1, fail
    lh t0, 24(a0); li t1, 10;   bne t0, t1, fail
    # Tail element (flat 2) stays zero.
    lh t0, 4(a0);  li t1, 0;    bne t0, t1, fail

    # ===================================================================
    # Row C: Int32->Int64, unsigned/unsigned
    #   SEW=64, lambda=2, LMUL=1, VL=4 => M=2, N=2, K_eff=4, storage_K=2,
    #   EMUL_C=1. Active C is the 2x2 block at flat indices 0..3.
    #   altfmt_A=altfmt_B=1; A packs 0x80000001 read as unsigned.
    # ===================================================================
    li t0, 0x26000000000000D8
    la a0, c_zero
    li a1, 4
    vsetvl t2, a1, t0
    vle64.v v16, (a0)
    la a0, a_rowC
    li a1, 4
    vsetvl t2, a1, t0
    vle64.v v8, (a0)
    la a0, b_rowC
    li a1, 4
    vsetvl t2, a1, t0
    vle64.v v12, (a0)
    li a1, 4
    vsetvl t2, a1, t0
    .word 0xe6c40857
    la a0, c_out
    li a1, 4
    vsetvl t2, a1, t0
    vse64.v v16, (a0)

    la a0, c_out
    ld t0, 0(a0);  li t1, 0x100000012; bne t0, t1, fail
    ld t0, 8(a0);  li t1, 0x80000004;  bne t0, t1, fail
    ld t0, 16(a0); li t1, 52;          bne t0, t1, fail
    ld t0, 24(a0); li t1, 12;          bne t0, t1, fail

    # ===================================================================
    # Row D: Int4->Int8, signed/signed
    #   SEW=8, lambda=4, LMUL=1, VL=4 => M=8, N=1, K_eff=8, storage_K=4,
    #   EMUL_C=2. Active C is the 8x1 column at flat indices 0,4,...,28.
    #   Exercises packed 4-bit (nibble) lanes, two per byte.
    # ===================================================================
    li t0, 0x30000000000000C1
    la a0, c_zero
    li a1, 64
    vsetvl t2, a1, t0
    vle8.v v16, (a0)
    li t0, 0x30000000000000C0
    la a0, a_rowD
    li a1, 32
    vsetvl t2, a1, t0
    vle8.v v8, (a0)
    la a0, b_rowD
    li a1, 4
    vsetvl t2, a1, t0
    vle8.v v12, (a0)
    li a1, 4
    vsetvl t2, a1, t0
    .word 0xe6c40857
    li t0, 0x30000000000000C1
    la a0, c_out
    li a1, 64
    vsetvl t2, a1, t0
    vse8.v v16, (a0)

    la a0, c_out
    lb t0, 0(a0);  li t1, 12;  bne t0, t1, fail
    lb t0, 4(a0);  li t1, -4;  bne t0, t1, fail
    lb t0, 8(a0);  li t1, 2;   bne t0, t1, fail
    lb t0, 12(a0); li t1, -12; bne t0, t1, fail
    lb t0, 16(a0); li t1, 3;   bne t0, t1, fail
    lb t0, 20(a0); li t1, 8;   bne t0, t1, fail
    lb t0, 24(a0); li t1, 7;   bne t0, t1, fail
    lb t0, 28(a0); li t1, -6;  bne t0, t1, fail
    # Tail element (flat 1) stays zero.
    lb t0, 1(a0);  li t1, 0;   bne t0, t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

.balign 64
# Shared zero source for C init and a scratch output buffer (64 bytes covers the
# largest C register group used by any row).
c_zero:
    .word 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 0
c_out:
    .word 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 0

.balign 64
# Row A: SEW=32 storage words, two Int16 lanes each (low=even k, high=odd k).
a_rowA:
    .word 0x0002ffff, 0xfffc0003, 0x00060005, 0x0008fff9
    .word 0xfffe0001, 0x0004fffd, 0x00020002, 0x00020002
b_rowA:
    .word 0xfff60009, 0x000c000b, 0x0001ffff, 0x0001ffff

.balign 64
# Row B: SEW=16 storage halfwords, two Int8 lanes each. B holds unsigned 200.
a_rowB:
    .half 0x0201, 0x0403, 0x0605, 0x0807
    .half 0xfeff, 0xfcfd, 0x0101, 0x0101
    .half 0x0002, 0x0002, 0x0002, 0x0002
    .half 0x05fb, 0x05fb, 0x0000, 0x0000
b_rowB:
    .half 0x0201, 0x0403, 0x0605, 0xc807

.balign 64
# Row C: SEW=64 storage dwords, two Int32 lanes each. A holds unsigned 0x80000001.
a_rowC:
    .dword 0x0000000180000001, 0x0000000400000003
    .dword 0x0000000600000005, 0x0000000800000007
b_rowC:
    .dword 0x0000000200000002, 0x0000000200000002
    .dword 0x0000000000000001, 0x0000000000000001

.balign 64
# Row D: SEW=8 storage bytes, two Int4 (nibble) lanes each.
a_rowD:
    .byte 0x11, 0x11, 0x11, 0x11
    .byte 0xf1, 0xf1, 0xf1, 0xf1
    .byte 0x02, 0x00, 0x00, 0x00
    .byte 0xff, 0xff, 0xff, 0xff
    .byte 0x03, 0x00, 0x00, 0x00
    .byte 0x10, 0x10, 0x10, 0x10
    .byte 0x07, 0x00, 0x00, 0x00
    .byte 0xee, 0x00, 0x00, 0x00
b_rowD:
    .byte 0x21, 0x21, 0x21, 0x21
