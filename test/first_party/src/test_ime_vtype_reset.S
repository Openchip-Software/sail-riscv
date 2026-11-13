#include "common/encoding.h"

# reset_sys sets vtype.vill = 1 on reset and must clear the IME vtype
# fields alongside the base vtype fields it already clears: the
# specification states that vlambda, vbs, altfmt_A and altfmt_B read
# 0 whenever vtype.vill = 1, including on reset (S:865-867).
#
# crt0 issues no vset* instruction before main, so the first CSR read
# below observes the state left by the simulator's single power-on
# reset, before any code has written vtype.
#
# vtype bit positions at XLEN=64 (model/extensions/V/vext_regs.sail):
#   vill = 63, vlambda = 62:60, vbs = 59, altfmt_A = 58, altfmt_B = 57.

.global main
main:
    mv t6, ra

    # The vtype CSR is accessible only while mstatus.VS != Off
    # (currentlyEnabled(Ext_Zve32x), model/extensions/V/vext_control.sail).
    # This only enables CSR access; it does not write vtype itself, so
    # the read below still observes reset_sys's output.
    li t0, MSTATUS_VS
    csrs mstatus, t0

    csrr t0, vtype

    # vill (bit 63) must be 1.
    bgez t0, fail

    # vlambda (bits 62:60) must be 0b000.
    srli t1, t0, 60
    andi t1, t1, 0x7
    bnez t1, fail

    # vbs (bit 59) must be 0.
    srli t1, t0, 59
    andi t1, t1, 0x1
    bnez t1, fail

    # altfmt_A (bit 58) must be 0.
    srli t1, t0, 58
    andi t1, t1, 0x1
    bnez t1, fail

    # altfmt_B (bit 57) must be 0.
    srli t1, t0, 57
    andi t1, t1, 0x1
    bnez t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret
