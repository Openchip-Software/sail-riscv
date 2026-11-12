#include "common/encoding.h"

# execute_ime_fp_engine and execute_ime_int_mx call set_vstart(zeros())
# before RETIRE_SUCCESS, which also calls dirty_v_context() and sets
# mstatus.VS to Dirty. At VL=0 the group loop in each function writes
# no C element, so this call is the only place that touches
# mstatus.VS. With mstatus.VS left at Clean beforehand, a VL=0 run of
# vfmmacc.vv or vfwimmacc.vv must still leave mstatus.VS at Dirty.
#
# vsetvl is itself gated by currentlyEnabled(Ext_Zve32x), which
# requires mstatus.VS != Off, and vsetvl's own set_vstart(zeros())
# call dirties mstatus.VS; mstatus.VS is forced back to Clean after
# each vsetvl, immediately before the instruction under test, so the
# check below observes only that instruction's effect.
#
# mstatus.VS occupies bits [10:9] (MSTATUS_VS = 0x600); Clean is 0b10,
# Dirty is 0b11.
#
# 1. vfmmacc.vv (unscaled FP engine, vm=1), SEW=32, lambda=2, LMUL=1,
#    VL=0: mstatus.VS reads Dirty afterward.
# 2. vfwimmacc.vv (integer-input MX engine, vm=0 of vwmmacc.vv),
#    SEW=16, lambda=4, LMUL=8, VL=0: mstatus.VS reads Dirty afterward.

#define MSTATUS_VS_CLEAN (0x2 << 9)

.global main
main:
    mv t6, ra

    # Enable floating-point and vector state (Zvvfmm and the MX rows
    # require Ext_F through Zve32f; vsetvl itself requires Ext_Zve32x,
    # which needs mstatus.VS != Off).
    li t0, (MSTATUS_VS | MSTATUS_FS)
    csrs mstatus, t0

    # =====================================================================
    # 1. vfmmacc.vv at VL=0.
    # =====================================================================
    li t0, 0x20000000000000D0   # lambda=2, SEW=32, LMUL=1, ta, ma
    li a1, 0
    vsetvl t2, a1, t0
    bnez t2, fail

    # vsetvl dirtied mstatus.VS; force it back to Clean immediately
    # before the instruction under test.
    li t0, MSTATUS_VS
    csrc mstatus, t0
    li t0, MSTATUS_VS_CLEAN
    csrs mstatus, t0

    # vfmmacc.vv v16, v8, v12 (funct6=0x14, vm=1, vs2=12, vs1=8, vd=16)
    .word 0x52c41857

    csrr t0, mstatus
    li t1, MSTATUS_VS
    and t0, t0, t1
    bne t0, t1, fail

    # =====================================================================
    # 2. vfwimmacc.vv at VL=0.
    # =====================================================================
    li t0, MSTATUS_VS
    csrs mstatus, t0

    li t0, 0x300000000000000b   # lambda=4, SEW=16, LMUL=8, ta, ma
    li a1, 0
    vsetvl t2, a1, t0
    bnez t2, fail

    li t0, MSTATUS_VS
    csrc mstatus, t0
    li t0, MSTATUS_VS_CLEAN
    csrs mstatus, t0

    # vfwimmacc.vv v24, v8, v16, v0.scale (funct6=0x39, vm=0, vs2=16,
    # vs1=8, vd=24)
    .word 0xe5040c57

    csrr t0, mstatus
    li t1, MSTATUS_VS
    and t0, t0, t1
    bne t0, t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret
