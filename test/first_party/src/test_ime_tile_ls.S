#include "common/encoding.h"

# Test for IME order-preserving tile load (vmtl.v) and tile store (vmts.v).
#
# Geometry: SEW=32, LMUL=1, lambda=2, VL=4, LD=4.
# linesize = lambda * LMUL = 2.
# For element index i in [0, VL):
#   mem_off = (i / linesize) * LD + (i % linesize)
#   i=0 -> 0, i=1 -> 1, i=2 -> 4, i=3 -> 5
# So active elements are loaded from word offsets [0,1,4,5] and stored back
# to the same offsets in a destination buffer.
#
# Source memory (16 words):  [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]
# Expected V[0..3] after vmtl: words at offsets 0,1,4,5 => [1,2,5,6]
# After vmts to a zeroed destination buffer, dest offsets [0,1,4,5] should
# be [1,2,5,6] and all other words should remain 0.

.global main
main:
    # Save return address.
    mv t6, ra

    # Enable vector extension.
    li t0, MSTATUS_VS
    csrs mstatus, t0

    # ---- Configure vtype: SEW=32, LMUL=1, ta, ma ----
    # We need lambda=2.  vsetvli preserves the current vtype lambda; to set
    # lambda we use vsetvl with a full vtype value in rs2.
    #
    # RV64 vtype layout (bits):
    #   63:vill  62:60:vlambda  59:vbs  58:altfmt_A  57:altfmt_B
    #   56:8 reserved  7:vma  6:vta  5:3:vsew  2:0:vlmul
    #
    # vsew=0b010 (e32), vlmul=0b000 (m1), vta=1, vma=1, vlambda=0b010 (lambda=2)
    # => 0x20000000000000D0
    li t0, 0x2000
    slli t0, t0, 44          # t0 = 0x2000000000000000 (lambda=2 at bits 62:60)
    li t1, 0xD0
    or  t0, t0, t1           # t0 = 0x20000000000000D0
    li a1, 4                 # AVL = 4 (VL we want)
    vsetvl t2, a1, t0        # rd=t2, rs1=a1 (AVL), rs2=t0 (vtype)

    # ---- Set up source memory ----
    # 16 words starting at src_buf, values 1..16.
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

    # ---- Set up destination memory (zeroed) ----
    la a2, dst_buf
    li t0, 0
    li t1, 0
2:
    sw t0, 0(a2)
    addi a2, a2, 4
    addi t1, t1, 1
    li t2, 16
    bne t1, t2, 2b

    # ---- vmtl.v v8, (a0), a1 ----
    # Load tile from src_buf into v8.
    # rs1 = base address (a0), rs2 = LD in elements (a1).
    # We use a1 for LD.  But a1 was clobbered (we used it as AVL earlier
    # then reused a0).  Set up registers now.
    la a0, src_buf           # rs1 = source base
    li  a1, 4                # rs2 = LD = 4 (leading dimension in elements)

    # vmtl.v v8, (a0), a1   [lambda=2 encoded explicitly]
    # Encoding: lambda(3) @ 1(1) @ 00(mode,2) @ vm(1) @ rs2(5) @ rs1(5) @ 0x7(funct3) @ vd(5) @ 0x07(opcode)
    # lambda=2 => imm7 = 0b010_1_00_1 = 0x29
    # .word 0x52b57407
    .word 0x52b57407

    # ---- vmts.v v8, (a2), a3 ----
    # Store tile from v8 to dst_buf.
    la a2, dst_buf           # rs1 = destination base
    li  a3, 4                # rs2 = LD = 4

    # vmts.v v8, (a2), a3   [lambda=2 encoded explicitly]
    # .word 0x52d67427
    .word 0x52d67427

    # ---- Verify destination ----
    # dst_buf should have words at offsets [0,1,4,5] = [1,2,5,6], rest 0.
    la a2, dst_buf

    # Check offset 0 == 1
    lw t0, 0(a2)
    li t1, 1
    bne t0, t1, fail

    # Check offset 4 == 2
    lw t0, 4(a2)
    li t1, 2
    bne t0, t1, fail

    # Check offset 8 == 0 (untouched)
    lw t0, 8(a2)
    li t1, 0
    bne t0, t1, fail

    # Check offset 12 == 0 (untouched)
    lw t0, 12(a2)
    li t1, 0
    bne t0, t1, fail

    # Check offset 16 == 5
    lw t0, 16(a2)
    li t1, 5
    bne t0, t1, fail

    # Check offset 20 == 6
    lw t0, 20(a2)
    li t1, 6
    bne t0, t1, fail

    # Check offset 24 == 0 (untouched)
    lw t0, 24(a2)
    li t1, 0
    bne t0, t1, fail

    # Check offset 28 == 0 (untouched)
    lw t0, 28(a2)
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
