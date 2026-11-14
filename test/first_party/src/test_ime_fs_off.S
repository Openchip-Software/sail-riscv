#include "common/encoding.h"

# Zvvfmm requires Zve32f, which requires Ext_F and therefore the
# mstatus.FS != Off check (tbl-extensions S:808-843; ime_types.sail). Zvvmm
# only requires Zve32x, which has no Ext_F/FS dependency.
#
# With mstatus.FS forced to Off:
#   1. vfmmacc.vv (SEW=32, lambda=2, LMUL=1 -- the geometry
#      test_ime_vfmmacc.S verifies for value correctness) raises an
#      illegal-instruction exception.
#   2. vmmacc.vv (SEW=32, lambda=2, LMUL=1 -- the geometry
#      test_ime_vtype_lambda.S verifies does not trap) still executes.

.global main
main:
    mv t6, ra

    # Enable vector state but force FS to Off.
    li t0, MSTATUS_VS
    csrs mstatus, t0
    li t0, MSTATUS_FS
    csrc mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0

    # ---- 1. vfmmacc.vv raises illegal instruction with FS=Off ----
    li t0, 0x20000000000000D0 # lambda=2, SEW=32, LMUL=1, ta, ma
    li a1, 4
    vsetvl t2, a1, t0

    li s1, 0
    # vfmmacc.vv v16, v8, v12 (funct6=0x14, vm=1, vs2=12, vs1=8, vd=16)
    .word 0x52c41857
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail

    # ---- 2. vmmacc.vv still executes with FS=Off ----
    li s1, 0
    # vmmacc.vv v16, v8, v12 (funct6=0x38, vm=1, vs2=12, vs1=8, vd=16)
    .word 0xe2c40857
    bnez s1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret

# Record mcause in s1 and skip the trapping instruction.
.balign 4
trap_handler:
    csrr s1, mcause
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret
