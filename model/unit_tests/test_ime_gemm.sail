// IME matrix multiply-accumulate regression tests for the largest C register
// group. The default unit-test config is rv64d_v256_e64 (VLEN=256), where
// SEW=16 with lambda=1 gives M=16 and EMUL_C=16: the C tile fills v16-v31
// and column j of C is register v16 + j.

// vtype for SEW=16, LMUL=1, lambda=1.
function ime_test_set_e16_l1(vl_value : int) -> unit = {
  vtype = [Mk_Vtype(zeros()) with vlambda = 0b001, vsew = 0b001, vlmul = 0b000];
  vl = to_bits_unsafe(sizeof(vlen_exp) + 1, vl_value)
}

// FP16 encodings of 0.0, 1.0, ..., 15.0, indexed by value.
let ime_test_fp16_ints : vector(16, bits(16)) = [
  0x4b80, 0x4b00, 0x4a80, 0x4a00, 0x4980, 0x4900, 0x4880, 0x4800,
  0x4700, 0x4600, 0x4500, 0x4400, 0x4200, 0x4000, 0x3c00, 0x0000
]

$[test]
function test_ime_gemm_geometry_emul_c16() -> unit = {
  let saved_vtype = vtype;
  let saved_vl = vl;
  let v0 = encdec_vreg(0b00000);
  let v8 = encdec_vreg(0b01000);
  let v12 = encdec_vreg(0b01100);
  let v16 = encdec_vreg(0b10000);

  assert(ime_group_size_legal(16));
  assert(not(ime_group_size_legal(32)));

  ime_test_set_e16_l1(16);
  match ime_gemm_geometry(1) {
    Some(g) => {
      assert(g.M == 16 & g.N == 16 & g.EMUL_C == 16 & g.K_eff == 1);
      // vd must be a multiple of EMUL_C: v0 and v16 only.
      assert(ime_gemm_groups_ok(g, v8, v12, v16));
      assert(ime_gemm_groups_ok(g, v8, v12, v0));
      assert(not(ime_gemm_groups_ok(g, v12, v0, v8)));
    },
    None() => assert(false, "EMUL_C=16 geometry rejected"),
  };

  vtype = saved_vtype;
  vl = saved_vl;
}

$[test]
function test_ime_c_group_spans_16_registers() -> unit = {
  let v16 = encdec_vreg(0b10000);
  let v24 = encdec_vreg(0b11000);
  let v31 = encdec_vreg(0b11111);

  // VLEN=256, EEW=16: 16 elements per register; idx 131 is v24 element 3.
  write_single_element_in_group(16, 131, v16, 0x1234, IME_EMUL_C_MAX);
  assert(read_single_element(16, 3, v24) == 0x1234);
  assert(read_single_element_in_group(16, 131, v16, IME_EMUL_C_MAX) == 0x1234);

  // EEW=64: 4 elements per register; idx 63 is v31 element 3.
  write_single_element_in_group(64, 63, v16, 0x0123456789abcdef, IME_EMUL_C_MAX);
  assert(read_single_element(64, 3, v31) == 0x0123456789abcdef);
  assert(ime_read_c(64, 63, v16) == 0x0123456789abcdef);
}

$[test]
function test_ime_int_gemm_emul_c16() -> unit = {
  let saved_vtype = vtype;
  let saved_vl = vl;
  let v8 = encdec_vreg(0b01000);
  let v12 = encdec_vreg(0b01100);
  let v16 = encdec_vreg(0b10000);

  // A[i] = i - 5 in v8, B^T[j] = 2j - 7 in v12, C[i][j] = 16j + i in
  // v16 + j. K_eff = 1, so C[i][j] += A[i] * B^T[j].
  foreach (n from 0 to 15) {
    write_single_element(16, n, v8, to_bits_unsafe(16, n - 5));
    write_single_element(16, n, v12, to_bits_unsafe(16, 2 * n - 7));
  };
  foreach (n from 0 to 255) {
    write_single_element_in_group(16, n, v16, to_bits_unsafe(16, n), IME_EMUL_C_MAX)
  };

  ime_test_set_e16_l1(16);
  match execute_ime_int_gemm(16, 1, 1, 1, true, true, v8, v12, v16) {
    Retire_Success() => (),
    _ => assert(false, "EMUL_C=16 vmmacc did not retire"),
  };
  foreach (j from 0 to 15) {
    foreach (i from 0 to 15) {
      assert(signed(read_single_element_in_group(16, 16 * j + i, v16, IME_EMUL_C_MAX)) == 16 * j + i + (i - 5) * (2 * j - 7))
    }
  };

  vtype = saved_vtype;
  vl = saved_vl;
}

$[test]
function test_ime_fp_gemm_emul_c16() -> unit = {
  let saved_vtype = vtype;
  let saved_vl = vl;
  let saved_fcsr = fcsr;
  let v8 = encdec_vreg(0b01000);
  let v12 = encdec_vreg(0b01100);
  let v16 = encdec_vreg(0b10000);

  // FP16: A[i] = 1.0, B^T[j] = j, C = 0, so C[i][j] = j in v16 + j. All
  // values are exact, so the result does not depend on the rounding mode.
  foreach (n from 0 to 15) {
    write_single_element(16, n, v8, 0x3c00);
    write_single_element(16, n, v12, ime_test_fp16_ints[n]);
  };
  foreach (n from 0 to 255) {
    write_single_element_in_group(16, n, v16, 0x0000, IME_EMUL_C_MAX)
  };

  ime_test_set_e16_l1(16);
  match ime_gemm_geometry(1) {
    Some(g) => ime_fp_gemm(g, IME_FP16, IME_FP16, IME_FP16, IME_UNSCALED, 0, v8, v12, v16),
    None()  => assert(false, "EMUL_C=16 geometry rejected"),
  };
  foreach (j from 0 to 15) {
    foreach (i from 0 to 15) {
      assert(read_single_element_in_group(16, 16 * j + i, v16, IME_EMUL_C_MAX) == ime_test_fp16_ints[j])
    }
  };

  vtype = saved_vtype;
  vl = saved_vl;
  fcsr = saved_fcsr;
}
