#include "common/encoding.h"

# Test for IME matrix multiply-accumulate with the largest C register group,
# EMUL_C=16, and for VL=0.
#
# Geometry (VLEN=256): SEW=16, LMUL=1, lambda=1 => M=16, K_eff=1,
# EMUL_C = VLEN / (SEW * lambda^2) = 16. The C tile fills v16-v31 and column
# j of C is register v16 + j, so with VL=16 (N=16) columns 8-15 are in
# v24-v31. With K_eff=1, C[i][j] += A[i] * B^T[j].
#
# Data: A[i] = i - 5 (v8), B^T[j] = 2j - 7 (v12), C[i][j] = 16j + i.
#   1. vmmacc.vv, VL=16: all 256 C elements, signed Int16.
#   2. vfmmacc.vv FP16, VL=16: all 256 C elements. Every value is an
#      integer below 2048, so the results are exact and do not depend on frm.
#   3. vmmacc.vv and vfmmacc.vv with vd=v8 (not a multiple of EMUL_C) raise
#      illegal instruction.
#   4. vmmacc.vv, VL=0: no trap, C unchanged. Runs before case 1.
#   5. vfmmacc.vv FP16, VL=0: no trap. Runs before case 2.
#
# vtype 0x10000000000000C8: lambda=1, SEW=16, LMUL=1, ta, ma.
# vmmacc.vv  v16, v8, v12: funct6=0x38, vm=1, OPIVV => .word 0xe2c40857
# vfmmacc.vv v16, v8, v12: funct6=0x14, vm=1, OPFVV => .word 0x52c41857
# The vd=v8 forms are 0xe2c40457 and 0x52c41457.

#define VMMACC .word 0xe2c40857
#define VFMMACC .word 0x52c41857
#define VMMACC_VD8 .word 0xe2c40457
#define VFMMACC_VD8 .word 0x52c41457
#define VTYPE_E16_L1 0x10000000000000C8

.global main
main:
    mv t6, ra

    li t0, (MSTATUS_VS | MSTATUS_FS)
    csrs mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0

    # =====================================================================
    # Integer: vmmacc.vv.
    # =====================================================================
    la a0, int_cinit
    jal load_c
    la a0, int_a
    la a2, int_b
    jal load_ab

    # 4. VL=0.
    li t0, VTYPE_E16_L1
    li a1, 0
    vsetvl t2, a1, t0
    li s1, 0
    VMMACC
    li a4, 8
    bnez s1, fail
    jal store_c
    la a2, int_cinit
    li a4, 9
    jal check_c

    # 1. VL=16.
    li t0, VTYPE_E16_L1
    li a1, 16
    vsetvl t2, a1, t0
    li a4, 1
    bne t2, a1, fail
    li s1, 0
    VMMACC
    li a4, 2
    bnez s1, fail
    jal store_c
    la a2, int_expected
    li a4, 3
    jal check_c

    # =====================================================================
    # FP16: vfmmacc.vv.
    # =====================================================================
    la a0, fp_cinit
    jal load_c
    la a0, fp_a
    la a2, fp_b
    jal load_ab

    # 5. VL=0.
    li t0, VTYPE_E16_L1
    li a1, 0
    vsetvl t2, a1, t0
    li s1, 0
    VFMMACC
    li a4, 10
    bnez s1, fail

    # 2. VL=16.
    li t0, VTYPE_E16_L1
    li a1, 16
    vsetvl t2, a1, t0
    li s1, 0
    VFMMACC
    li a4, 4
    bnez s1, fail
    jal store_c
    la a2, fp_expected
    li a4, 5
    jal check_c

    # =====================================================================
    # 3. vd=v8 is not aligned to EMUL_C=16.
    # =====================================================================
    li s1, 0
    VMMACC_VD8
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    li a4, 6
    bne s1, t1, fail
    li s1, 0
    VFMMACC_VD8
    li a4, 7
    bne s1, t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    mv a0, a4
    mv ra, t6
    ret

# Load the 256 SEW=16 elements at a0 into v16-v31.
load_c:
    li a1, 128
    vsetvli t1, a1, e16, m8, ta, ma
    vle16.v v16, (a0)
    addi a0, a0, 256
    vle16.v v24, (a0)
    ret

# Load the 16 A elements at a0 into v8 and the 16 B^T elements at a2 into v12.
load_ab:
    li a1, 16
    vsetvli t1, a1, e16, m1, ta, ma
    vle16.v v8, (a0)
    vle16.v v12, (a2)
    ret

# Store v16-v31 to c_out.
store_c:
    li a1, 128
    vsetvli t1, a1, e16, m8, ta, ma
    la a0, c_out
    vse16.v v16, (a0)
    addi a0, a0, 256
    vse16.v v24, (a0)
    ret

# Compare the 256 halfwords at c_out against a2; on mismatch fail with a4.
check_c:
    la a0, c_out
    li a3, 256
1:
    lh t0, 0(a0)
    lh t1, 0(a2)
    bne t0, t1, fail
    addi a0, a0, 2
    addi a2, a2, 2
    addi a3, a3, -1
    bnez a3, 1b
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
# C tables hold element i of register v16 + j at index 16j + i.
int_a:
    .half -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
int_b:
    .half -7, -5, -3, -1, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23
int_cinit:
    .half 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
    .half 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31
    .half 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47
    .half 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63
    .half 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79
    .half 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95
    .half 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111
    .half 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127
    .half 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143
    .half 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159
    .half 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175
    .half 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191
    .half 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207
    .half 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223
    .half 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239
    .half 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255
int_expected:
    .half 35, 29, 23, 17, 11, 5, -1, -7, -13, -19, -25, -31, -37, -43, -49, -55
    .half 41, 37, 33, 29, 25, 21, 17, 13, 9, 5, 1, -3, -7, -11, -15, -19
    .half 47, 45, 43, 41, 39, 37, 35, 33, 31, 29, 27, 25, 23, 21, 19, 17
    .half 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53, 53
    .half 59, 61, 63, 65, 67, 69, 71, 73, 75, 77, 79, 81, 83, 85, 87, 89
    .half 65, 69, 73, 77, 81, 85, 89, 93, 97, 101, 105, 109, 113, 117, 121, 125
    .half 71, 77, 83, 89, 95, 101, 107, 113, 119, 125, 131, 137, 143, 149, 155, 161
    .half 77, 85, 93, 101, 109, 117, 125, 133, 141, 149, 157, 165, 173, 181, 189, 197
    .half 83, 93, 103, 113, 123, 133, 143, 153, 163, 173, 183, 193, 203, 213, 223, 233
    .half 89, 101, 113, 125, 137, 149, 161, 173, 185, 197, 209, 221, 233, 245, 257, 269
    .half 95, 109, 123, 137, 151, 165, 179, 193, 207, 221, 235, 249, 263, 277, 291, 305
    .half 101, 117, 133, 149, 165, 181, 197, 213, 229, 245, 261, 277, 293, 309, 325, 341
    .half 107, 125, 143, 161, 179, 197, 215, 233, 251, 269, 287, 305, 323, 341, 359, 377
    .half 113, 133, 153, 173, 193, 213, 233, 253, 273, 293, 313, 333, 353, 373, 393, 413
    .half 119, 141, 163, 185, 207, 229, 251, 273, 295, 317, 339, 361, 383, 405, 427, 449
    .half 125, 149, 173, 197, 221, 245, 269, 293, 317, 341, 365, 389, 413, 437, 461, 485
fp_a:
    .half 0xc500, 0xc400, 0xc200, 0xc000, 0xbc00, 0x0000, 0x3c00, 0x4000, 0x4200, 0x4400, 0x4500, 0x4600, 0x4700, 0x4800, 0x4880, 0x4900
fp_b:
    .half 0xc700, 0xc500, 0xc200, 0xbc00, 0x3c00, 0x4200, 0x4500, 0x4700, 0x4880, 0x4980, 0x4a80, 0x4b80, 0x4c40, 0x4cc0, 0x4d40, 0x4dc0
fp_cinit:
    .half 0x0000, 0x3c00, 0x4000, 0x4200, 0x4400, 0x4500, 0x4600, 0x4700, 0x4800, 0x4880, 0x4900, 0x4980, 0x4a00, 0x4a80, 0x4b00, 0x4b80
    .half 0x4c00, 0x4c40, 0x4c80, 0x4cc0, 0x4d00, 0x4d40, 0x4d80, 0x4dc0, 0x4e00, 0x4e40, 0x4e80, 0x4ec0, 0x4f00, 0x4f40, 0x4f80, 0x4fc0
    .half 0x5000, 0x5020, 0x5040, 0x5060, 0x5080, 0x50a0, 0x50c0, 0x50e0, 0x5100, 0x5120, 0x5140, 0x5160, 0x5180, 0x51a0, 0x51c0, 0x51e0
    .half 0x5200, 0x5220, 0x5240, 0x5260, 0x5280, 0x52a0, 0x52c0, 0x52e0, 0x5300, 0x5320, 0x5340, 0x5360, 0x5380, 0x53a0, 0x53c0, 0x53e0
    .half 0x5400, 0x5410, 0x5420, 0x5430, 0x5440, 0x5450, 0x5460, 0x5470, 0x5480, 0x5490, 0x54a0, 0x54b0, 0x54c0, 0x54d0, 0x54e0, 0x54f0
    .half 0x5500, 0x5510, 0x5520, 0x5530, 0x5540, 0x5550, 0x5560, 0x5570, 0x5580, 0x5590, 0x55a0, 0x55b0, 0x55c0, 0x55d0, 0x55e0, 0x55f0
    .half 0x5600, 0x5610, 0x5620, 0x5630, 0x5640, 0x5650, 0x5660, 0x5670, 0x5680, 0x5690, 0x56a0, 0x56b0, 0x56c0, 0x56d0, 0x56e0, 0x56f0
    .half 0x5700, 0x5710, 0x5720, 0x5730, 0x5740, 0x5750, 0x5760, 0x5770, 0x5780, 0x5790, 0x57a0, 0x57b0, 0x57c0, 0x57d0, 0x57e0, 0x57f0
    .half 0x5800, 0x5808, 0x5810, 0x5818, 0x5820, 0x5828, 0x5830, 0x5838, 0x5840, 0x5848, 0x5850, 0x5858, 0x5860, 0x5868, 0x5870, 0x5878
    .half 0x5880, 0x5888, 0x5890, 0x5898, 0x58a0, 0x58a8, 0x58b0, 0x58b8, 0x58c0, 0x58c8, 0x58d0, 0x58d8, 0x58e0, 0x58e8, 0x58f0, 0x58f8
    .half 0x5900, 0x5908, 0x5910, 0x5918, 0x5920, 0x5928, 0x5930, 0x5938, 0x5940, 0x5948, 0x5950, 0x5958, 0x5960, 0x5968, 0x5970, 0x5978
    .half 0x5980, 0x5988, 0x5990, 0x5998, 0x59a0, 0x59a8, 0x59b0, 0x59b8, 0x59c0, 0x59c8, 0x59d0, 0x59d8, 0x59e0, 0x59e8, 0x59f0, 0x59f8
    .half 0x5a00, 0x5a08, 0x5a10, 0x5a18, 0x5a20, 0x5a28, 0x5a30, 0x5a38, 0x5a40, 0x5a48, 0x5a50, 0x5a58, 0x5a60, 0x5a68, 0x5a70, 0x5a78
    .half 0x5a80, 0x5a88, 0x5a90, 0x5a98, 0x5aa0, 0x5aa8, 0x5ab0, 0x5ab8, 0x5ac0, 0x5ac8, 0x5ad0, 0x5ad8, 0x5ae0, 0x5ae8, 0x5af0, 0x5af8
    .half 0x5b00, 0x5b08, 0x5b10, 0x5b18, 0x5b20, 0x5b28, 0x5b30, 0x5b38, 0x5b40, 0x5b48, 0x5b50, 0x5b58, 0x5b60, 0x5b68, 0x5b70, 0x5b78
    .half 0x5b80, 0x5b88, 0x5b90, 0x5b98, 0x5ba0, 0x5ba8, 0x5bb0, 0x5bb8, 0x5bc0, 0x5bc8, 0x5bd0, 0x5bd8, 0x5be0, 0x5be8, 0x5bf0, 0x5bf8
fp_expected:
    .half 0x5060, 0x4f40, 0x4dc0, 0x4c40, 0x4980, 0x4500, 0xbc00, 0xc700, 0xca80, 0xccc0, 0xce40, 0xcfc0, 0xd0a0, 0xd160, 0xd220, 0xd2e0
    .half 0x5120, 0x50a0, 0x5020, 0x4f40, 0x4e40, 0x4d40, 0x4c40, 0x4a80, 0x4880, 0x4500, 0x3c00, 0xc200, 0xc700, 0xc980, 0xcb80, 0xccc0
    .half 0x51e0, 0x51a0, 0x5160, 0x5120, 0x50e0, 0x50a0, 0x5060, 0x5020, 0x4fc0, 0x4f40, 0x4ec0, 0x4e40, 0x4dc0, 0x4d40, 0x4cc0, 0x4c40
    .half 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0, 0x52a0
    .half 0x5360, 0x53a0, 0x53e0, 0x5410, 0x5430, 0x5450, 0x5470, 0x5490, 0x54b0, 0x54d0, 0x54f0, 0x5510, 0x5530, 0x5550, 0x5570, 0x5590
    .half 0x5410, 0x5450, 0x5490, 0x54d0, 0x5510, 0x5550, 0x5590, 0x55d0, 0x5610, 0x5650, 0x5690, 0x56d0, 0x5710, 0x5750, 0x5790, 0x57d0
    .half 0x5470, 0x54d0, 0x5530, 0x5590, 0x55f0, 0x5650, 0x56b0, 0x5710, 0x5770, 0x57d0, 0x5818, 0x5848, 0x5878, 0x58a8, 0x58d8, 0x5908
    .half 0x54d0, 0x5550, 0x55d0, 0x5650, 0x56d0, 0x5750, 0x57d0, 0x5828, 0x5868, 0x58a8, 0x58e8, 0x5928, 0x5968, 0x59a8, 0x59e8, 0x5a28
    .half 0x5530, 0x55d0, 0x5670, 0x5710, 0x57b0, 0x5828, 0x5878, 0x58c8, 0x5918, 0x5968, 0x59b8, 0x5a08, 0x5a58, 0x5aa8, 0x5af8, 0x5b48
    .half 0x5590, 0x5650, 0x5710, 0x57d0, 0x5848, 0x58a8, 0x5908, 0x5968, 0x59c8, 0x5a28, 0x5a88, 0x5ae8, 0x5b48, 0x5ba8, 0x5c04, 0x5c34
    .half 0x55f0, 0x56d0, 0x57b0, 0x5848, 0x58b8, 0x5928, 0x5998, 0x5a08, 0x5a78, 0x5ae8, 0x5b58, 0x5bc8, 0x5c1c, 0x5c54, 0x5c8c, 0x5cc4
    .half 0x5650, 0x5750, 0x5828, 0x58a8, 0x5928, 0x59a8, 0x5a28, 0x5aa8, 0x5b28, 0x5ba8, 0x5c14, 0x5c54, 0x5c94, 0x5cd4, 0x5d14, 0x5d54
    .half 0x56b0, 0x57d0, 0x5878, 0x5908, 0x5998, 0x5a28, 0x5ab8, 0x5b48, 0x5bd8, 0x5c34, 0x5c7c, 0x5cc4, 0x5d0c, 0x5d54, 0x5d9c, 0x5de4
    .half 0x5710, 0x5828, 0x58c8, 0x5968, 0x5a08, 0x5aa8, 0x5b48, 0x5be8, 0x5c44, 0x5c94, 0x5ce4, 0x5d34, 0x5d84, 0x5dd4, 0x5e24, 0x5e74
    .half 0x5770, 0x5868, 0x5918, 0x59c8, 0x5a78, 0x5b28, 0x5bd8, 0x5c44, 0x5c9c, 0x5cf4, 0x5d4c, 0x5da4, 0x5dfc, 0x5e54, 0x5eac, 0x5f04
    .half 0x57d0, 0x58a8, 0x5968, 0x5a28, 0x5ae8, 0x5ba8, 0x5c34, 0x5c94, 0x5cf4, 0x5d54, 0x5db4, 0x5e14, 0x5e74, 0x5ed4, 0x5f34, 0x5f94
c_out:
    .zero 512
