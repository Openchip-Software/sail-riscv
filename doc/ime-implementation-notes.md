# Integrated Matrix Extension (IME / Zvvm) implementation notes

This is the status note for the Sail implementation of the draft RISC-V Integrated Matrix Extension. It documents what is implemented in this tree, how it is tested, and its known limitations.

Spec version: `riscv/integrated-matrix-extension` commit `58810918`, file `src/unpriv/integrated-matrix.adoc`.

## Implemented pieces

- Draft extension plumbing:
  - `Ext_Zvvmm` for integer matrix multiply-accumulate.
  - `Ext_Zvvmtls` for order-preserving tile load/store.
  - `Ext_Zvvmttls` for transposing tile load/store.
  - `Ext_Zvvfmm` gates the unscaled floating-point matrix multiply-accumulate rows.
  - 30 fine-grained microscaling extensions: `Zvvx{ofp4,ofp8}{fp16,bf16,fp32,fp64}mm` / `Zvvx{i4,i8}{...}mm` (BS=32) and their `Zvvxn*` (BS=16) forms, per `tbl-mx-extensions`. `Zvvxn*` implies the matching `Zvvx*`; a floating-point-input `Zvvx*` also implies its base row (see "Microscaling (MX) matrix multiply-accumulate"). Every microscaling extension with a BF16, FP16, or FP32 accumulator requires `Zve32f`; the four with an FP64 accumulator require `Zve64d`. The integer-input ones (`Zvvxi4/8{bf16,fp16,fp32,fp64}mm` and their `Zvvxni*` forms) require `Zve32f` too, although `tbl-mx-extensions` names no dependency for them: they accumulate into a floating-point C, read `frm`, and write `fflags` (AMB-06).
  - 31 individual computational extensions, one per (input type, accumulator type) row in `tbl-extensions` (`Zvvi4i8mm` .. `Zvvi64mm`, `Zvvbf16mm` .. `Zvvfp64mm`, `Zvvofp4bf16mm` .. `Zvvofp8mm`). `Zvvmm` implies every integer individual extension and `Zvvfmm` implies every floating-point one, including the nine whose own dependency (`Zve64x` for the four Int64-accumulator extensions, `Zve64d` for the five FP64-accumulator extensions) is stronger than the family's own dependency (`Zve32x`/`Zve32f`): `currentlyEnabled` for those nine is also true when the implying family is enabled and the stronger dependency is not. `ime_int_row_ok` and `ime_fp_base_row_ok` check `Zve64x`/`Zve64d` explicitly at their SEW=64 cells for this reason (AMB-15). An extension implied this way does not appear in the ISA string unless its own config flag is also set to `true` (the same rule `Zvfhmin` already follows).
- IME `vtype` high fields:
  - `vlambda` in bits `XLEN-2:XLEN-4`.
  - `vbs` in bit `XLEN-5`.
  - `altfmt_A` in bit `XLEN-6`.
  - `altfmt_B` in bit `XLEN-7`.
  - `altfmt` (Zvfbfa position) in bit 8: selects the C accumulator format (FP16/BF16 at `SEW=16`).
  - On reset, and whenever `vtype.vill=1`, `vlambda`, `vbs`, `altfmt_A`, and `altfmt_B` read as cleared (S:865-867).
- Lambda helper behavior:
  - Encodings map as `001=1`, `010=2`, `011=4`, `100=8`, `101=16`, `110=32`, `111=64`.
  - A lambda value is permissible for a given `(VLEN, SEW)` when `EMUL_C = VLEN / (SEW * lambda^2)` is an integer in `{1, 2, 4, 8, 16}` (the "Selected lambda" rule, S:975-1003). The model supports every permissible lambda, so "permissible" and "supported" coincide (AMB-11). At `VLEN=256` the supported sets are `e8 -> {2,4}`, `e16 -> {1,2,4}`, `e32 -> {1,2}`, `e64 -> {1,2}`.
  - Lambda write rules (`ime_select_vtype_lambda`): a write of `000` retains the current `vtype.lambda` if it is still supported for the new SEW, otherwise it selects the largest supported lambda; outside the IME-legal `(VLEN, SEW)` domain it selects `000`. A nonzero write retains the requested value if supported; otherwise it selects the largest supported value at most the request, or, if none is that small, the smallest supported value; outside the IME-legal domain it selects `000`.
  - `vsetvli` and `vsetivli` carry no lambda request of their own (the field is outside the `vtypei` immediate), so they always pass `000` to the write rule above, which preserves `vtype.lambda` when it is still supported or reselects it otherwise. `vsetvl` passes `vtype.lambda` from `rs2` directly, so it can request any value, including `000`.
- Vector configuration interaction:
  - With an IME extension enabled, `zimm[8]` on `vsetvli`/`vsetivli` writes `altfmt` (as in Zvfbfa); `zimm[10:9]` stay reserved.
  - `vsetvl` accepts the full `vtype` value, including every IME field, and applies the lambda write rule above.
- Order-preserving tile load/store:
  - `vmtl.v` and `vmts.v` decode for `Zvvmtls`.
  - Implemented for the standard vector element widths handled by the vector model (`SEW=8,16,32,64`).
  - The instruction-immediate lambda field, when nonzero, overrides `vtype.lambda`; `000` selects `vtype.lambda`. Either way the resulting lambda value must be permissible for the current `(VLEN, SEW)` (AMB-11); it is not WARL-clamped the way `vtype.lambda` itself is (S:2708-2720).
  - `VL` shall be a multiple of `lambda * LMUL`, or the instruction raises illegal instruction (AMB-12); `VL=0` remains a legal no-op, since `0 % (lambda * LMUL) == 0`.
  - Register layout (both tile modes): tile element `i` lives at register-group element `ime_tile_reg_idx(i, LMUL, lambda, VLEN/SEW)`, the layout the matrix multiplies read. The mask bit is indexed by tile element `i`. Only active elements are written; prestart, inactive and tail elements stay undisturbed. Example `LMUL=2`, `lambda=2`, `VLEN/SEW=8`: tile elements `0..7` land at `[0,1,8,9,2,3,10,11]`.
  - Uses the order-preserving memory address formula in `ime_tile_ordered_mem_off`: `linesize = lambda * LMUL`, `mem_off = (i / linesize) * LD + (i % linesize)`.
  - A zero value in `rs2` (`x0` or any register holding 0) selects the natural leading dimension `LD = lambda * LMUL`.
  - A masked load (`vm=0`) with `vd=v0` raises illegal instruction (also for `vmttl.v`). A masked store with `vs3=v0` is legal (AMB-13): the IME spec restricts only masked loads (S:2719-2720), and the store path has no `valid_rd_mask` check.
- Transposing tile load/store:
  - `vmttl.v` and `vmtts.v` decode for `Zvvmttls`. Decode is mode-gated: order-preserving mode (`mode=00`) requires `Zvvmtls`; transposing mode (`mode=01`) requires `Zvvmttls`. Neither mode requires both extensions.
  - Implemented for `SEW=8,16,32,64`, sharing the same lambda, mask, tail, prestart, `vstart`, `VL` divisibility, and memory-exception behavior as `vmtl.v`/`vmts.v`.
  - The active storage-element tile shape is `cols = lambda * LMUL` columns by `rows = VL / cols` rows.
  - Uses the transposing memory address formula in `ime_tile_transposed_mem_off`: `mem_off = (i % cols) * LD + (i / cols)`. For a 2x2 tile with `LD=4` this yields offsets `[0,4,1,5]`, versus `[0,1,4,5]` for the order-preserving traversal.
  - A zero value in `rs2` selects the natural leading dimension `LD = VLEN / (SEW * lambda)`.
  - Transposing transposes `SEW`-bit storage elements only; it does not unpack, transpose, or repack `W>1` logical elements that may be packed inside a `SEW`-bit storage element.
  - Inactive/tail destination elements for `vmttl.v` remain undisturbed; inactive/tail elements for `vmtts.v` do not write memory or fault.
