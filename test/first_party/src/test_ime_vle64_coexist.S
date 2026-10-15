#include "common/encoding.h"

# Tile load/store encodings always have inst[28] (mew) = 1. With
# Zvvmtls/Zvvmttls enabled, the standard 64-bit vector loads/stores
# (mew=0, width=111) must still decode as base V instructions and must not
# be captured as tile loads/stores.
#
# Geometry: VLEN=256, SEW=64, LMUL=1, VL=4, vtype.lambda=2.
#
# 1. vle64ff.v v8, (a0): lumop=10000 sits in the tile rs2 slot (x16 = a6).
#    With a6=1 a misdecoded tile load would read offsets [0,1,1,2] instead
#    of [0,1,2,3].
# 2. vluxei64.v v12, (a0), v4: mop=01 matches the transposing tile mode.
#    Byte indices [24,0,16,8] must load [4,1,3,2].
# 3. vsuxei64.v v12, (a2), v4 scatters back, so dst = [1,2,3,4].
# 4. vmtl.v v16, (a0), a1 with lambda field 000 uses vtype.lambda=2 and
#    LD=4: offsets [0,1,4,5] -> [1,2,5,6].

.global main
main:
    mv t6, ra

    li t0, MSTATUS_VS
    csrs mstatus, t0

    # vtype: lambda=2 (bits 62:60 = 0b010), vma=1, vta=1, e64, m1 => 0x20000000000000D8
    li t0, 0x20000000000000D8
    li a1, 4
    vsetvl t2, a1, t0
    li t1, 4
    bne t2, t1, fail

    # src_buf = [1..8] (dwords)
    la a0, src_buf
    li t0, 1
    li t1, 8
1:
    sd t0, 0(a0)
    addi a0, a0, 8
    addi t0, t0, 1
    ble t0, t1, 1b

    la a0, src_buf
    la a2, dst_buf

    # ---- 1. vle64ff.v v8, (a0) ----
    li a6, 1
    vle64ff.v v8, (a0)
    csrr t0, vl
    li t1, 4
    bne t0, t1, fail
    vse64.v v8, (a2)
    li t2, 1
    ld t0, 0(a2)
    bne t0, t2, fail
    li t2, 2
    ld t0, 8(a2)
    bne t0, t2, fail
    li t2, 3
    ld t0, 16(a2)
    bne t0, t2, fail
    li t2, 4
    ld t0, 24(a2)
    bne t0, t2, fail

    # ---- 2. vluxei64.v v12, (a0), v4 ----
    la t0, idx_buf
    vle64.v v4, (t0)
    vluxei64.v v12, (a0), v4
    la a3, chk_buf
    vse64.v v12, (a3)
    li t2, 4
    ld t0, 0(a3)
    bne t0, t2, fail
    li t2, 1
    ld t0, 8(a3)
    bne t0, t2, fail
    li t2, 3
    ld t0, 16(a3)
    bne t0, t2, fail
    li t2, 2
    ld t0, 24(a3)
    bne t0, t2, fail

    # ---- 3. vsuxei64.v v12, (a2), v4 ----
    # Clear dst_buf first, then scatter [4,1,3,2] to byte offsets [24,0,16,8].
    sd zero, 0(a2)
    sd zero, 8(a2)
    sd zero, 16(a2)
    sd zero, 24(a2)
    vsuxei64.v v12, (a2), v4
    li t2, 1
    ld t0, 0(a2)
    bne t0, t2, fail
    li t2, 2
    ld t0, 8(a2)
    bne t0, t2, fail
    li t2, 3
    ld t0, 16(a2)
    bne t0, t2, fail
    li t2, 4
    ld t0, 24(a2)
    bne t0, t2, fail

    # ---- 4. vmtl.v v16, (a0), a1 (lambda field 000 -> vtype.lambda) ----
    li a1, 4
    # lambda=000 @ 1 @ mode=00 @ vm=1 @ rs2=a1 @ rs1=a0 @ 111 @ vd=v16 @ 0000111
    .word 0x12b57807
    vse64.v v16, (a3)
    li t2, 1
    ld t0, 0(a3)
    bne t0, t2, fail
    li t2, 2
    ld t0, 8(a3)
    bne t0, t2, fail
    li t2, 5
    ld t0, 16(a3)
    bne t0, t2, fail
    li t2, 6
    ld t0, 24(a3)
    bne t0, t2, fail

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
    .fill 32, 1, 0
chk_buf:
    .fill 32, 1, 0
idx_buf:
    .dword 24, 0, 16, 8
