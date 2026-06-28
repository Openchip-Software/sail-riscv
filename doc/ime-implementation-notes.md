# Integrated Matrix Extension (IME / Zvvm) implementation notes

This is the status note for the initial Sail implementation loop for the draft RISC-V Integrated Matrix Extension. It documents what is implemented in this tree, how it is tested, and the known limitations that should guide the next development loop.

## Implemented pieces

- Draft extension plumbing:
  - `Ext_Zvvmm` for integer matrix multiply-accumulate.
  - `Ext_Zvvmtls` for order-preserving tile load/store.
  - `Ext_Zvvmttls` for transposing tile load/store.
  - `Ext_Zvvfmm` gates the staged unscaled floating-point matrix multiply-accumulate rows implemented so far.
- IME `vtype` high fields:
  - `vlambda` in bits `XLEN-2:XLEN-4`.
  - `vbs` in bit `XLEN-5`.
  - `altfmt_A` in bit `XLEN-6`.
  - `altfmt_B` in bit `XLEN-7`.
- Lambda helper behavior:
  - Encodings map as `001=1`, `010=2`, `011=4`, `100=8`, `101=16`, `110=32`, `111=64`.
  - `000` is treated as dynamic/preserve where appropriate and selects the largest supported legal lambda when a concrete vtype is written.
- Vector configuration interaction:
  - `vsetvli`/`vsetivli` preserve the existing IME fields while updating the standard vector fields.
  - `vsetvl` accepts the full `vtype` value, including IME fields, and applies the lambda WARL selection helper.
- Order-preserving tile load/store:
  - `vmtl.v` and `vmts.v` decode for `Zvvmtls`.
  - Implemented for the standard vector element widths handled by the vector model (`SEW=8,16,32,64`).
  - Uses the order-preserving memory address formula in `ime_tile_ordered_mem_off`: `linesize = lambda * LMUL`, `mem_off = (i / linesize) * LD + (i % linesize)`.
  - `rs2=x0` selects the natural leading dimension `LD = lambda * LMUL`.
- Transposing tile load/store:
  - `vmttl.v` and `vmtts.v` decode for `Zvvmttls`. Decode is mode-gated: order-preserving mode (`mode=00`) requires `Zvvmtls`; transposing mode (`mode=01`) requires `Zvvmttls`. Neither mode requires both extensions.
  - Implemented for `SEW=8,16,32,64`, sharing the same mask, tail, prestart, `vstart`, and memory-exception behavior as `vmtl.v`/`vmts.v`.
  - The active storage-element tile shape is `cols = lambda * LMUL` columns by `rows = VL / cols` rows.
  - Uses the transposing memory address formula in `ime_tile_transposed_mem_off`: `mem_off = (i % cols) * LD + (i / cols)`. For a 2x2 tile with `LD=4` this yields offsets `[0,4,1,5]`, versus `[0,1,4,5]` for the order-preserving traversal.
  - `rs2=x0` selects the natural leading dimension `LD = VLEN / (SEW * lambda)`.
  - Transposing transposes `SEW`-bit storage elements only; it does not unpack, transpose, or repack `W>1` logical elements that may be packed inside a `SEW`-bit storage element.
  - Inactive/tail destination elements for `vmttl.v` remain undisturbed; inactive/tail elements for `vmtts.v` do not write memory or fault.
- Basic non-widening integer matrix multiply-accumulate:
  - `vmmacc.vv` decodes for `Zvvmm`.
  - Implemented for W=1, `SEW=8,16,32,64`, integer LMUL `1,2,4,8` where the derived accumulator group is legal.
  - `altfmt_A=0`/`altfmt_B=0` select signed operands; `altfmt_A=1`/`altfmt_B=1` select unsigned operands.
  - Accumulation is written back modulo the destination SEW.
- Generalized integer GEMM executor (`execute_ime_int_gemm`):
  - `vmmacc.vv` now dispatches through this shared executor with widening factor `W=1`; the W=1 result is byte-for-byte identical to the previous dedicated path.
  - Takes a `widening_factor W` argument and uses the specification-shaped geometry: `K_eff = lambda * W * LMUL`, `storage_K = lambda * LMUL`, `M = VLEN / (SEW * lambda)`, `N = VL / storage_K`, `N_max = M`, `EMUL_C = VLEN / (SEW * lambda^2)` based on the C accumulator SEW.
  - The physical storage geometry is the same for all `W`: each matrix row holds `storage_K = lambda * LMUL` `SEW`-bit storage elements along K, addressed via `mat_A_idx`/`mat_B_idx`/`mat_C_idx` (built on `tile_reg_idx`).
  - For `W>1` each `SEW`-bit storage element packs `W` logical input elements of width `EEW = SEW / W`. Logical index `k` maps to storage column `k / W` and lane `k % W` (`ime_packed_storage_col`/`ime_packed_lane`); `ime_packed_subelement_value` extracts the lane in little-endian lane order and sign- or zero-extends it per `altfmt_A/B`. Element `k` occupies bits `[k*EEW + EEW-1 : k*EEW]`, including the sub-byte Int4 (`EEW=4`) nibble packing (even element = lower nibble, odd element = upper nibble).
  - Legality checks: `W in {1,2,4,8}`, `SEW % W == 0`, `EEW = SEW/W` a supported integer logical width (`{4,8,16,32,64}`), and `VL % K_eff == 0`, in addition to the existing `M`/`N`/`N_max`/`EMUL_C`/register-group checks.
  - Accumulation stays modulo `2^SEW`; C read/write indexing stays on `SEW` storage elements.
  - `vwmmacc.vv` (W=2), `vqmmacc.vv` (W=4), and `v8wmmacc.vv` (W=8) are now enabled and dispatch through this executor.
- Double-widening integer matrix multiply-accumulate (`vwmmacc.vv`, W=2):
  - Decodes for `Zvvmm` at funct6 `0x39`, OPIVV, `vm=1`. `vm=0` is the reserved `vfwimmacc.vv` microscaled form and raises illegal instruction.
  - Shares `execute_ime_int_mmacc(W, ...)` with `vmmacc.vv`; only the widening factor differs (`W=1` vs `W=2`).
  - Supported W=2 rows (all representable with the current packed-subelement helper, including the sub-byte nibble Int4 row): Int4→Int8 (`SEW=8`), Int8→Int16 (`SEW=16`), Int16→Int32 (`SEW=32`), Int32→Int64 (`SEW=64`). Each `SEW`-bit storage element packs two `SEW/2`-bit logical inputs.
  - Signedness per operand follows `altfmt_A`/`altfmt_B` (0=signed, 1=unsigned); mixed-sign combinations are supported.
- Quad-widening integer matrix multiply-accumulate (`vqmmacc.vv`, W=4):
  - Decodes for `Zvvmm` at funct6 `0x3a`, OPIVV, `vm=1`. `vm=0` is the reserved `vfqmmacc.vv` microscaled form and raises illegal instruction.
  - Shares `execute_ime_int_mmacc(W, ...)` with `vmmacc.vv`/`vwmmacc.vv`; only the widening factor differs (`W=4`).
  - Supported W=4 rows: Int4→Int16 (`SEW=16`), Int8→Int32 (`SEW=32`, the common `vqwmmacc`/Ozaki-style path), and Int16→Int64 (`SEW=64`). Each `SEW`-bit storage element packs four `SEW/4`-bit logical inputs. `SEW=8` (which would imply the reserved `EEW=2`) raises illegal instruction via the `ime_int_eew_supported` check, matching the spec. The Int4→Int16 row uses the same packed-nibble helper as the W=2 Int4 row, so it is fully implemented and tested with no Int4 limitation.
  - Signedness per operand follows `altfmt_A`/`altfmt_B` (0=signed, 1=unsigned); all four combinations (signed/signed, unsigned/signed, unsigned/unsigned, signed/unsigned) are covered by the tests.
- Octuple-widening integer matrix multiply-accumulate (`v8wmmacc.vv`, W=8):
  - Decodes for `Zvvmm` at funct6 `0x3b`, OPIVV, `vm=1`. `vm=0` is the reserved `vf8wimmacc.vv` microscaled form and raises illegal instruction.
  - Shares `execute_ime_int_mmacc(W, ...)` with the other unscaled integer GEMM instructions; only the widening factor differs (`W=8`).
  - Supported W=8 rows: Int4→Int32 (`SEW=32`) and Int8→Int64 (`SEW=64`). `SEW=8`/`SEW=16` imply reserved EEW values and raise illegal instruction via the shared EEW legality check.
  - The targeted tests cover signed and mixed-sign paths, including an `LMUL=2` case to exercise `K_eff = lambda * W * LMUL` with `storage_K = lambda * LMUL`.
- Staged unscaled floating-point matrix multiply-accumulate:
  - `vfmmacc.vv` (W=1) decodes for `Zvvfmm` at funct6 `0x14`, OPFVV, `vm=1`; `vm=0` remains the reserved microscaled form and raises illegal instruction.
  - Same-width default IEEE rows are implemented for FP16, FP32, and FP64.
  - `vfwmmacc.vv` (W=2, funct6 `0x15`) is implemented for FP16/BF16→FP32 and FP32→FP64; BF16 inputs are selected per operand with `altfmt_A/B=1`.
  - `vfqmmacc.vv` (W=4, funct6 `0x16`) is implemented for FP16/BF16→FP64.
  - Implemented rows use the disclosed unscaled profile `G=1`, `psm=0`, `rnd=frm`; products and accumulation use existing SoftFloat helpers and accrue active-lane `fflags`.

## Targeted tests

The initial IME tests live under `test/first_party/src/`:

- `test_ime_tile_ls.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, and `LD=4`.
  - Checks `vmtl.v` loads offsets `[0,1,4,5]` and `vmts.v` stores only those offsets.
- `test_ime_transpose_tile_ls.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, `VLEN=256`.
  - Subcase 1 checks `vmttl.v`/`vmtts.v` with explicit `LD=4` use transposed offsets `[0,4,1,5]` and leave non-addressed `dst` slots untouched.
  - Subcase 2 checks `rs2=x0` natural `LD = VLEN / (SEW * lambda) = 4` (not the ordered `lambda * LMUL = 2`).
- `test_ime_vmmacc.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, `VLEN=256`.
  - Checks a signed 4x2 by 2x2 non-widening GEMM and verifies inactive C tile columns remain untouched.
- `test_ime_vwmmacc.S`
  - Exercises all four W=2 widening rows at `VLEN=256`, `LMUL=1`:
    - Row A Int16→Int32 (`SEW=32`, `lambda=2`, `VL=4`), signed/signed, plus a tail-stays-zero check.
    - Row B Int8→Int16 (`SEW=16`, `lambda=4`, `VL=4`), mixed-sign (`altfmt_A=0` signed, `altfmt_B=1` unsigned with a packed 200).
    - Row C Int32→Int64 (`SEW=64`, `lambda=2`, `VL=4`), unsigned/unsigned with a packed `0x80000001` to exercise the unsigned high bit.
    - Row D Int4→Int8 (`SEW=8`, `lambda=4`, `VL=4`), signed/signed, exercising packed 4-bit nibble lanes.
  - Expected C constants are produced by a scalar reference mirroring the `int_gemm` helper.
- `test_ime_vqmmacc.S`
  - Exercises the three valid W=4 widening rows at `VLEN=256`, `lambda=2`, `LMUL=1`, encoded as `.word 0xeac40857` (`vqmmacc.vv v16, v8, v12`):
    - Row A Int8→Int32 (`SEW=32`, `VL=4`), signed/signed, the priority `vqwmmacc`/Ozaki-style path, plus a tail-stays-zero check.
    - Row B Int8→Int32 (`SEW=32`, `VL=4`), unsigned/signed (`altfmt_A=1`, `altfmt_B=0`) with a packed unsigned 200 (`0xC8`).
    - Row C Int4→Int16 (`SEW=16`, `VL=2`), unsigned/unsigned (`altfmt_A=altfmt_B=1`), exercising packed 4-bit nibble lanes including values `>= 8`.
    - Row D Int16→Int64 (`SEW=64`, `VL=4`), signed/unsigned (`altfmt_A=0`, `altfmt_B=1`) with a packed unsigned 32769 (`0x8001`).
  - Together the rows cover all four signedness combinations; expected C constants come from the same scalar reference mirroring the `int_gemm` helper.
- `test_ime_v8wmmacc.S`
  - Exercises the two valid W=8 widening rows at `VLEN=256`, encoded as `.word 0xeec40857` (`v8wmmacc.vv v16, v8, v12`):
    - Rows A/B cover Int4→Int32 (`SEW=32`) signed/signed and unsigned/signed paths.
    - Rows C/D cover Int8→Int64 (`SEW=64`) signed/signed and signed/unsigned paths, with Row D using `LMUL=2`.
  - Expected C constants come from a scalar reference mirroring the `int_gemm` helper.
- `test_ime_vfmmacc.S`
  - Exercises the staged unscaled FP rows at `VLEN=256`, using `.word` encodings for `vfmmacc.vv`, `vfwmmacc.vv`, and `vfqmmacc.vv`.
  - Covers same-width FP16/FP32/FP64, `vfwmmacc` FP16→FP32, BF16→FP32, FP32→FP64, and `vfqmmacc` FP16/BF16→FP64 with exact values.
  - Includes the FP32 inactive-column sentinel case that verifies inactive sNaNs do not update C or accrue `fflags`.
- `test/first_party/src/ime_override.json`
  - Enables `Zvvmm`, `Zvvmtls`, `Zvvmttls`, and `Zvvfmm` for the targeted first-party tests.
- `model/unit_tests/test_ime_vtype.sail`
  - Covers lambda encoding helpers, lambda WARL selection, and the addressability of the new high `vtype` fields.

## How to run the targeted IME checks

From the repository root:

```sh
cmake --build build --target generated_sail_riscv_model sail_riscv_sim build_rv64d_test_ime_v8wmmacc.S build_rv64d_test_ime_vqmmacc.S build_rv64d_test_ime_vwmmacc.S build_rv64d_test_ime_vfmmacc.S build_rv64d_test_ime_transpose_tile_ls.S build_rv64d_test_ime_tile_ls.S build_rv64d_test_ime_vmmacc.S -j$(nproc)
ctest --test-dir build -R 'first_party_rv64d_test_ime_(v8wmmacc|vqmmacc|vwmmacc|vfmmacc|transpose_tile_ls|tile_ls|vmmacc)\.S' --output-on-failure -V
```

These commands assume the build directory has already been configured and that the local Sail and RISC-V first-party test toolchain prerequisites are available. The simulator runs the IME tests with:

```text
--enable-experimental-extensions --config build/config/rv64d_v256_e64.json --config-override test/first_party/src/ime_override.json
```

Latest targeted verification in this workspace completed with all seven IME tests passing:

```text
100% tests passed, 0 tests failed out of 7
```

## Known limitations and shortcuts

- Both the order-preserving and transposing tile load/store modes are implemented; the remaining reserved tile modes (`10`, `11`) decode to illegal instruction. Transposing only transposes `SEW`-bit storage elements and is exercised for `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`; broader lambda/LMUL/SEW coverage is not yet tested.
- The `vmmacc.vv` (W=1), `vwmmacc.vv` (W=2), `vqmmacc.vv` (W=4), and `v8wmmacc.vv` (W=8) integer instruction encodings are enabled. The unscaled floating-point matrix loop now covers same-width `vfmmacc.vv` for FP16/FP32/FP64, `vfwmmacc.vv` for FP16/BF16→FP32 and FP32→FP64, and `vfqmmacc.vv` for FP16/BF16→FP64. Microscaling behavior remains out of scope. No Int4 limitation: the packed-subelement helper represents 4-bit nibble lanes, so the Int4 rows for W=2, W=4, and W=8 are implemented and tested.
- `vmmacc.vv`, `vwmmacc.vv`, `vqmmacc.vv`, and `v8wmmacc.vv` require `vm=1` and `vstart=0` as in the draft restriction used for this loop; masked matrix multiply is not implemented, and the `vm=0` microscaled forms (`vfwimmacc.vv`, `vfqmmacc.vv`, `vf8wimmacc.vv`, etc.) raise illegal instruction.
- Integer row/subextension legality is simplified: enabling `Zvvmm` enables the initial non-widening integer rows implemented here instead of modeling each fine-grained row as a separate configuration flag.
- C tile-tail columns are left undisturbed by the integer GEMM implementation; this matches the targeted tests and should be revisited if the final spec requires tail-agnostic updates for inactive physical columns.
- The first-party tests use `.word` instruction encodings for the new IME instructions so they do not depend on external assembler mnemonic support.
- The implementation is still a targeted first loop, not a full conformance suite for all legal lambdas, LMULs, element widths, masking, traps, and exception restart behavior.


## Floating-point vmmacc loop

The current implementation adds unscaled floating-point matrix multiply-accumulate in the same staged style as the integer work. It follows the draft spec's Sail-like starting point for `fp_gemm`, but remains narrower than the full draft matrix.

Initial disclosure for implemented unscaled FP rows:
- Grouping: `G=1`.
- Partial-sum mode: `psm=0` / exact-reference group formation, implemented initially through SoftFloat operations in the accumulator format for supported IEEE rows.
- Group rounding: `rnd=frm`.
- Microscaling (`v0.scale`/`vbs`) remains unimplemented and illegal/reserved for now.
- Alternate C accumulator format selection (`altfmt` in the draft text) is not yet represented in this local `vtype`; the first loop therefore supports only default IEEE C formats and treats alternate/non-default formats as future work.

Implemented pieces:
1. Shared decode/execute path for unscaled `vfmmacc.vv`, `vfwmmacc.vv`, and `vfqmmacc.vv` under `Ext_Zvvfmm`:
   - requires `vm=1` and `vstart=0`;
   - rejects unsupported `SEW`, `W`, and alternate input/output format combinations explicitly;
   - reuses `ime_mat_A_idx`, `ime_mat_B_idx`, `ime_mat_C_idx`, `ime_group_size_to_pow`, and active-column `VL/(lambda*LMUL)` geometry from the integer path;
   - uses dynamic `frm` through existing SoftFloat helper calls, so reserved `frm` is rejected by `valid_fp_op`;
   - ORs returned exception flags into `fflags` with `accrue_fflags` only for active output computations.
2. Same-width `vfmmacc.vv` rows for FP16, FP32, and FP64 (`W=1`, `altfmt_A=altfmt_B=0`, default IEEE C).
3. `vfwmmacc.vv` rows for FP16→FP32, BF16→FP32 (`altfmt_A/B=1` for BF16 inputs; mixed FP16/BF16 follows the same per-operand conversion path), and FP32→FP64.
4. `vfqmmacc.vv` rows for FP16/BF16→FP64.

Still deferred:
- `vf8wmmacc.vv`, OFP8/OFP4 input formats, non-default C accumulator `altfmt`, round-to-odd group rounding, disclosed `psm=1`, microscaling (`v0.scale`/`vbs`), integer-input FP-accumulate forms, and fine-grained per-format extension gating.

Test requirements for the FP loop:
- First-party assembly tests should continue to use `.word` encodings until assembler mnemonic support exists.
- FP32 W=1 smoke test: `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, `VLEN=256`; verify a 4x2 by 2x2 exact matrix multiply-add and confirm inactive C tile columns remain unchanged.
- Limited-vector-length test: set `VL=lambda*LMUL` so only one C/B column is active; place flag-generating sentinel values in inactive columns and verify they do not affect C or `fflags`.
- Multiple-LMUL test: exercise `LMUL=2` with exact values to prove `K_eff=lambda*LMUL` and register-step traversal.
- Rounding tests: after confirming the disclosure (`G=1`, `psm=0`, `rnd=frm`) with the user, add RNE plus at least one directed mode such as RTZ/RDN and check result bits and `NX`.
- Special-value tests: sNaN invalid, `0*inf` invalid, qNaN/default-NaN behavior, and inactive/tail non-participation. The FP32 limited-VL test already checks inactive sNaNs do not affect `fflags`; broaden this to the newer FP16/BF16/FP64 rows.
- Illegal/reserved tests: `vm=0` for `vfmmacc`, nonzero `vstart`, bad `VL` divisibility, misaligned register groups, unsupported alternate formats, `vfqmmacc` with `SEW=8`, and `vf8wmmacc` with `SEW<32`.

Open questions before broadening scope:
1. Whether to add the draft spec's separate C `altfmt` vtype bit now or keep this local model to default C formats until the vtype layout is settled.
2. Whether `G=1, psm=0, rnd=frm` is the desired architectural disclosure for the initial reference implementation, or whether a fused/`rnd=xct` profile is preferred.
3. Whether `Zvvfmm` should remain the coarse gate for all default IEEE FP rows in this repo or be replaced with fine-grained draft row extensions before lower-precision rows are enabled.

## Next-loop checklist

1. Add rounding-sensitive tests for the disclosed `G=1`, `psm=0`, `rnd=frm` profile, including directed rounding modes and `NX` checks.
2. Add explicit special-value tests for sNaN invalid, qNaN/default-NaN behavior, `0*inf`, and inactive/tail non-participation in the new FP16/BF16/FP64 rows.
3. Decide whether to add the draft C `altfmt` field and fine-grained row/subextension legality before enabling non-default C/BF16 accumulator rows.
4. Add `vf8wmmacc.vv`, OFP8/OFP4, microscaling support, and associated `vtype.vbs` behavior only after unscaled default-format FP remains stable.
5. Replace simplified row/subextension legality with the full extension implication/configuration table once the draft naming is settled.
6. Expand tests across lambda/LMUL/SEW combinations, masked/tail behavior, reserved encodings, and trap/restart cases.
