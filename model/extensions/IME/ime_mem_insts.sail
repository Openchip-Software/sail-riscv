// =======================================================================================
// Integrated Matrix Extension (IME / Zvvm) tile load/store instructions.
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

// vmtl.v — order-preserving tile load
union clause instruction = VMTLTYPE : (bits(3), bits(1), ime_tile_mode, bits(1), regidx, regidx, vregidx)

mapping clause encdec = VMTLTYPE(lambda_field, L, mode, vm, rs2, rs1, vd)
  <-> lambda_field @ L @ encdec_ime_tile_mode(mode) @ vm @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b111 @ encdec_vreg(vd) @ 0b0000111
  when (mode == IME_TILE_ORDERED & currentlyEnabled(Ext_Zvvmtls)) |
       (mode == IME_TILE_TRANSPOSED & currentlyEnabled(Ext_Zvvmttls))

function clause execute VMTLTYPE(lambda_field, L, mode, vm, rs2, rs1, vd) = {
  if mode != IME_TILE_ORDERED & mode != IME_TILE_TRANSPOSED then return Illegal_Instruction();
  let transposed : bool = mode == IME_TILE_TRANSPOSED;

  let SEW = get_sew();
  let SEW_bytes = get_sew_bytes();
  let LMUL_pow = get_lmul_pow();
  let EMUL_pow = LMUL_pow;
  let num_elem = get_num_elem(EMUL_pow, SEW);
  let lambda_value = if L == 0b1 then ime_lambda_field_to_value(lambda_field) else ime_lambda_field_to_value(vtype[vlambda]);

  if not(valid_vtype()) |
     not(valid_reg_group(vd, EMUL_pow)) |
     not(ime_lambda_supported_value_for_vsew(lambda_value, vtype[vsew])) |
     lambda_value == 0
  then return Illegal_Instruction();

  let LMUL = ime_lmul_value_nat(LMUL_pow);
  let lambda_nat = if L == 0b1 then ime_lambda_field_to_nat(lambda_field) else ime_lambda_field_to_nat(vtype[vlambda]);
  let cols = lambda_nat * LMUL;
  if cols == 0 then return Illegal_Instruction();
  assert(lambda_nat > 0);
  let VL = unsigned(vl);
  let rows = VL / cols;
  if transposed & rows == 0 then return Illegal_Instruction();

  // rs2=x0 selects the natural leading dimension: lambda*LMUL for the
  // order-preserving traversal, VLEN/(SEW*lambda) for the transposing one.
  let LD : nat = if rs2 == zreg then {
    if transposed then vlen / (SEW * lambda_nat) else cols
  } else unsigned(X(rs2));

  let vm_val = read_vmask(num_elem, vm, zvreg);
  let vd_val = read_vreg(num_elem, SEW, LMUL_pow, vd);

  let 'n = num_elem;
  let 'm = SEW;
  let (result, mask) : (vector('n, bits('m)), bits('n)) = init_masked_result(num_elem, SEW, LMUL_pow, vd_val, vm_val);

  foreach (i from 0 to (num_elem - 1)) {
    if mask[i] == 0b1 then {
      set_vstart(to_bits_unsafe(16, i));
      let mem_off = if transposed
                    then ime_tile_transposed_mem_off(i, rows, cols, LD)
                    else ime_tile_ordered_mem_off(i, cols, LD);
      let byte_offset = mem_off * SEW_bytes;
      match SEW {
        8  => match vmem_read(rs1, to_bits_unsafe(xlen, byte_offset), 1, Load(Vector), false, false, false) {
               Ok(elem) => write_single_element(8, i, vd, elem),
               Err(e)   => return e,
             },
        16 => match vmem_read(rs1, to_bits_unsafe(xlen, byte_offset), 2, Load(Vector), false, false, false) {
               Ok(elem) => write_single_element(16, i, vd, elem),
               Err(e)   => return e,
             },
        32 => match vmem_read(rs1, to_bits_unsafe(xlen, byte_offset), 4, Load(Vector), false, false, false) {
               Ok(elem) => write_single_element(32, i, vd, elem),
               Err(e)   => return e,
             },
        64 => match vmem_read(rs1, to_bits_unsafe(xlen, byte_offset), 8, Load(Vector), false, false, false) {
               Ok(elem) => write_single_element(64, i, vd, elem),
               Err(e)   => return e,
             },
      }
    } else {
      write_single_element(SEW, i, vd, result[i])
    }
  };

  set_vstart(zeros());
  RETIRE_SUCCESS
}

// vmts.v — order-preserving tile store
union clause instruction = VMTSTYPE : (bits(3), bits(1), ime_tile_mode, bits(1), regidx, regidx, vregidx)

mapping clause encdec = VMTSTYPE(lambda_field, L, mode, vm, rs2, rs1, vs3)
  <-> lambda_field @ L @ encdec_ime_tile_mode(mode) @ vm @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b111 @ encdec_vreg(vs3) @ 0b0100111
  when (mode == IME_TILE_ORDERED & currentlyEnabled(Ext_Zvvmtls)) |
       (mode == IME_TILE_TRANSPOSED & currentlyEnabled(Ext_Zvvmttls))

function clause execute VMTSTYPE(lambda_field, L, mode, vm, rs2, rs1, vs3) = {
  if mode != IME_TILE_ORDERED & mode != IME_TILE_TRANSPOSED then return Illegal_Instruction();
  let transposed : bool = mode == IME_TILE_TRANSPOSED;

  let SEW = get_sew();
  let SEW_bytes = get_sew_bytes();
  let LMUL_pow = get_lmul_pow();
  let EMUL_pow = LMUL_pow;
  let num_elem = get_num_elem(EMUL_pow, SEW);
  let lambda_value = if L == 0b1 then ime_lambda_field_to_value(lambda_field) else ime_lambda_field_to_value(vtype[vlambda]);

  if not(valid_vtype()) |
     not(valid_reg_group(vs3, EMUL_pow)) |
     not(ime_lambda_supported_value_for_vsew(lambda_value, vtype[vsew])) |
     lambda_value == 0
  then return Illegal_Instruction();

  let LMUL = ime_lmul_value_nat(LMUL_pow);
  let lambda_nat = if L == 0b1 then ime_lambda_field_to_nat(lambda_field) else ime_lambda_field_to_nat(vtype[vlambda]);
  let cols = lambda_nat * LMUL;
  if cols == 0 then return Illegal_Instruction();
  assert(lambda_nat > 0);
  let VL = unsigned(vl);
  let rows = VL / cols;
  if transposed & rows == 0 then return Illegal_Instruction();

  // rs2=x0 selects the natural leading dimension: lambda*LMUL for the
  // order-preserving traversal, VLEN/(SEW*lambda) for the transposing one.
  let LD : nat = if rs2 == zreg then {
    if transposed then vlen / (SEW * lambda_nat) else cols
  } else unsigned(X(rs2));

  let vm_val = read_vmask(num_elem, vm, zvreg);
  let 'n = num_elem;
  let mask : bits('n) = init_masked_source(num_elem, LMUL_pow, vm_val);

  foreach (i from 0 to (num_elem - 1)) {
    if mask[i] == 0b1 then {
      set_vstart(to_bits_unsafe(16, i));
      let mem_off = if transposed
                    then ime_tile_transposed_mem_off(i, rows, cols, LD)
                    else ime_tile_ordered_mem_off(i, cols, LD);
      let byte_offset = mem_off * SEW_bytes;
      let data = read_single_element(SEW, i, vs3);
      match SEW {
        8  => match vmem_write(rs1, to_bits_unsafe(xlen, byte_offset), 1, data[7 .. 0], Store(Vector), false, false, false) {
               Ok(true)  => (),
               Ok(false) => internal_error(__FILE__, __LINE__, "store got false from vmem_write"),
               Err(e)    => return e,
             },
        16 => match vmem_write(rs1, to_bits_unsafe(xlen, byte_offset), 2, data[15 .. 0], Store(Vector), false, false, false) {
               Ok(true)  => (),
               Ok(false) => internal_error(__FILE__, __LINE__, "store got false from vmem_write"),
               Err(e)    => return e,
             },
        32 => match vmem_write(rs1, to_bits_unsafe(xlen, byte_offset), 4, data[31 .. 0], Store(Vector), false, false, false) {
               Ok(true)  => (),
               Ok(false) => internal_error(__FILE__, __LINE__, "store got false from vmem_write"),
               Err(e)    => return e,
             },
        64 => match vmem_write(rs1, to_bits_unsafe(xlen, byte_offset), 8, data[63 .. 0], Store(Vector), false, false, false) {
               Ok(true)  => (),
               Ok(false) => internal_error(__FILE__, __LINE__, "store got false from vmem_write"),
               Err(e)    => return e,
             },
      }
    }
  };

  set_vstart(zeros());
  RETIRE_SUCCESS
}


// Shared unscaled integer GEMM executor for the vmmacc.vv family. This mirrors
// the specification's int_gemm helper: decode geometry from vtype/vl plus the
// per-instruction widening factor W, loop over active C columns j, rows i, and
// the effective K dimension, and use mat_A/mat_B/mat_C indexing.
//
// `EEW_C` is the C accumulator (and storage) element width SEW. `W` is the
// widening factor: W=1 is non-widening (vmmacc.vv); W=2/4/8 select the widening
// variants (vwmmacc/vqmmacc/v8wmmacc), each consuming W packed narrow input
// elements of width EEW = SEW/W per SEW-bit storage element. Only W=1 is
// currently dispatched; the W>1 paths are exercised by later widening tasks.
function execute_ime_int_gemm(
  EEW_C : sew_bitsize,
  W : nat,
  lambda_value : nat,
  LMUL : nat,
  signed_A : bool,
  signed_B : bool,
  vs1 : vregidx,
  vs2 : vregidx,
  vd : vregidx
) -> ExecutionResult = {
  assert(lambda_value > 0);
  assert(LMUL > 0);
  assert(W > 0);
  assert(EEW_C * lambda_value > 0);
  assert(EEW_C * lambda_value * lambda_value > 0);
  let epr_C : nat = vlen / EEW_C;
  let K_eff : nat = lambda_value * W * LMUL;
  assert(K_eff > 0);
  // Number of SEW-bit storage elements per matrix row along the K direction.
  // W narrow logical elements are packed into each storage element, so the
  // physical storage geometry is identical to the non-widening (W=1) case.
  let storage_K : nat = lambda_value * LMUL;
  assert(storage_K > 0);
  let M : nat = vlen / (EEW_C * lambda_value);
  let N_max : nat = M;
  let EMUL_C : nat = vlen / (EEW_C * lambda_value * lambda_value);
  // VL is counted in C/storage-width elements, so the active C column count
  // follows the specification Sail helper's vl_div = lambda * LMUL rather
  // than the widened logical K_eff = lambda * W * LMUL.
  let N : nat = unsigned(vl) / storage_K;
  let EMUL_C_pow = ime_group_size_to_pow(EMUL_C);
  // Logical input element width; W such elements pack into one SEW storage slot.
  let EEW : nat = EEW_C / W;

  if W != 1 & W != 2 & W != 4 & W != 8 then return Illegal_Instruction();
  if EEW_C % W != 0 then return Illegal_Instruction();
  if not(ime_int_eew_supported(EEW)) then return Illegal_Instruction();
  if K_eff == 0 |
     storage_K == 0 |
     M == 0 |
     N == 0 |
     unsigned(vl) % storage_K != 0 |
     N > N_max |
     not(ime_group_size_legal(EMUL_C)) |
     not(valid_reg_group(vd, EMUL_C_pow))
  then return Illegal_Instruction();

  foreach (j from 0 to (N - 1)) {
    foreach (i from 0 to (M - 1)) {
      let c_flat = ime_mat_C_idx(i, j, N_max, EMUL_C, lambda_value, epr_C);
      var acc : int = signed(read_single_element(EEW_C, c_flat, vd));
      foreach (k from 0 to (K_eff - 1)) {
        let storage_col = ime_packed_storage_col(k, W);
        let lane = ime_packed_lane(k, W);
        let a_flat = ime_mat_A_idx(i, storage_col, storage_K, LMUL, lambda_value, epr_C);
        let b_flat = ime_mat_B_idx(storage_col, j, storage_K, LMUL, lambda_value, epr_C);
        let a_storage = unsigned(read_single_element(EEW_C, a_flat, vs1));
        let b_storage = unsigned(read_single_element(EEW_C, b_flat, vs2));
        let a_val = ime_packed_subelement_value(a_storage, lane, EEW, signed_A);
        let b_val = ime_packed_subelement_value(b_storage, lane, EEW, signed_B);
        acc = acc + a_val * b_val
      };
      write_single_element(EEW_C, c_flat, vd, to_bits_unsafe(EEW_C, acc))
    }
  };

  set_vstart(zeros());
  RETIRE_SUCCESS
}

// Shared dispatch for the unscaled integer vmmacc.vv family. The members differ
// only in the per-instruction widening factor W (vmmacc.vv W=1, vwmmacc.vv W=2,
// and later vqmmacc.vv W=4, v8wmmacc.vv W=8); they share the vm=1-only encoding,
// vstart/vtype legality, LMUL-aligned input register groups, and the dispatch to
// execute_ime_int_gemm on the C accumulator SEW. `vm=0` is reserved for the
// microscaled integer-input FP-accumulate forms, which are not implemented.
function execute_ime_int_mmacc(W : nat, vm : bits(1), vs2 : vregidx, vs1 : vregidx, vd : vregidx) -> ExecutionResult = {
  let SEW = get_sew();
  let LMUL_pow = get_lmul_pow();
  let lambda_value = ime_lambda_field_to_value(vtype[vlambda]);
  let lambda_nat = ime_lambda_field_to_nat(vtype[vlambda]);
  let LMUL = ime_lmul_value_nat(LMUL_pow);
  let signed_A = vtype[altfmt_A] == 0b0;
  let signed_B = vtype[altfmt_B] == 0b0;

  if vm != 0b1 |
     not(valid_vtype()) |
     unsigned(vstart) != 0 |
     lambda_value == 0 |
     LMUL == 0 |
     not(valid_reg_group(vs1, LMUL_pow)) |
     not(valid_reg_group(vs2, LMUL_pow))
  then return Illegal_Instruction();

  match SEW {
    8  => execute_ime_int_gemm(8, W, lambda_nat, LMUL, signed_A, signed_B, vs1, vs2, vd),
    16 => execute_ime_int_gemm(16, W, lambda_nat, LMUL, signed_A, signed_B, vs1, vs2, vd),
    32 => execute_ime_int_gemm(32, W, lambda_nat, LMUL, signed_A, signed_B, vs1, vs2, vd),
    64 => execute_ime_int_gemm(64, W, lambda_nat, LMUL, signed_A, signed_B, vs1, vs2, vd),
  }
}

// vmmacc.vv — non-widening integer matrix multiply-accumulate.
// This is the first concrete member of the common IME GEMM family described
// in the specification's Sail starting point under integrated-matrix-insns.
union clause instruction = IMEVMMACCTYPE : (bits(1), vregidx, vregidx, vregidx)

mapping clause encdec = IMEVMMACCTYPE(vm, vs2, vs1, vd)
  <-> 0b111000 @ vm @ encdec_vreg(vs2) @ encdec_vreg(vs1) @ 0b000 @ encdec_vreg(vd) @ 0b1010111
  when currentlyEnabled(Ext_Zvvmm)

mapping clause assembly = IMEVMMACCTYPE(vm, vs2, vs1, vd)
  <-> "vmmacc.vv" ^ spc() ^ vreg_name(vd) ^ sep() ^ vreg_name(vs1) ^ sep() ^ vreg_name(vs2) ^ maybe_vmask(vm)

function clause execute IMEVMMACCTYPE(vm, vs2, vs1, vd) =
  execute_ime_int_mmacc(1, vm, vs2, vs1, vd)

// vwmmacc.vv — double-widening (W=2) integer matrix multiply-accumulate. A and B
// hold SEW/2-bit logical elements, two packed per SEW-bit storage element, and C
// accumulates at SEW. `vm=1` selects this unscaled integer form; `vm=0` is the
// reserved vfwimmacc.vv microscaled encoding (not implemented), so it falls
// through to the W-check / vm check in the shared dispatch and raises illegal.
union clause instruction = IMEVWMMACCTYPE : (bits(1), vregidx, vregidx, vregidx)

mapping clause encdec = IMEVWMMACCTYPE(vm, vs2, vs1, vd)
  <-> 0b111001 @ vm @ encdec_vreg(vs2) @ encdec_vreg(vs1) @ 0b000 @ encdec_vreg(vd) @ 0b1010111
  when currentlyEnabled(Ext_Zvvmm)

mapping clause assembly = IMEVWMMACCTYPE(vm, vs2, vs1, vd)
  <-> "vwmmacc.vv" ^ spc() ^ vreg_name(vd) ^ sep() ^ vreg_name(vs1) ^ sep() ^ vreg_name(vs2) ^ maybe_vmask(vm)

function clause execute IMEVWMMACCTYPE(vm, vs2, vs1, vd) =
  execute_ime_int_mmacc(2, vm, vs2, vs1, vd)

// vqmmacc.vv — quad-widening (W=4) integer matrix multiply-accumulate. A and B
// hold SEW/4-bit logical elements, four packed per SEW-bit storage element, and
// C accumulates at SEW. Only SEW in {16,32,64} is valid (EEW = SEW/4 in
// {4,8,16}); SEW=8 would give the reserved EEW=2 and is rejected by the shared
// EEW legality check. `vm=1` selects this unscaled integer form; `vm=0` is the
// reserved vfqmmacc.vv microscaled encoding (not implemented), so it falls
// through to the W-check / vm check in the shared dispatch and raises illegal.
union clause instruction = IMEVQMMACCTYPE : (bits(1), vregidx, vregidx, vregidx)

mapping clause encdec = IMEVQMMACCTYPE(vm, vs2, vs1, vd)
  <-> 0b111010 @ vm @ encdec_vreg(vs2) @ encdec_vreg(vs1) @ 0b000 @ encdec_vreg(vd) @ 0b1010111
  when currentlyEnabled(Ext_Zvvmm)

mapping clause assembly = IMEVQMMACCTYPE(vm, vs2, vs1, vd)
  <-> "vqmmacc.vv" ^ spc() ^ vreg_name(vd) ^ sep() ^ vreg_name(vs1) ^ sep() ^ vreg_name(vs2) ^ maybe_vmask(vm)

function clause execute IMEVQMMACCTYPE(vm, vs2, vs1, vd) =
  execute_ime_int_mmacc(4, vm, vs2, vs1, vd)

// v8wmmacc.vv — octuple-widening (W=8) integer matrix multiply-accumulate. A and
// B hold SEW/8-bit logical elements, eight packed per SEW-bit storage element,
// and C accumulates at SEW. Only SEW in {32,64} is valid (EEW = SEW/8 in {4,8});
// SEW in {8,16} would give the reserved EEW in {1,2} and is rejected by the
// shared EEW legality check. `vm=1` selects this unscaled integer form; `vm=0`
// is the reserved vf8wimmacc.vv microscaled encoding (not implemented), so it
// falls through to the W-check / vm check in the shared dispatch and raises
// illegal.
union clause instruction = IMEV8WMMACCTYPE : (bits(1), vregidx, vregidx, vregidx)

mapping clause encdec = IMEV8WMMACCTYPE(vm, vs2, vs1, vd)
  <-> 0b111011 @ vm @ encdec_vreg(vs2) @ encdec_vreg(vs1) @ 0b000 @ encdec_vreg(vd) @ 0b1010111
  when currentlyEnabled(Ext_Zvvmm)

mapping clause assembly = IMEV8WMMACCTYPE(vm, vs2, vs1, vd)
  <-> "v8wmmacc.vv" ^ spc() ^ vreg_name(vd) ^ sep() ^ vreg_name(vs1) ^ sep() ^ vreg_name(vs2) ^ maybe_vmask(vm)

function clause execute IMEV8WMMACCTYPE(vm, vs2, vs1, vd) =
  execute_ime_int_mmacc(8, vm, vs2, vs1, vd)

function ime_bf16_to_f32_set_flags(v : bits(16)) -> bits(32) = {
  let sign = v[15 .. 15];
  let exp = v[14 .. 7];
  let mant = v[6 .. 0];
  let is_nan = exp == ones() & mant != zeros();
  let is_inf = exp == ones() & mant == zeros();
  let fflags = if is_nan & signed(mant) >= 0 then nvFlag() else zeros();
  let value = if is_nan then canonical_NaN_S()
              else if is_inf then fmake_S(sign, ones(), zeros())
              else fmake_S(sign, exp, mant @ zeros(16));
  accrue_fflags(fflags);
  value
}

function ime_fp16_to_fp32_set_flags(rm_3b : bits(3), v : bits(16)) -> bits(32) = {
  let (fflags, value) = riscv_f16ToF32(rm_3b, v);
  accrue_fflags(fflags);
  value
}

function ime_fp16_to_fp64_set_flags(rm_3b : bits(3), v : bits(16)) -> bits(64) = {
  let (fflags, value) = riscv_f16ToF64(rm_3b, v);
  accrue_fflags(fflags);
  value
}

function ime_fp32_to_fp64_set_flags(rm_3b : bits(3), v : bits(32)) -> bits(64) = {
  let (fflags, value) = riscv_f32ToF64(rm_3b, v);
  accrue_fflags(fflags);
  value
}

function ime_bf16_to_fp64_set_flags(rm_3b : bits(3), v : bits(16)) -> bits(64) =
  ime_fp32_to_fp64_set_flags(rm_3b, ime_bf16_to_f32_set_flags(v))

function ime_fp16_or_bf16_to_fp32(rm_3b : bits(3), altfmt : bits(1), v : bits(16)) -> bits(32) =
  if altfmt == 0b0 then ime_fp16_to_fp32_set_flags(rm_3b, v)
  else ime_bf16_to_f32_set_flags(v)

function ime_fp16_or_bf16_to_fp64(rm_3b : bits(3), altfmt : bits(1), v : bits(16)) -> bits(64) =
  if altfmt == 0b0 then ime_fp16_to_fp64_set_flags(rm_3b, v)
  else ime_bf16_to_fp64_set_flags(rm_3b, v)

function ime_lane16_from32(storage : bits(32), lane : nat) -> bits(16) =
  if lane == 0 then storage[15 .. 0] else storage[31 .. 16]

function ime_lane16_from64(storage : bits(64), lane : nat) -> bits(16) =
  if lane == 0 then storage[15 .. 0]
  else if lane == 1 then storage[31 .. 16]
  else if lane == 2 then storage[47 .. 32]
  else storage[63 .. 48]

function ime_lane32_from64(storage : bits(64), lane : nat) -> bits(32) =
  if lane == 0 then storage[31 .. 0] else storage[63 .. 32]

// Shared unscaled floating-point GEMM executor for the vfmmacc.vv family. The
// tile/register geometry is identical to the integer execute_ime_int_gemm path
// (it reuses the same ime_mat_A/B/C_idx helpers); only the accumulation is in
// IEEE floating point via the SoftFloat helpers fp_mul/fp_add.
//
// Implemented rows in this staged loop:
//   W=1: FP16, FP32, FP64 same-width (default IEEE C format).
//   W=2: FP16/BF16 -> FP32 and FP32 -> FP64.
//   W=4: FP16/BF16 -> FP64.
// Microscaled vm=0, OFP4/OFP8, integer-input FP-accumulate, and non-default C
// altfmt remain out of scope and are rejected by the dispatch.
//
// Disclosed reference profile for the implemented rows: G=1, psm=0 (exact
// per-product partial sum), rnd=frm. Each product is rounded to the C format and
// then accumulated into C under the dynamic frm. Both rounding points accrue
// exception flags into fflags, and only active C columns (j < N) contribute flags.
function execute_ime_fp_gemm(
  EEW_C : sew_bitsize,
  W : nat,
  lambda_value : nat,
  LMUL : nat,
  rm_3b : bits(3),
  altfmt_A : bits(1),
  altfmt_B : bits(1),
  vs1 : vregidx,
  vs2 : vregidx,
  vd : vregidx
) -> ExecutionResult = {
  assert(lambda_value > 0);
  assert(LMUL > 0);
  assert(W > 0);
  assert(EEW_C * lambda_value > 0);
  assert(EEW_C * lambda_value * lambda_value > 0);
  let epr_C : nat = vlen / EEW_C;
  let K_eff : nat = lambda_value * W * LMUL;
  assert(K_eff > 0);
  // Number of SEW-bit storage elements per matrix row along K. W narrow logical
  // elements are packed into each storage element for the widening rows.
  let storage_K : nat = lambda_value * LMUL;
  assert(storage_K > 0);
  let M : nat = vlen / (EEW_C * lambda_value);
  let N_max : nat = M;
  let EMUL_C : nat = vlen / (EEW_C * lambda_value * lambda_value);
  let N : nat = unsigned(vl) / storage_K;
  let EMUL_C_pow = ime_group_size_to_pow(EMUL_C);

  let EEW : nat = EEW_C / W;

  if W != 1 & W != 2 & W != 4 then return Illegal_Instruction();
  if EEW_C % W != 0 then return Illegal_Instruction();
  if not(EEW == 16 | EEW == 32 | EEW == 64) then return Illegal_Instruction();
  if K_eff == 0 |
     storage_K == 0 |
     M == 0 |
     N == 0 |
     unsigned(vl) % storage_K != 0 |
     N > N_max |
     not(ime_group_size_legal(EMUL_C)) |
     not(valid_reg_group(vd, EMUL_C_pow))
  then return Illegal_Instruction();

  match (EEW_C, W) {
    (16, 1) => {
      foreach (j from 0 to (N - 1)) {
        foreach (i from 0 to (M - 1)) {
          let c_flat = ime_mat_C_idx(i, j, N_max, EMUL_C, lambda_value, epr_C);
          var acc : bits(16) = read_single_element(16, c_flat, vd);
          foreach (k from 0 to (K_eff - 1)) {
            let a_flat = ime_mat_A_idx(i, k, storage_K, LMUL, lambda_value, epr_C);
            let b_flat = ime_mat_B_idx(k, j, storage_K, LMUL, lambda_value, epr_C);
            let prod = fp_mul(rm_3b, read_single_element(16, a_flat, vs1), read_single_element(16, b_flat, vs2));
            acc = fp_add(rm_3b, acc, prod)
          };
          write_single_element(16, c_flat, vd, acc)
        }
      }
    },
    (32, 1) => {
      foreach (j from 0 to (N - 1)) {
        foreach (i from 0 to (M - 1)) {
          let c_flat = ime_mat_C_idx(i, j, N_max, EMUL_C, lambda_value, epr_C);
          var acc : bits(32) = read_single_element(32, c_flat, vd);
          foreach (k from 0 to (K_eff - 1)) {
            let a_flat = ime_mat_A_idx(i, k, storage_K, LMUL, lambda_value, epr_C);
            let b_flat = ime_mat_B_idx(k, j, storage_K, LMUL, lambda_value, epr_C);
            let prod = fp_mul(rm_3b, read_single_element(32, a_flat, vs1), read_single_element(32, b_flat, vs2));
            acc = fp_add(rm_3b, acc, prod)
          };
          write_single_element(32, c_flat, vd, acc)
        }
      }
    },
    (64, 1) => {
      foreach (j from 0 to (N - 1)) {
        foreach (i from 0 to (M - 1)) {
          let c_flat = ime_mat_C_idx(i, j, N_max, EMUL_C, lambda_value, epr_C);
          var acc : bits(64) = read_single_element(64, c_flat, vd);
          foreach (k from 0 to (K_eff - 1)) {
            let a_flat = ime_mat_A_idx(i, k, storage_K, LMUL, lambda_value, epr_C);
            let b_flat = ime_mat_B_idx(k, j, storage_K, LMUL, lambda_value, epr_C);
            let prod = fp_mul(rm_3b, read_single_element(64, a_flat, vs1), read_single_element(64, b_flat, vs2));
            acc = fp_add(rm_3b, acc, prod)
          };
          write_single_element(64, c_flat, vd, acc)
        }
      }
    },
    (32, 2) => {
      foreach (j from 0 to (N - 1)) {
        foreach (i from 0 to (M - 1)) {
          let c_flat = ime_mat_C_idx(i, j, N_max, EMUL_C, lambda_value, epr_C);
          var acc : bits(32) = read_single_element(32, c_flat, vd);
          foreach (k from 0 to (K_eff - 1)) {
            let storage_col = ime_packed_storage_col(k, W);
            let lane = ime_packed_lane(k, W);
            let a_flat = ime_mat_A_idx(i, storage_col, storage_K, LMUL, lambda_value, epr_C);
            let b_flat = ime_mat_B_idx(storage_col, j, storage_K, LMUL, lambda_value, epr_C);
            let a = ime_fp16_or_bf16_to_fp32(rm_3b, altfmt_A, ime_lane16_from32(read_single_element(32, a_flat, vs1), lane));
            let b = ime_fp16_or_bf16_to_fp32(rm_3b, altfmt_B, ime_lane16_from32(read_single_element(32, b_flat, vs2), lane));
            let prod = fp_mul(rm_3b, a, b);
            acc = fp_add(rm_3b, acc, prod)
          };
          write_single_element(32, c_flat, vd, acc)
        }
      }
    },
    (64, 2) => {
      foreach (j from 0 to (N - 1)) {
        foreach (i from 0 to (M - 1)) {
          let c_flat = ime_mat_C_idx(i, j, N_max, EMUL_C, lambda_value, epr_C);
          var acc : bits(64) = read_single_element(64, c_flat, vd);
          foreach (k from 0 to (K_eff - 1)) {
            let storage_col = ime_packed_storage_col(k, W);
            let lane = ime_packed_lane(k, W);
            let a_flat = ime_mat_A_idx(i, storage_col, storage_K, LMUL, lambda_value, epr_C);
            let b_flat = ime_mat_B_idx(storage_col, j, storage_K, LMUL, lambda_value, epr_C);
            let a = ime_fp32_to_fp64_set_flags(rm_3b, ime_lane32_from64(read_single_element(64, a_flat, vs1), lane));
            let b = ime_fp32_to_fp64_set_flags(rm_3b, ime_lane32_from64(read_single_element(64, b_flat, vs2), lane));
            let prod = fp_mul(rm_3b, a, b);
            acc = fp_add(rm_3b, acc, prod)
          };
          write_single_element(64, c_flat, vd, acc)
        }
      }
    },
    (64, 4) => {
      foreach (j from 0 to (N - 1)) {
        foreach (i from 0 to (M - 1)) {
          let c_flat = ime_mat_C_idx(i, j, N_max, EMUL_C, lambda_value, epr_C);
          var acc : bits(64) = read_single_element(64, c_flat, vd);
          foreach (k from 0 to (K_eff - 1)) {
            let storage_col = ime_packed_storage_col(k, W);
            let lane = ime_packed_lane(k, W);
            let a_flat = ime_mat_A_idx(i, storage_col, storage_K, LMUL, lambda_value, epr_C);
            let b_flat = ime_mat_B_idx(storage_col, j, storage_K, LMUL, lambda_value, epr_C);
            let a = ime_fp16_or_bf16_to_fp64(rm_3b, altfmt_A, ime_lane16_from64(read_single_element(64, a_flat, vs1), lane));
            let b = ime_fp16_or_bf16_to_fp64(rm_3b, altfmt_B, ime_lane16_from64(read_single_element(64, b_flat, vs2), lane));
            let prod = fp_mul(rm_3b, a, b);
            acc = fp_add(rm_3b, acc, prod)
          };
          write_single_element(64, c_flat, vd, acc)
        }
      }
    },
    _ => return Illegal_Instruction()
  };

  set_vstart(zeros());
  RETIRE_SUCCESS
}

// Shared dispatch for the unscaled floating-point vfmmacc.vv family. Mirrors the
// integer execute_ime_int_mmacc legality (vm=1-only, vstart=0, LMUL-aligned
// input register groups) and additionally validates the FP operation/rounding
// mode via valid_fp_op. `vm=0` is reserved for microscaled forms in this staged
// implementation and raises illegal instruction.
function execute_ime_fp_mmacc(W : nat, vm : bits(1), vs2 : vregidx, vs1 : vregidx, vd : vregidx) -> ExecutionResult = {
  let SEW = get_sew();
  let LMUL_pow = get_lmul_pow();
  let rm_3b = fcsr[FRM];
  let lambda_value = ime_lambda_field_to_value(vtype[vlambda]);
  let lambda_nat = ime_lambda_field_to_nat(vtype[vlambda]);
  let LMUL = ime_lmul_value_nat(LMUL_pow);

  if vm != 0b1 |
     not(valid_vtype()) |
     not(valid_fp_op(SEW, rm_3b)) |
     unsigned(vstart) != 0 |
     lambda_value == 0 |
     LMUL == 0 |
     not(valid_reg_group(vs1, LMUL_pow)) |
     not(valid_reg_group(vs2, LMUL_pow))
  then return Illegal_Instruction();

  if W == 1 & (vtype[altfmt_A] != 0b0 | vtype[altfmt_B] != 0b0) then return Illegal_Instruction();
  if W == 2 & SEW == 64 & (vtype[altfmt_A] != 0b0 | vtype[altfmt_B] != 0b0) then return Illegal_Instruction();
  if W == 2 & SEW == 16 then return Illegal_Instruction();
  if W == 4 & SEW != 64 then return Illegal_Instruction();
  if W != 1 & W != 2 & W != 4 then return Illegal_Instruction();

  match SEW {
    8  => Illegal_Instruction(),
    16 => execute_ime_fp_gemm(16, W, lambda_nat, LMUL, rm_3b, vtype[altfmt_A], vtype[altfmt_B], vs1, vs2, vd),
    32 => execute_ime_fp_gemm(32, W, lambda_nat, LMUL, rm_3b, vtype[altfmt_A], vtype[altfmt_B], vs1, vs2, vd),
    64 => execute_ime_fp_gemm(64, W, lambda_nat, LMUL, rm_3b, vtype[altfmt_A], vtype[altfmt_B], vs1, vs2, vd),
  }
}

// vfmmacc.vv — non-widening (W=1) floating-point matrix multiply-accumulate.
// A, B, and C are all SEW-bit IEEE floating-point values. `vm=1` selects the
// unscaled form; `vm=0` is the reserved microscaled encoding (not implemented)
// and raises illegal instruction.
union clause instruction = IMEVFMMACCTYPE : (bits(1), vregidx, vregidx, vregidx)

mapping clause encdec = IMEVFMMACCTYPE(vm, vs2, vs1, vd)
  <-> 0b010100 @ vm @ encdec_vreg(vs2) @ encdec_vreg(vs1) @ 0b001 @ encdec_vreg(vd) @ 0b1010111
  when currentlyEnabled(Ext_Zvvfmm)

mapping clause assembly = IMEVFMMACCTYPE(vm, vs2, vs1, vd)
  <-> "vfmmacc.vv" ^ spc() ^ vreg_name(vd) ^ sep() ^ vreg_name(vs1) ^ sep() ^ vreg_name(vs2) ^ maybe_vmask(vm)

function clause execute IMEVFMMACCTYPE(vm, vs2, vs1, vd) =
  execute_ime_fp_mmacc(1, vm, vs2, vs1, vd)

// vfwmmacc.vv — double-widening (W=2) floating-point matrix
// multiply-accumulate. A/B are packed SEW/2 inputs and C accumulates at SEW;
// vm=0 selects microscaling in the draft ISA and is not implemented here.
union clause instruction = IMEVFWMMACCTYPE : (bits(1), vregidx, vregidx, vregidx)

mapping clause encdec = IMEVFWMMACCTYPE(vm, vs2, vs1, vd)
  <-> 0b010101 @ vm @ encdec_vreg(vs2) @ encdec_vreg(vs1) @ 0b001 @ encdec_vreg(vd) @ 0b1010111
  when currentlyEnabled(Ext_Zvvfmm)

mapping clause assembly = IMEVFWMMACCTYPE(vm, vs2, vs1, vd)
  <-> "vfwmmacc.vv" ^ spc() ^ vreg_name(vd) ^ sep() ^ vreg_name(vs1) ^ sep() ^ vreg_name(vs2) ^ maybe_vmask(vm)

function clause execute IMEVFWMMACCTYPE(vm, vs2, vs1, vd) =
  execute_ime_fp_mmacc(2, vm, vs2, vs1, vd)

// vfqmmacc.vv — quad-widening (W=4) floating-point matrix
// multiply-accumulate. This staged implementation accepts only SEW=64 with
// packed FP16/BF16 inputs; vm=0 microscaling remains illegal.
union clause instruction = IMEVFQMMACCTYPE : (bits(1), vregidx, vregidx, vregidx)

mapping clause encdec = IMEVFQMMACCTYPE(vm, vs2, vs1, vd)
  <-> 0b010110 @ vm @ encdec_vreg(vs2) @ encdec_vreg(vs1) @ 0b001 @ encdec_vreg(vd) @ 0b1010111
  when currentlyEnabled(Ext_Zvvfmm)

mapping clause assembly = IMEVFQMMACCTYPE(vm, vs2, vs1, vd)
  <-> "vfqmmacc.vv" ^ spc() ^ vreg_name(vd) ^ sep() ^ vreg_name(vs1) ^ sep() ^ vreg_name(vs2) ^ maybe_vmask(vm)

function clause execute IMEVFQMMACCTYPE(vm, vs2, vs1, vd) =
  execute_ime_fp_mmacc(4, vm, vs2, vs1, vd)
