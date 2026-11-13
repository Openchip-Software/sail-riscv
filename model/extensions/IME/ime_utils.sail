// =======================================================================================
// Integrated Matrix Extension (IME / Zvvm) shared helpers.
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

// Any individual floating-point computational extension (tbl-extensions,
// the 18 Zvvmm-family members whose currentlyEnabled clause also accepts
// Ext_Zvvfmm). A decode guard that accepts this function alongside
// Ext_Zvvfmm therefore decodes an encoding whose cell belongs to exactly one
// member extension even when Zvvfmm itself is not enabled. The execute
// function still rejects the encoding when the enabled member does not
// cover that (W, SEW) cell (ime_fp_base_row_ok in ime_mx.sail).
function ime_fp_base_any_enabled() -> bool =
  currentlyEnabled(Ext_Zvvbf16mm) |
  currentlyEnabled(Ext_Zvvbf16fp32mm) |
  currentlyEnabled(Ext_Zvvbf16fp64mm) |
  currentlyEnabled(Ext_Zvvfp16mm) |
  currentlyEnabled(Ext_Zvvfp16fp32mm) |
  currentlyEnabled(Ext_Zvvfp16fp64mm) |
  currentlyEnabled(Ext_Zvvfp32mm) |
  currentlyEnabled(Ext_Zvvfp32fp64mm) |
  currentlyEnabled(Ext_Zvvfp64mm) |
  currentlyEnabled(Ext_Zvvofp8mm) |
  currentlyEnabled(Ext_Zvvofp8bf16mm) |
  currentlyEnabled(Ext_Zvvofp8fp16mm) |
  currentlyEnabled(Ext_Zvvofp8fp32mm) |
  currentlyEnabled(Ext_Zvvofp8fp64mm) |
  currentlyEnabled(Ext_Zvvofp4bf16mm) |
  currentlyEnabled(Ext_Zvvofp4fp16mm) |
  currentlyEnabled(Ext_Zvvofp4fp32mm) |
  currentlyEnabled(Ext_Zvvofp4ofp8mm)

// Any floating-point-input microscaling (Zvvxofp*/Zvvxnofp*) extension.
// Ext_Zvvxofp4ofp8mm and Ext_Zvvxnofp4ofp8mm name an OFP8 accumulator row
// that ime_fp_mx_row_ok does not recognize yet (deferred to block C3), so
// enabling only one of the two still traps in execute_ime_fp_engine. They
// are listed here anyway, because the decode guard has to accept the
// encoding for execute_ime_fp_engine to reach that per-cell check.
function ime_fp_mx_any_enabled() -> bool =
  currentlyEnabled(Ext_Zvvxofp4fp16mm) |
  currentlyEnabled(Ext_Zvvxnofp4fp16mm) |
  currentlyEnabled(Ext_Zvvxofp4bf16mm) |
  currentlyEnabled(Ext_Zvvxnofp4bf16mm) |
  currentlyEnabled(Ext_Zvvxofp8fp16mm) |
  currentlyEnabled(Ext_Zvvxnofp8fp16mm) |
  currentlyEnabled(Ext_Zvvxofp8bf16mm) |
  currentlyEnabled(Ext_Zvvxnofp8bf16mm) |
  currentlyEnabled(Ext_Zvvxofp8fp32mm) |
  currentlyEnabled(Ext_Zvvxnofp8fp32mm) |
  currentlyEnabled(Ext_Zvvxofp4fp32mm) |
  currentlyEnabled(Ext_Zvvxnofp4fp32mm) |
  currentlyEnabled(Ext_Zvvxofp8fp64mm) |
  currentlyEnabled(Ext_Zvvxnofp8fp64mm) |
  currentlyEnabled(Ext_Zvvxofp4ofp8mm) |
  currentlyEnabled(Ext_Zvvxnofp4ofp8mm)

// Any individual integer computational extension (tbl-extensions, the 13
// Zvvmm-family members whose currentlyEnabled clause also accepts
// Ext_Zvvmm). See ime_fp_base_any_enabled for why a decode guard can accept
// this function instead of resolving the specific member: the per-cell
// check lives in execute_ime_int_mmacc (ime_int_row_ok in ime_mx.sail).
function ime_int_base_any_enabled() -> bool =
  currentlyEnabled(Ext_Zvvi4i8mm) |
  currentlyEnabled(Ext_Zvvi4i16mm) |
  currentlyEnabled(Ext_Zvvi4i32mm) |
  currentlyEnabled(Ext_Zvvi8mm) |
  currentlyEnabled(Ext_Zvvi8i16mm) |
  currentlyEnabled(Ext_Zvvi8i32mm) |
  currentlyEnabled(Ext_Zvvi8i64mm) |
  currentlyEnabled(Ext_Zvvi16mm) |
  currentlyEnabled(Ext_Zvvi16i32mm) |
  currentlyEnabled(Ext_Zvvi16i64mm) |
  currentlyEnabled(Ext_Zvvi32mm) |
  currentlyEnabled(Ext_Zvvi32i64mm) |
  currentlyEnabled(Ext_Zvvi64mm)

// Any integer-input microscaling (Zvvxi*/Zvvxni*) extension.
function ime_int_mx_any_enabled() -> bool =
  currentlyEnabled(Ext_Zvvxi8fp16mm) |
  currentlyEnabled(Ext_Zvvxni8fp16mm) |
  currentlyEnabled(Ext_Zvvxi8bf16mm) |
  currentlyEnabled(Ext_Zvvxni8bf16mm) |
  currentlyEnabled(Ext_Zvvxi8fp32mm) |
  currentlyEnabled(Ext_Zvvxni8fp32mm) |
  currentlyEnabled(Ext_Zvvxi8fp64mm) |
  currentlyEnabled(Ext_Zvvxni8fp64mm) |
  currentlyEnabled(Ext_Zvvxi4fp16mm) |
  currentlyEnabled(Ext_Zvvxni4fp16mm) |
  currentlyEnabled(Ext_Zvvxi4bf16mm) |
  currentlyEnabled(Ext_Zvvxni4bf16mm) |
  currentlyEnabled(Ext_Zvvxi4fp32mm) |
  currentlyEnabled(Ext_Zvvxni4fp32mm)

function ime_vtype_fields_enabled() -> bool =
  currentlyEnabled(Ext_Zvvmm) |
  currentlyEnabled(Ext_Zvvmtls) |
  currentlyEnabled(Ext_Zvvmttls) |
  currentlyEnabled(Ext_Zvvfmm) |
  ime_fp_base_any_enabled() |
  ime_fp_mx_any_enabled() |
  ime_int_base_any_enabled() |
  ime_int_mx_any_enabled()

function ime_lambda_field_to_value(field : bits(3)) -> int =
  match field {
    0b000 => 0,
    0b001 => 1,
    0b010 => 2,
    0b011 => 4,
    0b100 => 8,
    0b101 => 16,
    0b110 => 32,
    0b111 => 64,
  }

function ime_lambda_value_to_field(value : int) -> bits(3) =
  if value == 1 then 0b001
  else if value == 2 then 0b010
  else if value == 4 then 0b011
  else if value == 8 then 0b100
  else if value == 16 then 0b101
  else if value == 32 then 0b110
  else if value == 64 then 0b111
  else 0b000

// EMUL_C in {1, 2, 4, 8, 16}.
function ime_group_size_legal(group : nat) -> bool =
  group == 1 | group == 2 | group == 4 | group == 8 | group == 16

// A nonzero lambda is architecturally permissible for (VLEN, SEW) only when
// EMUL_C = VLEN / (SEW * lambda^2) is an integer in {1, 2, 4, 8, 16}
// (spec "Selected lambda" section). The model supports every permissible
// lambda, so "supported" and "permissible" coincide here.
function ime_lambda_supported_value_for_vsew(lambda_value : int, sew : bits(3)) -> bool = {
  let sew_bits = 2 ^ (unsigned(sew) + 3);
  if lambda_value <= 0 then false
  else {
    let denom = sew_bits * lambda_value * lambda_value;
    if denom <= 0 then false
    else (vlen % denom == 0) & ime_group_size_legal(vlen / denom)
  }
}

function ime_lambda_supported_for_vsew(field : bits(3), sew : bits(3)) -> bool =
  ime_lambda_supported_value_for_vsew(ime_lambda_field_to_value(field), sew)

// Largest supported nonzero lambda for (VLEN, SEW), or 0b000 when (VLEN, SEW)
// is outside the IME-legal configuration domain (no nonzero lambda is
// permissible, not even lambda = 1).
function ime_largest_supported_lambda_for_vsew(sew : bits(3)) -> bits(3) =
  if ime_lambda_supported_value_for_vsew(64, sew) then 0b111
  else if ime_lambda_supported_value_for_vsew(32, sew) then 0b110
  else if ime_lambda_supported_value_for_vsew(16, sew) then 0b101
  else if ime_lambda_supported_value_for_vsew(8, sew) then 0b100
  else if ime_lambda_supported_value_for_vsew(4, sew) then 0b011
  else if ime_lambda_supported_value_for_vsew(2, sew) then 0b010
  else if ime_lambda_supported_value_for_vsew(1, sew) then 0b001
  else 0b000