- Generalized integer GEMM executor (`execute_ime_int_gemm`), shared by `vmmacc.vv` (W=1), `vwmmacc.vv` (W=2), `vqmmacc.vv` (W=4), and `v8wmmacc.vv` (W=8):
  - Takes the geometry that `ime_gemm_geometry(W)` decodes for the instruction's widening factor `W`: `K_eff = lambda * W * LMUL`, `storage_K = lambda * LMUL`, `M = VLEN / (SEW * lambda)`, `N = VL / storage_K`, `N_max = M`, `EMUL_C = VLEN / (SEW * lambda^2)`.
  - The physical storage geometry is the same for all `W`: each matrix row holds `storage_K = lambda * LMUL` `SEW`-bit storage elements along K, addressed via `ime_mat_A_idx`/`ime_mat_B_idx`/`ime_mat_C_idx` (built on `ime_tile_reg_idx`).
  - For `W>1` each `SEW`-bit storage element packs `W` logical input elements of width `EEW = SEW / W`. Logical index `k` maps to storage column `k / W` and lane `k % W` (`ime_packed_storage_col`/`ime_packed_lane`); `ime_packed_subelement_value` extracts the lane in little-endian lane order and sign- or zero-extends it per `altfmt_A/B`. Element `k` occupies bits `[k*EEW + EEW-1 : k*EEW]`, including the sub-byte Int4 (`EEW=4`) nibble packing (even element = lower nibble, odd element = upper nibble).
  - `W` is 1, 2, 4 or 8, fixed by the instruction. `execute_ime_int_mmacc` applies these checks to a `vm=1` encoding, in this order:
    - `ime_int_row_ok(W, SEW)`: the individual extension that `tbl-int-encoding-map` names for the `(W, SEW)` cell is enabled. The `SEW=64` cells also require `Zve64x`. A `(W, SEW)` cell with no row in the table, such as `vqmmacc.vv` at `SEW=8`, fails this check.
    - `valid_vtype()`.
    - `vstart` is zero (`VSTART_MANDATORY`).
    - `ime_gemm_geometry(W)`, the geometry helper that the floating-point and MX paths also call. It requires `LMUL >= 1` and a nonzero `vtype.lambda` that `ime_lambda_supported_for_vsew` accepts for the current `SEW`. It requires `SEW % W == 0` and an `EEW = SEW/W` in `{4,8,16,32,64}` (`ime_int_eew_supported`). It requires `M % lambda == 0` and `EMUL_C = M / lambda` in `{1,2,4,8,16}` (`ime_group_size_legal`). It requires `VL` to be a multiple of `storage_K = lambda * LMUL`, not of the widened `K_eff = lambda * W * LMUL`, because `VL` counts storage-width elements. This matches `vl_div = lambda * LMUL` in `decode_gemm_geometry` (S:4880-4907). It also requires `N <= N_max`.
    - `ime_gemm_groups_ok`, which the floating-point and MX paths also call. It requires `vs1` and `vs2` to be aligned to `LMUL` and `vd` to be aligned to `EMUL_C`. It also requires `vd` to overlap neither `vs1` nor `vs2`.
  - `EMUL_C` may be 1, 2, 4, 8 or 16 (`ime_group_size_legal`). `EMUL_C=16` occurs, for example, at `VLEN=256`, `SEW=16`, `lambda=1`; `vd` is then `v0` or `v16`. `read_single_element`/`write_single_element` accept at most 8 registers (max LMUL), so C is accessed through `read_single_element_in_group`/`write_single_element_in_group` with a limit of `IME_EMUL_C_MAX` (16, defined in `ime_types.sail`). The FP rows use the same accessors.
  - `VL=0` is a legal no-op (`N=0`).
  - `vd` shall not overlap `vs1` or `vs2` (`ime_reg_groups_disjoint`), regardless of `VL`, including `VL=0` (S:551-559). `vs1` and `vs2` may overlap each other (S:556-559).
  - Accumulation stays modulo `2^SEW`; C read/write indexing stays on `SEW` storage elements.
  - Each row is gated by the individual extension that `tbl-int-encoding-map` names for that `(W, SEW)` cell (`ime_int_row_ok`); `altfmt_A`/`altfmt_B` select signed or unsigned interpretation and do not change which extension a row needs.
  - `vmmacc.vv` (W=1): Int8/Int16/Int32/Int64. `altfmt_A=0`/`altfmt_B=0` selects signed operands; `altfmt_A=1`/`altfmt_B=1` selects unsigned operands.
  - `vwmmacc.vv` (W=2): Int4->Int8, Int8->Int16, Int16->Int32, Int32->Int64; mixed-sign combinations supported.
  - `vqmmacc.vv` (W=4): Int4->Int16, Int8->Int32 (the common `vqwmmacc`/Ozaki-style path), Int16->Int64; `SEW=8` (which would imply the reserved `EEW=2`) raises illegal instruction.
  - `v8wmmacc.vv` (W=8): Int4->Int32, Int8->Int64; `SEW=8`/`SEW=16` imply reserved EEW values and raise illegal instruction.
  - `vd` overlap, `VL` divisibility, and `vstart` legality are common to all four; `vstart` is `VSTART_MANDATORY` (any nonzero value raises illegal instruction, AMB-14), checked via `illegal_vstart(VSTART_MANDATORY, ...)` with operand A's LMUL-aligned geometry. 64-bit accumulator rows additionally require `Zve64x`, checked explicitly in `ime_int_row_ok`'s SEW=64 cells rather than through the extension's own dependency chain (AMB-15). The individual-extension bullet under "Implemented pieces" explains why.
  - `vm=0` of `vwmmacc.vv`, `vqmmacc.vv` and `v8wmmacc.vv` encodes the integer-input MX forms `vfwimmacc.vv`, `vfqimmacc.vv` and `vf8wimmacc.vv`. `execute_ime_int_mmacc` passes them to `execute_ime_int_mx` (see "Microscaling (MX) matrix multiply-accumulate").
  - `vm=0` of `vmmacc.vv` is reserved, because no MX form exists for `W=1`. It raises illegal instruction. The assembly mapping prints it with the `, v0.scale` suffix of the `vm=0` MX forms.
- Unscaled floating-point matrix multiply-accumulate (`execute_ime_fp_engine`, `vm=1`), shared by `vfmmacc.vv` (W=1, funct6 `0x14`), `vfwmmacc.vv` (W=2, funct6 `0x15`), `vfqmmacc.vv` (W=4, funct6 `0x16`), and `vf8wmmacc.vv` (W=8, funct6 `0x17`):
  - `vfmmacc.vv` (`SEW=8`): OFP8xOFP8->OFP8, every E4M3/E5M2 input pair (per operand via `altfmt_A`/`altfmt_B`) into an E4M3 (`altfmt=0`) or E5M2 (`altfmt=1`) C (`Zvvofp8mm`, S:7282-7289).
  - `vfmmacc.vv` (`SEW=16`): FP16xFP16->FP16 and BF16xBF16->BF16 are legal; FP16xFP16->BF16 and BF16xBF16->FP16 are reserved (the C format shall match the input format when both inputs match). A mixed FP16/BF16 input pair is legal into either C format and needs both `Zvvfp16mm` and `Zvvbf16mm` enabled. `SEW=32`/`SEW=64`: FP32/FP64 inputs ignore `altfmt_A`/`altfmt_B` (S:1127, S:1489-1493).
  - `vfwmmacc.vv`: OFP4 E2M1->E4M3/E5M2 (`SEW=8`, `altfmt_A=altfmt_B=0`, `altfmt` selects the C format, `Zvvofp4ofp8mm`, S:7305-7306; `altfmt_A=altfmt_B=1` is reserved), OFP8->FP16/BF16 (`SEW=16`), FP16/BF16->FP32 with the C format fixed at FP32 (`SEW=32`), FP32->FP64 with `altfmt_A`/`altfmt_B` ignored (`SEW=64`).
  - `vfqmmacc.vv`: OFP4->FP16/BF16 (`SEW=16`), OFP8->FP32 (`SEW=32`), FP16/BF16->FP64 with the C format fixed at FP64 (`SEW=64`).
  - `vf8wmmacc.vv`: OFP4 E2M1->FP32 (`SEW=32`, `altfmt_A=altfmt_B=0`), OFP8 E4M3/E5M2->FP64 (`SEW=64`, per-operand `altfmt_A/B`, mixed allowed). `SEW<32` raises illegal instruction, as does `altfmt_A/B=1` at `SEW=32`.
  - OFP8 C formats (AMB-03): the specification does not define rounding or overflow for an OFP8 accumulator, so the model follows the OCP OFP8 non-saturating conversion at `ime_fp_round`'s single rounding into C, both for the group sum and for the add into C. E5M2 rounds like an IEEE format: overflow gives ±inf or the largest finite value (57344) per the IEEE 754 rule for `frm`, with OF and NX. E4M3 has no infinity: an overflow that IEEE 754 would round to ±inf gives the E4M3 NaN `0x7f` with OF and NX, and one it would round to the largest finite value gives ±448 with OF and NX (for example 480 gives NaN under RNE and 448 under RTZ). An exact infinity (for example an E5M2 infinity input product) rounded to E4M3 gives NaN with NV. The canonical E4M3 NaN is `0x7f`; the canonical E5M2 NaN is `0x7e`.
  - OFP4/OFP8 inputs ignore `altfmt_A`/`altfmt_B` for extension selection (any E4M3/E5M2 mix is legal where OFP8 is an input); OFP4 additionally requires `altfmt_A=altfmt_B=0` (S:1441-1442). OFP8 has no signaling NaN: E4M3/E5M2 NaN encodings decode to the canonical NaN without raising NV (AMB-04).
  - Each row is gated by the individual extension(s) `tbl-fp-encoding-map` names for that `(W, SEW, altfmt_A, altfmt_B, altfmt)` combination; a mixed FP16/BF16 row needs both the FP16 and BF16 extensions for that accumulator width.
  - The geometry checks of `ime_gemm_geometry` and the register-group checks of `ime_gemm_groups_ok` are the same helpers the integer path calls. As on the integer path, `vstart` must be zero (`VSTART_MANDATORY`). `frm` must not hold 5, 6 or 7 (`valid_fp_op`); the unscaled integer path does not read `frm`.
  - `Zvvfmm` requires `Zve32f`, which requires `Ext_F`, so the floating-point IME instructions are subject to the `mstatus.FS` check. FP64-accumulator rows additionally require `Zve64d`, checked explicitly in `ime_fp_base_row_ok`'s SEW=64 cells (AMB-15). The individual-extension bullet under "Implemented pieces" explains why.
  - As on the integer path, `vm=0` of `vfmmacc.vv` is reserved: it prints with the `, v0.scale` suffix and raises illegal instruction. `vm=0` of the other three forms encodes their MX forms (see "Microscaling (MX) matrix multiply-accumulate").
  - Runs on the exact engine described in "Microscaling (MX) matrix multiply-accumulate" with the disclosed profile `G=1`, `psm=0`, `rnd=frm`, and accrues `fflags` once per active C element, even when the accrued value is zero (base-V convention: `fflags_dirty_policy` relies on one `accrue_fflags` call per element to mark `mstatus.FS`/`SD` dirty, independent of the flags it carries).

## Known gaps

- The disclosed FP group profile is fixed at `G=1`, `psm=0` (exact partial sums), `rnd=frm`; no other disclosure profile is implemented.
- C tile tail elements of the multiply-accumulate instructions are always left undisturbed; the model never reads `vta` in the GEMM paths. The specification permits this: `vta=0` requires it, and `vta=1` permits (but does not require) retaining the pre-instruction value instead of writing an all-ones `SEW`-bit pattern (S:2962-2984). The model never exercises the all-ones alternative `vta=1` also allows. This is unrelated to tile load/store, where the specification itself says the `vta`/`vma` fill policies do not apply and inactive/tail destination elements are always undisturbed (S:2682, S:2804) — the model already matches that mandatory behavior.
- The first-party test matrix targets RV64 with `VLEN=256` only; other `VLEN`/`XLEN` combinations are untested.

## Targeted tests

The IME tests live under `test/first_party/src/`, registered with `add_ime_test(...)` in `test/first_party/CMakeLists.txt`; that file is the current list of test sources, march/xlen, and config-override JSON, and grows as rows are added, so it is the source of truth rather than any count given here.

- `test_ime_tile_ls.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, and `LD=4`.
  - Checks `vmtl.v` loads offsets `[0,1,4,5]` and `vmts.v` stores only those offsets.
- `test_ime_tile_ls_lmul.S`
  - Configures `SEW=32`, `LMUL=2`, `VL=16`, `VLEN=256`.
  - Checks the `tile_reg_idx` register layout for `vmtl.v`/`vmts.v` (`lambda=1`, `LD=2`, plus a masked load) and for all four tile loads/stores at `lambda=2`, `LD=4`.
- `test_ime_transpose_tile_ls.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, `VLEN=256`.
  - Subcase 1 checks `vmttl.v`/`vmtts.v` with explicit `LD=4` use transposed offsets `[0,4,1,5]` and leave non-addressed `dst` slots untouched.
  - Subcase 2 checks `rs2=x0` natural `LD = VLEN / (SEW * lambda) = 4` (not the ordered `lambda * LMUL = 2`).
- `test_ime_tile_ls_vl.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `LD=2`, `VLEN=256`.
  - Checks `VL` values that are and are not multiples of `lambda * LMUL` trap accordingly, and `VL=0` does not trap.
- `test_ime_tile_ls_v0.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=1`, `VL=4`, `LD=4`, `VLEN=256`.
  - Checks masked `vmtl.v`/`vmttl.v` into `v0` trap; masked `vmtl.v` into `v8` and masked `vmts.v`/`vmtts.v` from `v0` do not.
- `test_ime_tile_ls_ld0.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=8`, `VLEN=256`, `rs2=a1` holding 0.
  - Checks all four tile loads/stores use the natural `LD` (2 order-preserving, 4 transposing).
- `test_ime_vtype_lambda.S`
  - Configures `VLEN=256`.
  - Checks the lambda write rules: a `vsetvl` request outside the permissible set clamps to the largest supported value at most the request (`e16` lambda=8 request reads back 4; `e32` lambda=8 request reads back 2), and a following `vsetvli` (lambda field forced to `000`) retains the current lambda when it is still supported for the new SEW.
- `test_ime_vtype_altfmt.S`
  - Checks `altfmt` (bit 8) via `vsetvli`, `vsetivli`, and `vsetvl`, and that `zimm[9]` stays reserved.
- `test_ime_vmmacc.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, `VLEN=256`.
  - Checks a signed 4x2 by 2x2 non-widening GEMM and verifies inactive C tile columns remain untouched.
- `test_ime_vwmmacc.S`
  - Exercises all four W=2 widening rows at `VLEN=256`, `LMUL=1`:
    - Row A Int16->Int32 (`SEW=32`, `lambda=2`, `VL=4`), signed/signed, plus a tail-stays-zero check.
    - Row B Int8->Int16 (`SEW=16`, `lambda=4`, `VL=4`), mixed-sign (`altfmt_A=0` signed, `altfmt_B=1` unsigned with a packed 200).
    - Row C Int32->Int64 (`SEW=64`, `lambda=2`, `VL=4`), unsigned/unsigned with a packed `0x80000001` to exercise the unsigned high bit.
    - Row D Int4->Int8 (`SEW=8`, `lambda=4`, `VL=4`), signed/signed, exercising packed 4-bit nibble lanes.
  - Expected C constants are produced by a scalar reference mirroring the `int_gemm` helper.
- `test_ime_vqmmacc.S`
  - Exercises the three valid W=4 widening rows at `VLEN=256`, `lambda=2`, `LMUL=1`:
    - Row A Int8->Int32 (`SEW=32`, `VL=4`), signed/signed, the priority `vqwmmacc`/Ozaki-style path, plus a tail-stays-zero check.
    - Row B Int8->Int32 (`SEW=32`, `VL=4`), unsigned/signed (`altfmt_A=1`, `altfmt_B=0`) with a packed unsigned 200 (`0xC8`).
    - Row C Int4->Int16 (`SEW=16`, `VL=2`), unsigned/unsigned (`altfmt_A=altfmt_B=1`), exercising packed 4-bit nibble lanes including values `>= 8`.
    - Row D Int16->Int64 (`SEW=64`, `VL=4`), signed/unsigned (`altfmt_A=0`, `altfmt_B=1`) with a packed unsigned 32769 (`0x8001`).
  - Together the rows cover all four signedness combinations; expected C constants come from the same scalar reference mirroring the `int_gemm` helper.
- `test_ime_v8wmmacc.S`
  - Exercises the two valid W=8 widening rows at `VLEN=256`:
    - Rows A/B cover Int4->Int32 (`SEW=32`) signed/signed and unsigned/signed paths.
    - Rows C/D cover Int8->Int64 (`SEW=64`) signed/signed and signed/unsigned paths, with Row D using `LMUL=2`.
  - Expected C constants come from a scalar reference mirroring the `int_gemm` helper.
- `test_ime_vfmmacc.S`
  - Exercises the unscaled FP rows at `VLEN=256`, using `.word` encodings for `vfmmacc.vv`, `vfwmmacc.vv`, and `vfqmmacc.vv`.
  - Covers same-width FP16/FP32/FP64, `vfwmmacc` FP16->FP32, BF16->FP32, FP32->FP64, and `vfqmmacc` FP16/BF16->FP64 with exact values.
  - Includes the FP32 inactive-column sentinel case that verifies inactive sNaNs do not update C or accrue `fflags`.
- `test_ime_vf8wmmacc.S`
  - `vf8wmmacc.vv v16, v8, v12`, `VLEN=256`, `lambda=2`.
  - E2M1->FP32 (`LMUL=1`, inactive C sentinels), E4M3xE4M3->FP64 (max normal, subnormal), E4M3xE5M2->FP64 with `LMUL=2` (E5M2 max and subnormal), and E5M2xE4M3 special values (`inf*0` -> NaN + NV, OFP8 NaN -> canonical NaN without flags).
  - Illegal: `vm=0`, `SEW=16`, `SEW=32` with `altfmt_A=1`, `vstart!=0`.
- `test_ime_emul_c16.S`
  - `VLEN=256`, `SEW=16`, `LMUL=1`, `lambda=1`: `M=16`, `EMUL_C=16`, C in `v16`-`v31`, column `j` in `v16 + j`.
  - `vmmacc.vv` and FP16 `vfmmacc.vv` with `VL=16` check all 256 C elements. `VL=0` does not trap, and `vmmacc.vv` leaves C unchanged. `vd=v8` raises illegal instruction.
- `test_ime_fs_off.S`
  - Forces `mstatus.FS=Off` after `crt0` sets it, at `SEW=32`, `lambda=2`, `LMUL=1`.
  - `vfmmacc.vv` raises illegal instruction (`Zvvfmm` requires `Zve32f`, hence `Ext_F`'s `mstatus.FS` check); `vmmacc.vv` still executes (`Zvvmm` requires only `Zve32x`, which has no `Ext_F`/FS dependency).
- `test_ime_vtype_reset.S`
  - Reads `vtype` before any `vset*` instruction has run, after setting `mstatus.VS` so that the CSR is accessible.
  - Checks `vill=1` and that `vlambda`, `vbs`, `altfmt_A`, and `altfmt_B` read 0 (S:865-867).
  - Limitation: the Sail C emulator starts with all registers at zero, and `reset_sys` runs once before the test. The test therefore also passes without the explicit clearing of these fields in `reset_sys`. It checks the reset state, not that `reset_sys` produces it.
- `test_ime_vl0_vs_dirty.S` (with `ime_mx_override.json`)
  - Runs `vfmmacc.vv` (`SEW=32`, `lambda=2`, `LMUL=1`) and `vfwimmacc.vv` (`SEW=16`, `lambda=4`, `LMUL=8`) at `VL=0`.
  - Sets `mstatus.VS` to Clean after each `vsetvl`, immediately before the instruction under test.
  - Checks that `mstatus.VS` reads Dirty afterward. At `VL=0` no C element is written, so the only write to `mstatus.VS` is the `dirty_v_context()` call inside `set_vstart(zeros())`.
- `test_ime_vmmacc_vstart.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, `VLEN=256`.
  - Checks that `vmmacc.vv` and `vwmmacc.vv` with `vstart=1` raise illegal instruction and leave `vstart` at 1.
- `test/first_party/src/ime_override.json`
  - Enables `Zvvmm`, `Zvvmtls`, `Zvvmttls`, and `Zvvfmm` for the targeted first-party tests; by implication, this also enables every individual computational extension whose own dependency the default config satisfies.
- `model/unit_tests/test_ime_vtype.sail`
  - Covers lambda encoding helpers, lambda WARL selection, and the addressability of the new high `vtype` fields.
- `model/unit_tests/test_ime_gemm.sail`
  - `ime_gemm_geometry` and `vd` alignment at `EMUL_C=16`.
  - `read_single_element_in_group`/`write_single_element_in_group` with a 16-register limit reach `v24` and `v31` from `vd=v16`.
  - `execute_ime_int_gemm` and `ime_fp_gemm` across the full 16-register C group, and `execute_ime_int_gemm` with `VL=0` leaving C unchanged.
- `model/unit_tests/test_ime_asm.sail`
  - Checks `vmmacc.vv`/`vfmmacc.vv` assembly for `vm=1` and for the reserved `vm=0` encoding, which prints the `, v0.scale` suffix.

The microscaling-specific tests (`test_ime_mx_*.S`, `test_ime_fp_rows.S`, generated by `ime_mx_gen.py`) are described in "Microscaling (MX) matrix multiply-accumulate".

## How to run the targeted IME checks

The IME test targets follow the naming `build_${arch}_${test_source}` and `first_party_${arch}_${test_source}`, one pair per `add_ime_test(...)` entry in `test/first_party/CMakeLists.txt`; `${arch}` is `rv64d` for every current entry. From a configured build directory:

```sh
cmake --build build -j$(nproc)
ctest --test-dir build -R 'first_party_rv64d_test_ime_' --output-on-failure
```

This assumes `FIRST_PARTY_TESTS` was enabled at configure time and the RISC-V cross-compiler prerequisites (Clang or GCC) are on `PATH`. The simulator runs each IME test with:

```text
--enable-experimental-extensions --config build/config/rv64d_v256_e64.json --config-override test/first_party/src/<the test's own override JSON>
```

## Microscaling (MX) matrix multiply-accumulate

Implements the spec's `fp_gemm`, `fp_scaled_gemm`, `int_scaled_gemm`, and `read_block_scales` pseudocode for the MX rows and the base rows they imply.

```
ime_mem_insts.sail  execute_ime_fp_mmacc / execute_ime_int_mmacc (dispatch)
        |  every FP row; integer vm=0 rows
        v
ime_mx.sail         geometry, encoding-map legality, fp_gemm / scaled GEMMs
        |
        v
ime_fp.sail         exact values (unbounded ints) + IEEE rounding with RISC-V flags
```

- Engine (`ime_fp.sail`): decodes E2M1, E4M3, E5M2, FP16, BF16, FP32, and FP64 to an exact value; exact multiply/add; correctly rounded conversion to E4M3/E5M2/FP16/BF16/FP32/FP64 under `frm` with `NX/UF/OF/NV` (tininess after rounding; OFP8 overflow follows the OCP OFP8 non-saturating conversion described under "Unscaled floating-point matrix multiply-accumulate", AMB-03). `model/unit_tests/test_ime_fp.sail` cross-checks engine add/mul against SoftFloat (3000 FP16/FP32/FP64 cases, all five rounding modes, bits and flags); `test_ime_fp_round_ofp8` checks the OFP8 overflow, tie, infinite-input, and subnormal-boundary cases by hand.
- Disclosure for every FP row (`vm=1` and `vm=0`): `G=1`, `psm=0`, `rnd=frm`. Per group, the `W` products are summed exactly (the sum seeds from the first product rather than a literal `+0`, so a single-term group keeps that product's sign exactly, including `-0`, matching the IEEE 754 sum-of-zeros rule for multi-term groups too, AMB-02). For `vm=0`, the combined E8M0 exponent `eA + eB - 254` is applied exactly to the unrounded group sum; neither scale nor their product is converted to the C format, and reading and combining the scales raises no flags (S:2010-2023, S:2100-2109, `combine_scale_exponents`/`fp_internal_scale`, AMB-01). The scaled or unscaled group sum is rounded once to the C format, then added into C, rounded once more. Either E8M0 value being `0xFF` makes C[i,j] the canonical NaN and ends that element's evaluation; later blocks are skipped. Integer MX: the exact block dot product is scaled exactly by the combined exponent, rounded once to the C format, and added to C (S:1283-1292).
- Rows, all with `vm=0` at BS=32 (`bs=0`) and BS=16 (`bs=1`):
  - `vfwmmacc.vv` `SEW=8`: E2M1 -> E4M3/E5M2 (`Zvvxofp4ofp8mm`/`Zvvxnofp4ofp8mm`); also `vm=1`. BS=16 limits LMUL to 4 (`W*LMUL<=SEW`).
  - `vfwmmacc.vv` `SEW=16`: OFP8 (all E4M3/E5M2 A/B pairs) -> FP16/BF16; also `vm=1`.
  - `vfqmmacc.vv` `SEW=16`: E2M1 -> FP16/BF16; `SEW=32`: OFP8 -> FP32; also `vm=1`.
  - `vf8wmmacc.vv` `SEW=32`: E2M1 -> FP32; `SEW=64`: OFP8 -> FP64; also `vm=1`.
  - The unscaled rows (`vfmmacc` FP16/FP32/FP64, `vfwmmacc` FP16/BF16->FP32 and FP32->FP64, `vfqmmacc` FP16/BF16->FP64) use the same engine.
  - `vfwimmacc.vv` `SEW=16`: MXINT8 -> FP16/BF16. `vfqimmacc.vv` `SEW=16`: MXINT4 -> FP16/BF16; `SEW=32`: MXINT8 -> FP32. `vf8wimmacc.vv` `SEW=32`: MXINT4 -> FP32; `SEW=64`: MXINT8 -> FP64.
- Legality, checked by `execute_ime_fp_engine` for every floating-point-input row and by `execute_ime_int_mx` for the integer-input `vm=0` rows:
  - `valid_vtype()` holds, `vstart` is zero (`VSTART_MANDATORY`), and `frm` does not hold 5, 6 or 7 (`valid_fp_op`).
  - `ime_gemm_geometry(W)` accepts the geometry. These are the same checks as on the integer path (see "Generalized integer GEMM executor"), with `EMUL_C` up to 16.
  - The encoding-map cell names an enabled extension: `ime_fp_base_row_ok` for `vm=1`, and `ime_fp_mx_row_ok` or `ime_int_mx_row_ok` for `vm=0`. `ime_int_mx_row_ok` also requires `altfmt_A=altfmt_B=0`, because MXINT inputs are signed.
  - For `vm=0` only, `ime_mx_operands_ok` requires `SEW*lambda >= 16`, requires `W*LMUL <= SEW` with BS=16, and rejects `v0` as the base register of `vs1`, `vs2` or `vd`. Register groups are aligned, so no operand group can overlap `v0`.
  - `ime_gemm_groups_ok` accepts the register groups, as on the integer path.
- Extension gating: a `vm=0` cell needs its `Zvvx*` (BS=32; also satisfied by `Zvvxn*`) or `Zvvxn*` (BS=16). A `vm=1` engine row needs the individual extension(s) `tbl-fp-encoding-map`/`tbl-int-encoding-map` name for that cell, or an MX extension that implies it. The FP MMA opcodes decode when `Zvvfmm`, any individual floating-point computational extension (`ime_fp_base_any_enabled`), or any FP MX extension is enabled; the integer ones when `Zvvmm`, any individual integer computational extension (`ime_int_base_any_enabled`), or any integer MX extension is enabled. The per-cell check named above still rejects the decoded instruction in execute when the enabled extension does not cover that `(W, SEW)` cell.
- `ime_mx_gen.py` generates the ten `test/first_party/src/test_ime_mx_*.S` tests and `test_ime_fp_rows.S`. It is an independent Python reference of the specification pseudocode that computes with exact `fractions.Fraction` arithmetic. At startup, `self_check()` compares its round-to-nearest-even rounding to FP16, FP32 and FP64 with the conversions of Python's `struct` module, and its OFP8 rounding to hand-computed cases. Rerun it after changing data or cases: `python3 test/first_party/src/ime_mx_gen.py`. CI regenerates the eleven files and fails when they differ from the committed copies.
  - `vfwmmacc`, `vfqmmacc`, `vf8wmmacc`, `vfwimmacc`, `vfqimmacc`, `vf8wimmacc`: every format combination listed above, `vm=1` for `vfwmmacc` and `vfqmmacc`, both block sizes, all five rounding modes, `K_eff=64` (2 or 4 blocks), one sNaN tail column.
  - `special`: 17 cases, including NaN scale with early termination (a later block would overflow), large and tiny scaled sums leaving the C range (one under round-up to the minimum subnormal instead of to `+0`, one under round-towards-zero to the maximum finite value instead of to infinity), `inf*0`, BF16 overflow of a scaled sum, a partial block (`K_eff=16`), NaN B scale, a `2^-127 * 2^127` scale pair that combines to exponent 0 with no flags, an integer dot product that overflows the C format, two `exact-scale` cases where rounding the group sum before scaling would tie the other way (FP32 and integer), the spec's `2^-15 * 2^-15 * 2^10 = 2^-20` FP16 example (S:2025-2029), and a `-0` group sum from a single-term (`W=1`) group whose one product is exactly `-0`.
  - `illegal`: reserved rows, BS=16 `W*LMUL>SEW`, `v0` overlap, `vstart!=0`, bad `VL`, `frm=5`, `vmmacc`/`vfmmacc` `vm=0`, the reserved `vfwmmacc` SEW=8 row with `altfmt_A=altfmt_B=1`.
  - `ofp8` (`test_ime_mx_ofp8.S`, with `ime_mx_override.json`): every `vfmmacc` SEW=8 format row, `vfwmmacc` E2M1->E4M3/E5M2 unscaled and at both block sizes, E5M2 overflow to ±inf (RNE, RUP, RDN) and to the largest finite value (RTZ), E4M3 overflow to NaN (RNE, RMM) and to 448 (RTZ), an exact infinity rounded to E4M3, a combined E8M0 exponent of 2^9 applied to the unrounded group sum overflowing E4M3 at its single rounding (NaN under RNE, 448 under RTZ), the reserved OFP4 rows, the BS=16 LMUL limit, and `vfmmacc` `vm=0`.
  - `gate` (with `ime_mx_gate_override.json`): BS=32/BS=16 cells, implied base rows, `vfwmmacc` SEW=8 through `Zvvxnofp4ofp8mm` and the extensions it implies, `vfmmacc` SEW=8 trapping without `Zvvofp8mm`, an integer row and a floating-point row each enabled through their own individual extension alone (no family flag), and a mixed FP16/BF16 row that traps when only one of the two needed extensions is enabled.
  - `test_ime_vtype_altfmt.S`: `altfmt` via `vsetvli`/`vsetivli`/`vsetvl`.
  - `test_ime_fp_rows.S` (with `ime_override.json`): the unscaled rows, random data in all rounding modes, plus a `group-tie` case per `W>1` row where rounding each product into C separately would give a different result.
- `ime_mx_override.json` enables all IME and MX extensions. `ime_override.json` enables no MX extension, so the `vm=0` encodings that `test_ime_vf8wmmacc.S` expects to trap raise illegal instruction.

## Open work

1. The only implemented disclosure profile is `G=1`, `psm=0`, `rnd=frm`. A different profile and its tests are needed only if the architecture requires one.
2. The tests cover only RV64 with `VLEN=256`. Other `VLEN` values, RV32, and other `XLEN`/`ELEN` combinations are untested.
3. The multiply-accumulate paths never write the all-ones tail pattern that `vta=1` permits. They always leave tail elements undisturbed.
4. Masked, tail, and trap/restart behavior is tested only for the lambda, LMUL and SEW combinations of the targeted tests above.
