#include "common/encoding.h"

# vtype.lambda write rules (spec "lambda write rules" / S:1003 discovery
# mechanism): a vsetvl request is WARL-clamped to a supported value and the
# clamped value is read back from vtype.
#
# Geometry: VLEN=256.
#
# 1. e16 (permissible lambda set {1,2,4}): requesting lambda=8 via vsetvl
#    reads back lambda=4, the largest supported value <= the request.
# 2. e32 (permissible lambda set {1,2}): requesting lambda=8 via vsetvl
#    reads back lambda=2.
# 3. A following vsetvli e32 leaves the instruction's own lambda field at
#    000 (it is outside the vsetvli immediate); vtype.lambda=2 from case 2
#    is still supported at e32, so it is retained, and vmmacc.vv executes
#    without trapping.

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    li a1, 1

    # ---- 1. vsetvl request lambda=8 at e16, m1, ta, ma ----
    # vtype = lambda=8, SEW=16, LMUL=1, ta, ma
    li t0, 0x4
    slli t0, t0, 60
    li t1, 0xC8
    or t0, t0, t1
    vsetvl t2, a1, t0

    csrr t1, vtype
    li t2, 0x3
    slli t2, t2, 60
    li t3, 0xC8
    or t2, t2, t3
    bne t1, t2, fail

    # ---- 2. vsetvl request lambda=8 at e32, m1, ta, ma ----
    # vtype = lambda=8, SEW=32, LMUL=1, ta, ma
    li t0, 0x4
    slli t0, t0, 60
    li t1, 0xD0
    or t0, t0, t1
    vsetvl t2, a1, t0

    csrr t1, vtype
    li t2, 0x2
    slli t2, t2, 60
    li t3, 0xD0
    or t2, t2, t3
    bne t1, t2, fail

    # ---- 3. vsetvli e32 retains vtype.lambda=2; vmmacc.vv does not trap ----
    la t0, trap_handler
    csrw mtvec, t0

    li a1, 4
    vsetvli t0, a1, e32, m1, ta, ma
    li t1, 4
    bne t0, t1, fail

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
