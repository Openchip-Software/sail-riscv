#include "common/encoding.h"

# Test for IME octuple-widening floating-point matrix multiply-accumulate
# (vf8wmmacc.vv, W=8, unscaled vm=1 form).
#
# Rows covered (VLEN=256, lambda=2):
#   r32:  OFP4 E2M1 x E2M1 -> FP32, SEW=32, LMUL=1, VL=4
#         M=4, N=2, K_eff=16, EMUL_C=2. Inactive C columns (v17) hold sNaN
#         sentinels and must stay unchanged without raising flags.
#   r64a: OFP8 E4M3 x E4M3 -> FP64, SEW=64, LMUL=1, VL=4
#         M=2, N=2, K_eff=16. Includes max normal 448 and subnormal 2^-9.
#   r64b: OFP8 E4M3 (A) x E5M2 (B) -> FP64, SEW=64, LMUL=2, VL=8
#         M=2, N=2, K_eff=32. Includes E5M2 max 57344 and subnormal 2^-16.
#   r64s: OFP8 E5M2 (A) x E4M3 (B) -> FP64 special values:
#         C[0][0] = inf * 0     -> default NaN, raises NV
#         C[0][1] = inf * NaN   -> default NaN (E4M3 NaN is quiet)
#         C[1][1] = 1 * NaN     -> default NaN
#         C[1][0] = 15.0 (finite)
# Illegal: vm=0 (microscaling not implemented), SEW=16, SEW=32 with
# altfmt_A=1 (reserved OFP4 encoding), and vstart != 0.
#
# All finite results are exact in the C format, so they are independent of
# frm and accrue no flags. Data/expected values come from a scalar reference
# that decodes OFP4/OFP8 and mirrors ime_mat_{A,B,C}_idx.
#
# vtype: 0x20...D0 = lambda=2,SEW=32,LMUL=1; D1 = LMUL=2; D8 = SEW=64,LMUL=1;
#        D9 = SEW=64,LMUL=2. altfmt_A = bit 58 (0x04..), altfmt_B = bit 57
#        (0x02..).
#
# vf8wmmacc.vv v16, v8, v12: funct6=0x17, vm=1, vs2=12, vs1=8, OPFVV, vd=16
#   => .word 0x5ec41857 (vm=0 form: 0x5cc41857)

#define VF8WMMACC .word 0x5ec41857
#define VF8WMMACC_VM0 .word 0x5cc41857
#define FFLAGS_NV 0x10

.global main
main:
    mv t6, ra

    li t0, (MSTATUS_VS | MSTATUS_FS)
    csrs mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0

    # =====================================================================
    # r32: E2M1 -> FP32.
    # =====================================================================
    csrw fflags, x0
    li t0, 0x20000000000000D1
    la a0, r32_cinit
    li a1, 16
    vsetvl t2, a1, t0
    vle32.v v16, (a0)

    li t0, 0x20000000000000D0
    li a1, 8
    vsetvl t2, a1, t0
    la a0, r32_a
    vle32.v v8, (a0)
    la a0, r32_b
    vle32.v v12, (a0)

    li a1, 4
    vsetvl t2, a1, t0
    VF8WMMACC

    li t0, 0x20000000000000D1
    li a1, 16
    vsetvl t2, a1, t0
    la a0, c_out
    vse32.v v16, (a0)

    la a2, r32_expected
    li a3, 16
    li a4, 1
    jal check32
    csrr t0, fflags
    li a4, 2
    bnez t0, fail

    # =====================================================================
    # r64a: E4M3 x E4M3 -> FP64.
    # =====================================================================
    csrw fflags, x0
    li t0, 0x20000000000000D8
    li a1, 4
    vsetvl t2, a1, t0
    la a0, r64a_cinit
    vle64.v v16, (a0)
    la a0, r64a_a
    vle64.v v8, (a0)
    la a0, r64a_b
    vle64.v v12, (a0)

    VF8WMMACC

    la a0, c_out
    vse64.v v16, (a0)
    la a2, r64a_expected
    li a3, 4
    li a4, 3
    jal check64
    csrr t0, fflags
    li a4, 4
    bnez t0, fail

    # =====================================================================
    # r64b: E4M3 (A) x E5M2 (B) -> FP64, LMUL=2.
    # =====================================================================
    csrw fflags, x0
    li t0, 0x20000000000000D8
    li a1, 4
    vsetvl t2, a1, t0
    la a0, r64b_cinit
    vle64.v v16, (a0)

    li t0, 0x20000000000000D9
    li a1, 8
    vsetvl t2, a1, t0
    la a0, r64b_a
    vle64.v v8, (a0)
    la a0, r64b_b
    vle64.v v12, (a0)

    li t0, 0x22000000000000D9   # altfmt_B=1 (E5M2)
    vsetvl t2, a1, t0
    VF8WMMACC

    li t0, 0x20000000000000D8
    li a1, 4
    vsetvl t2, a1, t0
    la a0, c_out
    vse64.v v16, (a0)
    la a2, r64b_expected
    li a3, 4
    li a4, 5
    jal check64
    csrr t0, fflags
    li a4, 6
    bnez t0, fail

    # =====================================================================
    # r64s: E5M2 (A) x E4M3 (B) special values; only NV expected.
    # =====================================================================
    csrw fflags, x0
    li t0, 0x24000000000000D8   # altfmt_A=1 (E5M2)
    li a1, 4
    vsetvl t2, a1, t0
    la a0, r64s_cinit
    vle64.v v16, (a0)
    la a0, r64s_a
    vle64.v v8, (a0)
    la a0, r64s_b
    vle64.v v12, (a0)

    VF8WMMACC

    la a0, c_out
    vse64.v v16, (a0)
    la a2, r64s_expected
    li a3, 4
    li a4, 7
    jal check64
    csrr t0, fflags
    li t1, FFLAGS_NV
    li a4, 8
    bne t0, t1, fail

    # =====================================================================
    # Illegal encodings / configurations.
    # =====================================================================

    # vm=0 requests microscaling, which is not implemented.
    li t0, 0x20000000000000D8
    li a1, 4
    vsetvl t2, a1, t0
    li s1, 0
    VF8WMMACC_VM0
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    li a4, 9
    bne s1, t1, fail

    # SEW=16 is reserved (EEW=2).
    li t0, 0x20000000000000C8
    li a1, 4
    vsetvl t2, a1, t0
    li s1, 0
    VF8WMMACC
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    li a4, 10
    bne s1, t1, fail

    # SEW=32 with altfmt_A=1 is the reserved OFP4 encoding.
    li t0, 0x24000000000000D0
    li a1, 4
    vsetvl t2, a1, t0
    li s1, 0
    VF8WMMACC
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    li a4, 11
    bne s1, t1, fail

    # vstart != 0.
    li t0, 0x20000000000000D8
    li a1, 4
    vsetvl t2, a1, t0
    li t0, 1
    csrw vstart, t0
    li s1, 0
    VF8WMMACC
    csrw vstart, x0
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    li a4, 12
    bne s1, t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    mv a0, a4
    mv ra, t6
    ret

# Compare a3 words/dwords at c_out against a2; on mismatch fail with a4.
check32:
    la a0, c_out
1:
    lw t0, 0(a0)
    lw t1, 0(a2)
    bne t0, t1, fail
    addi a0, a0, 4
    addi a2, a2, 4
    addi a3, a3, -1
    bnez a3, 1b
    ret

check64:
    la a0, c_out
1:
    ld t0, 0(a0)
    ld t1, 0(a2)
    bne t0, t1, fail
    addi a0, a0, 8
    addi a2, a2, 8
    addi a3, a3, -1
    bnez a3, 1b
    ret

# Record mcause in s1 and skip the trapping instruction.
trap_handler:
    csrr s1, mcause
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

.balign 64
# E2M1 nibbles: even element in the low nibble.
#   A rows: [1,2,3,4,6,0.5,1.5,-1,0...0], [-6,6,-4,4,-3,3,-2,2,1 x8],
#           [0.5 x16], [6,0,6,0,6,0,6,0,-0.5,0,...]
#   B cols: [1 x16], [6,-6,0.5,-0.5,2,3,4,-1.5,0,1,0,1,0,1,0,1]
r32_a:
    .byte 0x42, 0x65, 0x17, 0xa3, 0x00, 0x00, 0x00, 0x00, 0x7f, 0x6e, 0x5d, 0x4c, 0x22, 0x22, 0x22, 0x22
    .byte 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x07, 0x07, 0x07, 0x07, 0x09, 0x09, 0x09, 0x09
r32_b:
    .byte 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0xf7, 0x91, 0x54, 0xb6, 0x20, 0x20, 0x20, 0x20
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
# C row-major, active columns in v16: [0.25,-0.25, 1,2, 0,0, -8,8];
# v17 (physical columns 2,3) holds sNaN sentinels.
r32_cinit:
    .word 0x3e800000, 0xbe800000, 0x3f800000, 0x40000000
    .word 0x00000000, 0x00000000, 0xc1000000, 0x41000000
    .word 0x7fa00000, 0x7fa00000, 0x7fa00000, 0x7fa00000
    .word 0x7fa00000, 0x7fa00000, 0x7fa00000, 0x7fa00000
# [17.25, 14.25, 9, -78, 8, 5.75, 14, 83] + unchanged sentinels.
r32_expected:
    .word 0x418a0000, 0x41640000, 0x41100000, 0xc29c0000
    .word 0x41000000, 0x40b80000, 0x41600000, 0x42a60000
    .word 0x7fa00000, 0x7fa00000, 0x7fa00000, 0x7fa00000
    .word 0x7fa00000, 0x7fa00000, 0x7fa00000, 0x7fa00000

.balign 64
#   A rows: [448,-448,1,2,0.125,2^-9,-2^-6,0.875,3.5,0 x6,1], [1 x8,-1 x8]
#   B cols: [1,1,1,1,8,2^-9,1,2,4,0 x6,0.5], [0.5,0.25,1 x13,240]
r64a_a:
    .byte 0x7e, 0xfe, 0x38, 0x40, 0x20, 0x01, 0x88, 0x36, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x38
    .byte 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0xb8, 0xb8, 0xb8, 0xb8, 0xb8, 0xb8, 0xb8, 0xb8
r64a_b:
    .byte 0x38, 0x38, 0x38, 0x38, 0x50, 0x01, 0x38, 0x40, 0x48, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30
    .byte 0x30, 0x28, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x77
r64a_cinit:
    .double 1, -1, 0.5, 0
# [21.234378814697266, 358.486328125, 11.001953125, -240.25]
r64a_expected:
    .quad 0x40353c0040000000, 0x407667c800000000, 0x4026010000000000, 0xc06e080000000000

.balign 64
# LMUL=2: A/B span two registers; k<16 in the first, k>=16 in the second.
#   A rows (E4M3): [1..8] x4, [-0.5,0.25] x16
#   B cols (E5M2): [1 x16, 2^-16, 57344, 0 x14], [0.5,-0.5] x8 + [-3 x16]
r64b_a:
    .byte 0x38, 0x40, 0x44, 0x48, 0x4a, 0x4c, 0x4e, 0x50, 0x38, 0x40, 0x44, 0x48, 0x4a, 0x4c, 0x4e, 0x50
    .byte 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28
    .byte 0x38, 0x40, 0x44, 0x48, 0x4a, 0x4c, 0x4e, 0x50, 0x38, 0x40, 0x44, 0x48, 0x4a, 0x4c, 0x4e, 0x50
    .byte 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28, 0xb0, 0x28
r64b_b:
    .byte 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c
    .byte 0x38, 0xb8, 0x38, 0xb8, 0x38, 0xb8, 0x38, 0xb8, 0x38, 0xb8, 0x38, 0xb8, 0x38, 0xb8, 0x38, 0xb8
    .byte 0x01, 0x7b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2
r64b_cinit:
    .double 0, 0, 0, 0
# [114760 + 2^-16, -220, 14334 - 2^-17, 3]
r64b_expected:
    .quad 0x40fc048000100000, 0xc06b800000000000, 0x40cbfeffffc00000, 0x4008000000000000

.balign 64
#   A rows (E5M2): [+inf, 1 x15], [1 x16]
#   B cols (E4M3): [0, 1 x15], [NaN (0x7f), 1 x15]
r64s_a:
    .byte 0x7c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c
    .byte 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c, 0x3c
r64s_b:
    .byte 0x00, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38
    .byte 0x7f, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38
r64s_cinit:
    .double 0, 0, 0, 0
# [NaN, NaN, 15, NaN]
r64s_expected:
    .quad 0x7ff8000000000000, 0x7ff8000000000000, 0x402e000000000000, 0x7ff8000000000000

.balign 64
c_out:
    .fill 64, 1, 0
