#include "common/encoding.h"

# vstart is VSTART_MANDATORY for the unscaled integer matrix
# multiply-accumulate family: the specification requires an
# illegal-instruction exception for any nonzero vstart (S:1272,
# S:5449). execute_ime_int_mmacc (model/extensions/IME/ime_mem_insts.sail)
# enforces this with illegal_vstart(VSTART_MANDATORY, ...) for every
# widening factor W, including vmmacc.vv (W=1) and vwmmacc.vv (W=2).
#
# Geometry: VLEN=256, SEW=32, LMUL=1, lambda=2 => VL=4, EMUL_C=2.
#
# 1. vmmacc.vv with vstart=1 traps with mcause=2 and leaves vstart
#    unchanged.
# 2. vwmmacc.vv with vstart=1 traps with mcause=2 and leaves vstart
#    unchanged.

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    la t0, trap_handler
    csrw mtvec, t0

    li t0, 0x20000000000000D0   # lambda=2, SEW=32, LMUL=1, ta, ma
    li a1, 4
    vsetvl t2, a1, t0

    # ---- 1. vmmacc.vv with vstart = 1 ----
    li s2, 1
    csrw vstart, s2
    li s1, 0
    # vmmacc.vv v16, v8, v12 (funct6=0x38, vm=1, vs2=12, vs1=8, vd=16)
    .word 0xe2c40857
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail
    csrr t0, vstart
    bne t0, s2, fail

    # ---- 2. vwmmacc.vv with vstart = 1 ----
    csrw vstart, s2
    li s1, 0
    # vwmmacc.vv v16, v8, v12 (funct6=0x39, vm=1, vs2=12, vs1=8, vd=16)
    .word 0xe6c40857
    li t1, CAUSE_ILLEGAL_INSTRUCTION
    bne s1, t1, fail
    csrr t0, vstart
    bne t0, s2, fail

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