// Smallest supported nonzero lambda for (VLEN, SEW), or 0b000 outside the
// IME-legal configuration domain.
function ime_smallest_supported_lambda_for_vsew(sew : bits(3)) -> bits(3) =
  if ime_lambda_supported_value_for_vsew(1, sew) then 0b001
  else if ime_lambda_supported_value_for_vsew(2, sew) then 0b010
  else if ime_lambda_supported_value_for_vsew(4, sew) then 0b011
  else if ime_lambda_supported_value_for_vsew(8, sew) then 0b100
  else if ime_lambda_supported_value_for_vsew(16, sew) then 0b101
  else if ime_lambda_supported_value_for_vsew(32, sew) then 0b110
  else if ime_lambda_supported_value_for_vsew(64, sew) then 0b111
  else 0b000

// Largest supported nonzero lambda that is <= requested_value, or 0b000 when
// no supported value is that small.
function ime_largest_supported_lambda_leq(requested_value : int, sew : bits(3)) -> bits(3) =
  if requested_value >= 64 & ime_lambda_supported_value_for_vsew(64, sew) then 0b111
  else if requested_value >= 32 & ime_lambda_supported_value_for_vsew(32, sew) then 0b110
  else if requested_value >= 16 & ime_lambda_supported_value_for_vsew(16, sew) then 0b101
  else if requested_value >= 8 & ime_lambda_supported_value_for_vsew(8, sew) then 0b100
  else if requested_value >= 4 & ime_lambda_supported_value_for_vsew(4, sew) then 0b011
  else if requested_value >= 2 & ime_lambda_supported_value_for_vsew(2, sew) then 0b010
  else if requested_value >= 1 & ime_lambda_supported_value_for_vsew(1, sew) then 0b001
  else 0b000

// Lambda write rules (spec "lambda write rules"):
// - A write of 000 is a preserve-or-initialize request: retain `current` if
//   it is still supported for the resulting (VLEN, SEW); otherwise select
//   the largest supported nonzero lambda, or 000 outside the IME-legal
//   domain.
// - A nonzero write requests that exact value: retain it if supported;
//   otherwise select the largest supported value <= the request, or, if
//   none is that small, the smallest supported value; or 000 outside the
//   IME-legal domain.
function ime_select_vtype_lambda(requested : bits(3), current : bits(3), sew : bits(3)) -> bits(3) =
  if requested == 0b000 then {
    if current != 0b000 & ime_lambda_supported_for_vsew(current, sew)
    then current
    else ime_largest_supported_lambda_for_vsew(sew)
  } else if ime_lambda_supported_for_vsew(requested, sew) then requested
  else {
    let leq = ime_largest_supported_lambda_leq(ime_lambda_field_to_value(requested), sew);
    if leq != 0b000 then leq else ime_smallest_supported_lambda_for_vsew(sew)
  }

function ime_vtype_fields_clear(vt : Vtype) -> bool =
  vt[vlambda] == 0b000 &
  vt[vbs] == 0b0 &
  vt[altfmt_A] == 0b0 &
  vt[altfmt_B] == 0b0 &
  vt[altfmt] == 0b0

function ime_vtype_fields_legal(vt : Vtype) -> bool =
  ime_vtype_fields_enabled() | ime_vtype_fields_clear(vt)

// vsetvli/vsetivli zimm[10:8]. zimm[8] is altfmt (Zvfbfa position), which
// selects the C accumulator format and is legal only when IME is enabled.
// zimm[10:9] stay reserved. Example: 0b001 sets altfmt=1 (BF16 C at SEW=16).
function ime_vtr_legal(vtr : bits(3)) -> bool =
  vtr[2 .. 1] == 0b00 & (vtr[0] == bitzero | ime_vtype_fields_enabled())

function ime_lambda_field_to_nat(field : bits(3)) -> nat =
  match field {
    0b000 => 0,
    0b001 => 1,
    0b010 => 2,
    0b011 => 4,
    0b100 => 8,
    0b101 => 16,
    0b110 => 32,
    0b111 => 64,
  }

function ime_lmul_value_nat(LMUL_pow : int) -> nat =
  if LMUL_pow == 0 then 1
  else if LMUL_pow == 1 then 2
  else if LMUL_pow == 2 then 4
  else if LMUL_pow == 3 then 8
  else 0

function ime_group_size_to_pow(group : nat) -> int =
  if group == 1 then 0
  else if group == 2 then 1
  else if group == 4 then 2
  else if group == 8 then 3
  else 4

// True when the architectural vector-register ranges [a, a + a_regs) and
// [b, b + b_regs) name no register in common. Register-group bases are not
// reduced modulo 32 here: IME register groups are aligned and at most 16
// registers wide, so a legal group never wraps past v31.
function ime_reg_groups_disjoint(a : vregidx, a_regs : nat, b : vregidx, b_regs : nat) -> bool = {
  let a0 : nat = unsigned(vregidx_bits(a));
  let b0 : nat = unsigned(vregidx_bits(b));
  a0 + a_regs <= b0 | b0 + b_regs <= a0
}

// Map a sequential tile element index to the flat architectural element
// index within a vector register group. The index and elems_per_reg use the
// element width of the vector-register view being indexed. Widening A/B
// callers therefore pass lambda * W and the narrow input epr.
function ime_tile_reg_idx(i : nat, group : nat, lambda_value : nat, elems_per_reg : nat) -> nat = {
  let linesize : nat = lambda_value * group;
  assert(linesize > 0);
  assert(lambda_value > 0);
  let line : nat = i / linesize;
  let elem_in_line : nat = i % linesize;
  let regoff : nat = elem_in_line / lambda_value;
  let elementoff : nat = line * lambda_value + elem_in_line % lambda_value;
  regoff * elems_per_reg + elementoff
}

// Memory element offset for the order-preserving tile traversal. The active
// tile is walked row-major across `linesize = lambda * LMUL` storage elements
// per row: row = i / linesize, col = i % linesize, offset = row * LD + col.
function ime_tile_ordered_mem_off(i : nat, linesize : nat, LD : nat) -> nat = {
  assert(linesize > 0);
  let row = i / linesize;
  let col = i % linesize;
  row * LD + col
}

// Memory element offset for the transposing tile traversal. The active tile
// has `cols = lambda * LMUL` storage-element columns; the flat index i
// selects (row, col) row-major but addresses the transpose:
// offset = col * LD + row. For a 2x2 tile with LD=4 this yields the offsets
// [0, 4, 1, 5] for flat indices [0, 1, 2, 3].
function ime_tile_transposed_mem_off(i : nat, cols : nat, LD : nat) -> nat = {
  assert(cols > 0);
  let row = i / cols;
  let col = i % cols;
  col * LD + row
}

function ime_mat_A_idx(i : nat, k : nat, K_eff : nat, LMUL : nat, lambda_value : nat, epr : nat) -> nat =
  ime_tile_reg_idx(i * K_eff + k, LMUL, lambda_value, epr)

function ime_mat_B_idx(k : nat, j : nat, K_eff : nat, LMUL : nat, lambda_value : nat, epr : nat) -> nat =
  ime_tile_reg_idx(j * K_eff + k, LMUL, lambda_value, epr)

function ime_mat_C_idx(i : nat, j : nat, N_max : nat, EMUL_C : nat, lambda_value : nat, epr : nat) -> nat =
  ime_tile_reg_idx(i * N_max + j, EMUL_C, lambda_value, epr)

// A supported integer logical input element width EEW = SEW / W. Includes the
// sub-byte Int4 width, which is packed two-per-byte in the storage element.
function ime_int_eew_supported(eew : nat) -> bool =
  eew == 4 | eew == 8 | eew == 16 | eew == 32 | eew == 64

// Packed-input mapping for widening GEMM. A logical K-dimension index `k`
// (0..K_eff-1) addresses one of `W` narrow elements packed into a single
// `SEW`-bit storage element. The storage column selects which `SEW`-bit
// storage element along the K direction, and the lane selects the subelement
// within it. With W=1 this reduces to storage_col=k, lane=0.
function ime_packed_storage_col(k : nat, W : nat) -> nat = {
  assert(W > 0);
  k / W
}

function ime_packed_lane(k : nat, W : nat) -> nat = {
  assert(W > 0);
  k % W
}

// Extract the value of logical subelement `lane` (0-based, little-endian lane
// order) of width `eew` bits from an `sew`-bit storage element holding W=sew/eew
// packed elements. Element k occupies bits [k*eew + eew-1 : k*eew], so for EEW=4
// the even element is the lower nibble and the odd element the upper nibble,
// matching the IME packing definition. `storage` is the unsigned value of the
// `SEW`-bit storage element. With `is_signed` the eew-bit field is sign-extended,
// otherwise zero-extended. For W=1 (lane=0, eew=sew) this reduces to a plain
// signed/unsigned read of the whole storage element.
function ime_packed_subelement_value(storage : nat, lane : nat, eew : nat, is_signed : bool) -> int = {
  assert(eew > 0);
  let modulus = 2 ^ eew;
  let field = (storage / (2 ^ (lane * eew))) % modulus;
  if is_signed & field >= modulus / 2 then field - modulus else field
}
