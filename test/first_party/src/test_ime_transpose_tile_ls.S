#include "common/encoding.h"

# Test for IME transposing tile load (vmttl.v) and tile store (vmtts.v).
#
# This is a RED test for Task 8: it defines the expected Zvvmttls behavior
# before the Sail implementation exists.  The current model is expected to
# reject or mis-execute the transposing tile mode until Task 9 implements it.
#
# Geometry for both subcases: SEW=32, LMUL=1, lambda=2, VL=4.
# cols = lambda * LMUL = 2 storage elements.
# rows = VL / cols = 2 storage-element rows.
#
# vmttl.v/vmtts.v transpose SEW-bit storage elements only.  They do not
# unpack, transpose, or repack W>1 logical input elements that may be packed
# inside a SEW-bit storage element for widening matrix multiply instructions.
#
# For explicit LD=4, transposed traversal selects word offsets [0,4,1,5]
# for flat register/storage-element indices [0,1,2,3].  This differs from
# order-preserving vmtl/vmts traversal [0,1,4,5].
#
# The second subcase uses rs2=x0.  For transposing tile load/store, natural
# LD is VLEN / (SEW * lambda) = 256 / (32 * 2) = 4, not lambda * LMUL = 2.

.global main
main:
    # Save return address.
    mv t6, ra

    # Enable vector extension.
    li t0, MSTATUS_VS
    csrs mstatus, t0

    # ---- Configure vtype: SEW=32, LMUL=1, ta, ma, lambda=2 ----
    # RV64 vtype layout (bits):
    #   63:vill  62:60:vlambda  59:vbs  58:altfmt_A  57:altfmt_B
    #   56:8 reserved  7:vma  6:vta  5:3:vsew  2:0:vlmul
    # vsew=0b010 (e32), vlmul=0b000 (m1), vta=1, vma=1,
    # vlambda=0b010 (lambda=2) => 0x20000000000000D0.
    li t0, 0x2000
    slli t0, t0, 44          # t0 = 0x2000000000000000
    li t1, 0xD0
    or  t0, t0, t1
    li a1, 4                 # AVL = 4
    vsetvl t2, a1, t0

    # =====================================================================================
    # Subcase 1: explicit LD=4.
    # =====================================================================================

    # Initialize src_buf with words 1..16.
    la a0, src_buf
    li t0, 1
    li t1, 0
1:
    sw t0, 0(a0)
    addi t0, t0, 1
    addi a0, a0, 4
    addi t1, t1, 1
    li t2, 16
    bne t1, t2, 1b

    # Initialize dst_buf with zero sentinels.
    la a2, dst_buf
    li t0, 0
    li t1, 0
2:
    sw t0, 0(a2)
    addi a2, a2, 4
    addi t1, t1, 1
    li t2, 16
    bne t1, t2, 2b

    # vmttl.v v8, (a0), a1, L2
    # Encoding: lambda(3) @ L(1) @ mode(2) @ vm(1) @ rs2 @ rs1 @ 0x7 @ vd @ 0x07
    # lambda=2, L=1, transposed mode=01, vm=1 => imm7 = 0b010_1_01_1 = 0x2b.
    # Expected load values in v8 flat elements: [src[0], src[4], src[1], src[5]] = [1,5,2,6].
    la a0, src_buf
    li a1, 4
    .word 0x56b57407         # vmttl.v v8, (a0), a1, L2

    # vmtts.v v8, (a2), a3, L2
    # Expected stores to dst offsets [0,4,1,5] with values [1,5,2,6].
    la a2, dst_buf
    li a3, 4
    .word 0x56d67427         # vmtts.v v8, (a2), a3, L2

    # Verify explicit-LD destination layout.
    la a2, dst_buf
    lw t0, 0(a2)             # dst[0] == 1
    li t1, 1
    bne t0, t1, fail
    lw t0, 4(a2)             # dst[1] == 2
    li t1, 2
    bne t0, t1, fail
    lw t0, 8(a2)             # dst[2] untouched
    li t1, 0
    bne t0, t1, fail
    lw t0, 12(a2)            # dst[3] untouched
    li t1, 0
    bne t0, t1, fail
    lw t0, 16(a2)            # dst[4] == 5
    li t1, 5
    bne t0, t1, fail
    lw t0, 20(a2)            # dst[5] == 6
    li t1, 6
    bne t0, t1, fail
    lw t0, 24(a2)            # dst[6] untouched
    li t1, 0
    bne t0, t1, fail
    lw t0, 28(a2)            # dst[7] untouched
    li t1, 0
    bne t0, t1, fail

    # =====================================================================================
    # Subcase 2: rs2=x0 natural LD.  For transposing operations this is 4.
    # =====================================================================================

    # Initialize src2_buf with words 101..116.
    la a0, src2_buf
    li t0, 101
    li t1, 0
3:
    sw t0, 0(a0)
    addi t0, t0, 1
    addi a0, a0, 4
    addi t1, t1, 1
    li t2, 16
    bne t1, t2, 3b

    # Initialize dst2_buf with zero sentinels.
    la a2, dst2_buf
    li t0, 0
    li t1, 0
4:
    sw t0, 0(a2)
    addi a2, a2, 4
    addi t1, t1, 1
    li t2, 16
    bne t1, t2, 4b

    # vmttl.v v9, (a0), x0, L2
    # With transposing natural LD=4, expected load values are [101,105,102,106].
    # If an implementation incorrectly used ordered natural LD=2, it would touch
    # [101,103,102,104] instead and this subcase would fail.
    la a0, src2_buf
    .word 0x56057487         # vmttl.v v9, (a0), x0, L2

    # vmtts.v v9, (a2), x0, L2
    la a2, dst2_buf
    .word 0x560674a7         # vmtts.v v9, (a2), x0, L2

    # Verify natural-LD destination layout.
    la a2, dst2_buf
    lw t0, 0(a2)             # dst2[0] == 101
    li t1, 101
    bne t0, t1, fail
    lw t0, 4(a2)             # dst2[1] == 102
    li t1, 102
    bne t0, t1, fail
    lw t0, 8(a2)             # dst2[2] untouched if natural LD is 4
    li t1, 0
    bne t0, t1, fail
    lw t0, 12(a2)            # dst2[3] untouched if natural LD is 4
    li t1, 0
    bne t0, t1, fail
    lw t0, 16(a2)            # dst2[4] == 105
    li t1, 105
    bne t0, t1, fail
    lw t0, 20(a2)            # dst2[5] == 106
    li t1, 106
    bne t0, t1, fail
    lw t0, 24(a2)            # dst2[6] untouched
    li t1, 0
    bne t0, t1, fail
    lw t0, 28(a2)            # dst2[7] untouched
    li t1, 0
    bne t0, t1, fail

    # All checks passed.
    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

.balign 64
src_buf:
    .fill 64, 1, 0
dst_buf:
    .fill 64, 1, 0
src2_buf:
    .fill 64, 1, 0
dst2_buf:
    .fill 64, 1, 0
