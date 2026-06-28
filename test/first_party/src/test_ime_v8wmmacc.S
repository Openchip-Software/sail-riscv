#include "common/encoding.h"

# Test for IME octuple-widening integer matrix multiply-accumulate (v8wmmacc.vv,
# W=8). Each A/B input element is SEW/8 bits wide, eight packed per SEW-bit
# storage element; C accumulates at SEW. Geometry per row follows the spec:
#   K_eff = lambda * 8 * LMUL          (logical dot-product depth)
#   storage_K = lambda * LMUL          (SEW-wide storage elements along K)
#   M = VLEN / (SEW * lambda), N = VL / storage_K, EMUL_C = VLEN / (SEW*lambda^2)
# VLEN=256. VL must be a multiple of lambda*LMUL. EEW = SEW/8 must be a supported
# integer width (4, 8, ...), so only SEW in {32,64} (EEW in {4,8}) is exercised;
# SEW=16 (EEW=2) and SEW=8 (EEW=1) are reserved.
#
# The four rows cover both supported widths, both Int4 and Int8 inputs, all
# relevant signedness via altfmt_A/altfmt_B, and an LMUL=2 case to prove the
# generalized K_eff = lambda*W*LMUL / storage_K = lambda*LMUL path is not
# hard-coded to LMUL=1:
#   Row A: Int4->Int32 signed/signed     (altfmt_A=0, altfmt_B=0, LMUL=1)
#   Row B: Int4->Int32 unsigned/signed   (altfmt_A=1, altfmt_B=0, LMUL=1)
#   Row C: Int8->Int64 signed/signed     (altfmt_A=0, altfmt_B=0, LMUL=1)
#   Row D: Int8->Int64 signed/unsigned   (altfmt_A=0, altfmt_B=1, LMUL=2)
#
# Encoding for every row is v8wmmacc.vv v16, v8, v12 (vd=16, vs1=8, vs2=12,
# vm=1): funct6=0x3b, OPIVV. .word 0xeec40857.
#
# C active outputs land at the architectural tile-register flat indices given by
# mat_C_idx; the expected constants below are produced by ref_v8wmmacc.py, a
# scalar reference mirroring the Sail int_gemm helper.

.global main
main:
    mv t6, ra

    # Enable vector extension.
    li t0, MSTATUS_VS
    csrs mstatus, t0

    # ===================================================================
    # Row A: Int4->Int32, signed/signed
    #   SEW=32, lambda=2, LMUL=1, VL=4 => M=4, N=2, K_eff=16, storage_K=2,
    #   EMUL_C=2. Active C is the 4x2 row-major block at flat indices 0..7.
    # ===================================================================
    # Load C init (EMUL_C=2 group) as SEW=32, LMUL=2.
    li t0, 0x20000000000000D1
    la a0, c_zero
    li a1, 16
    vsetvl t2, a1, t0
    vle32.v v16, (a0)
    # Load A (8 storage words) and B (4 storage words) at SEW=32, LMUL=1.
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
    .word 0xeec40857
    # Store C and check active outputs (word offsets = flat*4).
    li t0, 0x20000000000000D1
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse32.v v16, (a0)

    la a0, c_out
    lw t0, 0(a0);  li t1, 4;   bne t0, t1, fail
    lw t0, 4(a0);  li t1, 1;   bne t0, t1, fail
    lw t0, 8(a0);  li t1, 1;   bne t0, t1, fail
    lw t0, 12(a0); li t1, 1;   bne t0, t1, fail
    lw t0, 16(a0); li t1, 10;  bne t0, t1, fail
    lw t0, 20(a0); li t1, 4;   bne t0, t1, fail
    lw t0, 24(a0); li t1, -1;  bne t0, t1, fail
    lw t0, 28(a0); li t1, -1;  bne t0, t1, fail
    # Tail column (flat 8) stays zero.
    lw t0, 32(a0); li t1, 0;   bne t0, t1, fail

    # ===================================================================
    # Row B: Int4->Int32, unsigned A / signed B (mixed sign)
    #   SEW=32, lambda=2, LMUL=1, VL=4 => M=4, N=2, K_eff=16, storage_K=2,
    #   EMUL_C=2. altfmt_A=1 (unsigned), altfmt_B=0 (signed); A packs an
    #   unsigned nibble 0xf (=15) read positive, B packs a signed -1 (0xf).
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
    .word 0xeec40857
    li t0, 0x24000000000000D1
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse32.v v16, (a0)

    la a0, c_out
    lw t0, 0(a0);  li t1, 10;  bne t0, t1, fail
    lw t0, 4(a0);  li t1, -5;  bne t0, t1, fail
    lw t0, 8(a0);  li t1, 1;   bne t0, t1, fail
    lw t0, 12(a0); li t1, -1;  bne t0, t1, fail
    lw t0, 16(a0); li t1, 4;   bne t0, t1, fail
    lw t0, 20(a0); li t1, 0;   bne t0, t1, fail
    lw t0, 24(a0); li t1, 15;  bne t0, t1, fail
    lw t0, 28(a0); li t1, -15; bne t0, t1, fail
    # Tail column (flat 8) stays zero.
    lw t0, 32(a0); li t1, 0;   bne t0, t1, fail

    # ===================================================================
    # Row C: Int8->Int64, signed/signed
    #   SEW=64, lambda=2, LMUL=1, VL=4 => M=2, N=2, K_eff=16, storage_K=2,
    #   EMUL_C=1. Active C is the 2x2 block at flat indices 0..3.
    # ===================================================================
    li t0, 0x20000000000000D8
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
    .word 0xeec40857
    la a0, c_out
    li a1, 4
    vsetvl t2, a1, t0
    vse64.v v16, (a0)

    la a0, c_out
    ld t0, 0(a0);  li t1, 7;   bne t0, t1, fail
    ld t0, 8(a0);  li t1, 6;   bne t0, t1, fail
    ld t0, 16(a0); li t1, 4;   bne t0, t1, fail
    ld t0, 24(a0); li t1, -1;  bne t0, t1, fail

    # ===================================================================
    # Row D: Int8->Int64, signed A / unsigned B (mixed sign), LMUL=2
    #   SEW=64, lambda=2, LMUL=2, VL=8 => M=2, N=2, K_eff=32, storage_K=4,
    #   EMUL_C=1. Active C is the 2x2 block at flat indices 0..3. A/B are
    #   loaded as LMUL=2 register groups (v8/v9 and v12/v13). altfmt_A=0
    #   (signed), altfmt_B=1 (unsigned); B packs an unsigned 200 (0xc8).
    # ===================================================================
    li t0, 0x22000000000000D8
    la a0, c_zero
    li a1, 4
    vsetvl t2, a1, t0
    vle64.v v16, (a0)
    li t0, 0x22000000000000D9
    la a0, a_rowD
    li a1, 8
    vsetvl t2, a1, t0
    vle64.v v8, (a0)
    la a0, b_rowD
    li a1, 8
    vsetvl t2, a1, t0
    vle64.v v12, (a0)
    li a1, 8
    vsetvl t2, a1, t0
    .word 0xeec40857
    li t0, 0x22000000000000D8
    la a0, c_out
    li a1, 4
    vsetvl t2, a1, t0
    vse64.v v16, (a0)

    la a0, c_out
    ld t0, 0(a0);  li t1, 4;    bne t0, t1, fail
    ld t0, 8(a0);  li t1, 200;  bne t0, t1, fail
    ld t0, 16(a0); li t1, 0;    bne t0, t1, fail
    ld t0, 24(a0); li t1, -197; bne t0, t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

.balign 64
# Shared zero source for C init and a scratch output buffer (128 bytes covers
# the largest C register group used by any row, Row A/B's EMUL_C=2 at SEW=32).
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
# Row A: SEW=32 storage words, eight signed Int4 lanes each (lane k occupies
# bits [k*4 + 3 : k*4], lane 0 the least-significant nibble).
a_rowA:
    .word 0x00110f21, 0x000011e2, 0x00000001, 0x00000000
    .word 0x11111111, 0x11111111, 0x0000000f, 0x10000000
b_rowA:
    .word 0x11111111, 0x00000011, 0x00002f01, 0x00000110

.balign 64
# Row B: SEW=32 storage words, eight Int4 lanes each. A read unsigned, B signed.
a_rowB:
    .word 0x00000027, 0x00000011, 0x00000001, 0x00000000
    .word 0x00002222, 0x00000000, 0x0000000f, 0x00000000
b_rowB:
    .word 0x00000011, 0x00000001, 0x0000001f, 0x00000000

.balign 64
# Row C: SEW=64 storage dwords, eight signed Int8 lanes each.
a_rowC:
    .dword 0x00000000ff030201, 0x0000000000000101
    .dword 0x0000000000000002, 0x0000000001010101
b_rowC:
    .dword 0x0000000001010101, 0x0000000000000101
    .dword 0x00000000000200ff, 0x0000000000000001

.balign 64
# Row D: SEW=64 storage dwords, eight Int8 lanes each, LMUL=2 group. A read
# signed, B read unsigned (0xc8=200).
a_rowD:
    .dword 0x0000000000000101, 0x0000000000000002
    .dword 0x00000000000000ff, 0x0000000000000101
    .dword 0x0000000000000000, 0x0000000000000000
    .dword 0x0000000000000000, 0x0000000000000003
b_rowD:
    .dword 0x0000000000000101, 0x0000000000000001
    .dword 0x00000000000000c8, 0x0000000000000000
    .dword 0x0000000000000000, 0x0000000000000000
    .dword 0x0000000000000000, 0x0000000000000001
