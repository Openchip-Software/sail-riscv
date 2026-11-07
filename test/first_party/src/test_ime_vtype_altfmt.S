#include "common/encoding.h"

# vtype.altfmt (bit 8, Zvfbfa position) selects the IME C accumulator
# format. With IME enabled:
# 1. vsetvli with zimm[8]=1 sets vtype.altfmt.
# 2. vsetivli with zimm[8]=1 sets it too; a later vsetvli with zimm[8]=0
#    clears it.
# 3. vsetvl writes it from rs2 bit 8.
# 4. vsetvli with zimm[9]=1 (still reserved) sets vill.

#define VTYPE_ALTFMT (1 << 8)

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    li a1, 4

    # ---- 1. vsetvli t0, a1, e16, m1, zimm[8]=1 ----
    .word 0x1085f2d7
    csrr t1, vtype
    andi t2, t1, VTYPE_ALTFMT
    beqz t2, fail
    bltz t1, fail

    # ---- 2. vsetivli t0, 4, e16, m1, zimm[8]=1; then vsetvli clears ----
    vsetvli t0, a1, e16, m1, ta, ma
    .word 0xd08272d7
    csrr t1, vtype
    andi t2, t1, VTYPE_ALTFMT
    beqz t2, fail
    vsetvli t0, a1, e16, m1, tu, mu
    csrr t1, vtype
    andi t2, t1, VTYPE_ALTFMT
    bnez t2, fail

    # ---- 3. vsetvl with rs2 bit 8 ----
    li t3, (VTYPE_ALTFMT | 0x08)
    vsetvl t0, a1, t3
    csrr t1, vtype
    andi t2, t1, VTYPE_ALTFMT
    beqz t2, fail

    # ---- 4. vsetvli with reserved zimm[9]=1 -> vill ----
    .word 0x2085f2d7
    csrr t1, vtype
    bgez t1, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    li a0, 1
    mv ra, t6
    ret
