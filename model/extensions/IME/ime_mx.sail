// =======================================================================================
// Integrated Matrix Extension (IME / Zvvm) microscaled (MX) matrix multiply and the
// floating-point rows that share its exact-arithmetic engine.
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

// This file follows the specification pseudocode (decode_gemm_geometry,
// fp_gemm, fp_scaled_gemm, int_scaled_gemm, read_block_scales) on top of the
// exact engine in ime_fp.sail.
//
// Disclosed FP group profile for every row: G=1, psm=0 (exact partial sum),
// rnd=frm. One group is one sub-dot-product of W products:
//
//   k:   |<- W ->|<- W ->| ...            (one LMUL=1 step = lambda groups)
//   S  = exact sum of the W products of the group
//   C  = round_frm(C + round_frm(S))                                 (vm=1)
//   C  = round_frm(C + fp_mul(blk_scale, round_frm(S)))              (vm=0)
//
// where blk_scale = fp_mul(conv(scale_A), conv(scale_B)) and conv() rounds
// one E8M0 value to the C format under frm (S:1958-2027, S:5097-5124). Each
// of conv(scale_A), conv(scale_B), their product, round_frm(S), and the two
// final multiplies/adds is a separate rounding point with its own flags;
// the scale is never applied to the unrounded exact sum.
//
// v0 scale layout (vm=0): 16-bit element p = m * R + s holds the E8M0 pair
// for row/column m and K block s; bits [7:0] scale A rows, [15:8] scale B
// columns. R = lambda * SEW / 16. Example: SEW=16, lambda=4 -> R=4, so the
// scales of A row 1, block 2 are in the low byte of v0 element 6.

// FP group size G of the disclosed profile.
type ime_fp_grouping : Int = 1

// Width of one (scale_A, scale_B) E8M0 pair in v0.
let IME_SCALE_PAIR_BITS = 16

// E8M0 scale: exponent-only, bias 127, 0xFF is NaN.
let IME_E8M0_BIAS = 127
let IME_E8M0_NAN : bits(8) = 0xFF

// Microscaling block sizes selected by vtype.bs.
let IME_MX_BLOCK_BS0 = 32
let IME_MX_BLOCK_BS1 = 16

// Largest C register group (EMUL_C) allowed by the specification.
let IME_EMUL_C_MAX = 16

// Whether an FP GEMM applies v0 block scales.
enum ime_scaling = { IME_UNSCALED, IME_MX_SCALED }

// Decoded tile geometry for widening factor W (decode_gemm_geometry).
struct ime_gemm_geom = {
  EEW_C  : int,   // accumulator element width (= SEW)
  EEW_A  : int,   // input element width (= SEW / W)
  W      : nat,
  LMUL   : nat,
  lambda : nat,
  K_eff  : nat,   // lambda * W * LMUL
  M      : nat,   // rows of A and C
  N      : nat,   // active columns of B^T and C (from VL)
  N_max  : nat,   // physical C columns (= M)
  EMUL_C : nat,   // registers in the C group
  epr_A  : nat,   // input elements per register
  epr_C  : nat,   // C elements per register
}

// Non-negative int to nat. Callers guarantee x >= 0.
function ime_nat(x : int) -> nat = {
  let 'y = x;
  assert('y >= 0, "IME: negative tile index");
  y
}

// Floor division of non-negative a by positive b.
function ime_div(a : int, b : int) -> nat = {
  assert(b > 0, "IME: zero divisor");
  ime_nat(tdiv_int(a, b))
}

// decode_gemm_geometry: None() when the geometry is illegal.
// Example (VLEN=256): SEW=16, W=2, lambda=4, LMUL=8, VL=96 ->
//   K_eff=64, M=4, N=3, EMUL_C=1.
function ime_gemm_geometry(W : nat) -> option(ime_gemm_geom) = {
  let EEW_C = get_sew();
  let LMUL = ime_lmul_value_nat(get_lmul_pow());
  let lambda = ime_lambda_field_to_nat(vtype[vlambda]);
  if LMUL == 0 | lambda == 0 | W == 0 then return None();
  if not(ime_lambda_supported_for_vsew(vtype[vlambda], vtype[vsew])) then return None();
  if tmod_int(EEW_C, W) != 0 then return None();

  let EEW_A = ime_div(EEW_C, W);
  if not(EEW_A == 4 | EEW_A == 8 | EEW_A == 16 | EEW_A == 32 | EEW_A == 64) then return None();
  let K_eff : nat = lambda * W * LMUL;
  let M = ime_div(vlen, EEW_C * lambda);
  let line : nat = lambda * LMUL;
  let VL = unsigned(vl);

  if tmod_int(M, lambda) != 0 then return None();
  let EMUL_C = ime_div(M, lambda);
  if tmod_int(VL, line) != 0 then return None();
  let N = ime_div(VL, line);
  if N > M then return None();
  if not(EMUL_C == 1 | EMUL_C == 2 | EMUL_C == 4 | EMUL_C == 8 | EMUL_C == IME_EMUL_C_MAX) then return None();

  Some(struct {
    EEW_C = EEW_C,
    EEW_A = EEW_A,
    W = W,
    LMUL = LMUL,
    lambda = lambda,
    K_eff = K_eff,
    M = M,
    N = N,
    N_max = M,
    EMUL_C = EMUL_C,
    epr_A = ime_div(vlen, EEW_A),
    epr_C = ime_div(vlen, EEW_C),
  })
}

// Read input element idx of width EEW_A (4..64), zero-extended.
// 4-bit elements pack two per byte, the even index in the low nibble.
function ime_read_in(EEW_A : int, idx : nat, vs : vregidx) -> bits(64) =
  match EEW_A {
    4 => {
      let byte : bits(8) = read_single_element(8, ime_div(idx, 2), vs);
      zero_extend(64, if tmod_int(idx, 2) == 0 then byte[3 .. 0] else byte[7 .. 4])
    },
    8  => zero_extend(64, read_single_element(8, idx, vs)),
    16 => zero_extend(64, read_single_element(16, idx, vs)),
    32 => zero_extend(64, read_single_element(32, idx, vs)),
    64 => read_single_element(64, idx, vs),
    _  => internal_error(__FILE__, __LINE__, "IME: unsupported input width"),
  }

// Signed integer value of an EEW_A-bit input element (MXINT4/MXINT8).
function ime_read_in_signed(EEW_A : int, idx : nat, vs : vregidx) -> int = {
  let v = ime_read_in(EEW_A, idx, vs);
  if EEW_A == 4 then signed(v[3 .. 0]) else signed(v[7 .. 0])
}

// Read/write a C element of width EEW_C (16, 32, 64), zero-extended to 64.
function ime_read_c(EEW_C : int, idx : nat, vd : vregidx) -> bits(64) =
  match EEW_C {
    16 => zero_extend(64, read_single_element_in_group(16, idx, vd, IME_EMUL_C_MAX)),
    32 => zero_extend(64, read_single_element_in_group(32, idx, vd, IME_EMUL_C_MAX)),
    64 => read_single_element_in_group(64, idx, vd, IME_EMUL_C_MAX),
    _  => internal_error(__FILE__, __LINE__, "IME: unsupported C width"),
  }

function ime_write_c(EEW_C : int, idx : nat, vd : vregidx, v : bits(64)) -> unit =
  match EEW_C {
    16 => write_single_element_in_group(16, idx, vd, v[15 .. 0], IME_EMUL_C_MAX),
    32 => write_single_element_in_group(32, idx, vd, v[31 .. 0], IME_EMUL_C_MAX),
    64 => write_single_element_in_group(64, idx, vd, v, IME_EMUL_C_MAX),
    _  => internal_error(__FILE__, __LINE__, "IME: unsupported C width"),
  }

// read_block_scales (S:1958-2027, S:5097-5124): convert scale_A[i,s] and
// scale_B[j,s] to fmt_C under rm, accruing each conversion's flags, then
// form their product with one fmt_C-rounded multiply. Returns the combined
// block scale's bits, its accrued flags, and whether it is NaN.
//
// The combined block scale is NaN either when either encoded E8M0 value is
// 0xFF (no flags for that case: the NaN scale is detected before any
// conversion), or when the two fmt_C conversions and their multiplication
// produce NaN, for example +0 times +inf when range conversion under rm
// sends one scale to +0 and the other to +inf (S:2008-2027).
function ime_block_scale(g : ime_gemm_geom, fmt_C : ime_fp_fmt, rm : int,
                         i : nat, j : nat, s : nat) -> (bits_fflags, bits(64), bool) = {
  let R = ime_div(g.lambda * g.EEW_C, IME_SCALE_PAIR_BITS);
  let eA : bits(8) = read_single_element(16, i * R + s, zvreg)[7 .. 0];
  let eB : bits(8) = read_single_element(16, j * R + s, zvreg)[15 .. 8];
  if eA == IME_E8M0_NAN | eB == IME_E8M0_NAN then (zeros(), ime_fp_canonical_nan(fmt_C), true)
  else {
    let (flags_a, scale_a) = ime_fp_round(fmt_C, IME_FPX_FIN(0b0, 1, unsigned(eA) - IME_E8M0_BIAS), rm);
    let (flags_b, scale_b) = ime_fp_round(fmt_C, IME_FPX_FIN(0b0, 1, unsigned(eB) - IME_E8M0_BIAS), rm);
    let (flags_mul, blk_scale) = ime_fp_mul(fmt_C, scale_a, scale_b, rm);
    let (decoded, _) = ime_fp_decode(fmt_C, blk_scale);
    (flags_a | flags_b | flags_mul, blk_scale, ime_fpx_is_nan(decoded))
  }
}

// One term A[i,k] * B^T[k,j] of a group: decoded and multiplied exactly.
function ime_fp_group_term(g : ime_gemm_geom, i : nat, j : nat, k : nat,
                           fmt_A : ime_fp_fmt, fmt_B : ime_fp_fmt,
                           vs1 : vregidx, vs2 : vregidx) -> (bits_fflags, ime_fpx) = {
  let a_flat = ime_mat_A_idx(i, k, g.K_eff, g.LMUL, g.lambda * g.W, g.epr_A);
  let b_flat = ime_mat_B_idx(k, j, g.K_eff, g.LMUL, g.lambda * g.W, g.epr_A);
  let (fa, a) = ime_fp_decode_flags(fmt_A, ime_read_in(g.EEW_A, a_flat, vs1));
  let (fb, b) = ime_fp_decode_flags(fmt_B, ime_read_in(g.EEW_A, b_flat, vs2));
  let (fmul, prod) = ime_fpx_mul(a, b);
  (fa | fb | fmul, prod)
}

// fp_group_sum (psm=0): exact sum of A[i,k] * B^T[k,j] for k in [k_lo,
// k_hi]. The sum starts from the first product rather than a literal +0 so
// a single-term group (W=1) keeps that product's sign exactly, including
// -0 (spec S:1532-1533: a W=1 sub-dot-product is the exact product; adding
// it to +0 would turn a -0 product into +0 under round-to-nearest-even).
function ime_fp_group_sum(g : ime_gemm_geom, i : nat, j : nat, k_lo : nat, k_hi : nat,
                          fmt_A : ime_fp_fmt, fmt_B : ime_fp_fmt, rm : int,
                          vs1 : vregidx, vs2 : vregidx) -> (bits_fflags, ime_fpx) = {
  let (flags0, prod0) = ime_fp_group_term(g, i, j, k_lo, fmt_A, fmt_B, vs1, vs2);
  var S : ime_fpx = prod0;
  var flags : bits_fflags = flags0;
  foreach (k from (k_lo + 1) to k_hi) {
    let (fprod, prod) = ime_fp_group_term(g, i, j, k, fmt_A, fmt_B, vs1, vs2);
    let (fadd, sum) = ime_fpx_add(S, prod, rm);
    S = sum;
    flags = flags | fprod | fadd
  };
  (flags, S)
}

// Microscaling block size from vtype.bs.
function ime_mx_block_size() -> nat =
  if vtype[vbs] == 0b1 then IME_MX_BLOCK_BS1 else IME_MX_BLOCK_BS0

// fp_gemm (IME_UNSCALED) and fp_scaled_gemm (IME_MX_SCALED). The unscaled
// form is one block spanning K_eff with no scale multiply; both walk K in
// increasing order: block s, then LMUL=1 step, then group.
function ime_fp_gemm(g : ime_gemm_geom, fmt_A : ime_fp_fmt, fmt_B : ime_fp_fmt, fmt_C : ime_fp_fmt,
                     scaling : ime_scaling, rm : int,
                     vs1 : vregidx, vs2 : vregidx, vd : vregidx) -> unit = {
  let block_size : nat = if scaling == IME_MX_SCALED then ime_mx_block_size() else g.K_eff;
  let S_blocks = ime_div(g.K_eff + block_size - 1, block_size);
  let step_len : nat = g.lambda * g.W;

  foreach (j from 0 to (g.N - 1)) {
    foreach (i from 0 to (g.M - 1)) {
      let c_flat = ime_mat_C_idx(i, j, g.N_max, g.EMUL_C, g.lambda, g.epr_C);
      var acc : bits(64) = ime_read_c(g.EEW_C, c_flat, vd);
      var nan_out : bool = false;
      var elem_flags : bits_fflags = zeros();

      foreach (s from 0 to (S_blocks - 1)) {
        // A NaN combined scale forces C[i,j] to NaN and ends its evaluation.
        if not(nan_out) then {
          let (blk_flags, blk_scale, blk_is_nan) : (bits_fflags, bits(64), bool) =
            if scaling == IME_MX_SCALED then ime_block_scale(g, fmt_C, rm, i, j, s)
            else (zeros(), zeros(), false);
          elem_flags = elem_flags | blk_flags;
          nan_out = blk_is_nan;

          if not(nan_out) then {
            let blk_k_lo : nat = s * block_size;
            let blk_end : nat = blk_k_lo + block_size;
            let blk_k_hi = ime_nat((if blk_end < g.K_eff then blk_end else g.K_eff) - 1);

            // Intersect each LMUL=1 step with the block; walk its groups.
            foreach (step from 0 to (g.LMUL - 1)) {
              let step_k_lo : nat = step * step_len;
              let step_k_hi = ime_nat(step_k_lo + step_len - 1);
              let int_k_lo : nat = if step_k_lo > blk_k_lo then step_k_lo else blk_k_lo;
              let int_k_hi : nat = if step_k_hi < blk_k_hi then step_k_hi else blk_k_hi;

              if int_k_lo <= int_k_hi then {
                let subdot_lo = ime_div(int_k_lo - step_k_lo, g.W);
                let subdot_hi = ime_div(int_k_hi - step_k_lo, g.W);
                foreach (g0 from subdot_lo to subdot_hi by sizeof(ime_fp_grouping)) {
                  let k_lo : nat = step_k_lo + g0 * g.W;
                  let k_hi = ime_nat(k_lo + sizeof(ime_fp_grouping) * g.W - 1);
                  let (flags_sum, S) = ime_fp_group_sum(g, i, j, k_lo, k_hi, fmt_A, fmt_B, rm, vs1, vs2);
                  // S is rounded to fmt_C before scaling: a separate
                  // rounding point from the final accumulation (S:2098-2102).
                  let (flags_round, S_bits) = ime_fp_round(fmt_C, S, rm);
                  let (flags_scale, term) : (bits_fflags, bits(64)) =
                    if scaling == IME_MX_SCALED then ime_fp_mul(fmt_C, blk_scale, S_bits, rm)
                    else (zeros(), S_bits);
                  let (flags_add, new_acc) = ime_fp_add(fmt_C, acc, term, rm);
                  acc = new_acc;
                  elem_flags = elem_flags | flags_sum | flags_round | flags_scale | flags_add
                }
              }
            }
          }
        }
      };

      // One fflags accrual per active C element, even when no flag is set
      // (base-V convention: fflags_dirty_policy relies on it).
      accrue_fflags(elem_flags);
      ime_write_c(g.EEW_C, c_flat, vd, if nan_out then ime_fp_canonical_nan(fmt_C) else acc)
    }
  }
}

// int_scaled_gemm (S:1283-1293, S:5398-5400): per block, the exact signed
// integer dot product is converted to fmt_C under rm (int_to_fp, a separate
// rounding point), multiplied by the block scale in fmt_C, and added to C
// (rounded per frm).
function ime_int_scaled_gemm(g : ime_gemm_geom, fmt_C : ime_fp_fmt, rm : int,
                             vs1 : vregidx, vs2 : vregidx, vd : vregidx) -> unit = {
  let block_size = ime_mx_block_size();
  let S_blocks = ime_div(g.K_eff + block_size - 1, block_size);

  foreach (j from 0 to (g.N - 1)) {
    foreach (i from 0 to (g.M - 1)) {
      let c_flat = ime_mat_C_idx(i, j, g.N_max, g.EMUL_C, g.lambda, g.epr_C);
      var acc : bits(64) = ime_read_c(g.EEW_C, c_flat, vd);
      var nan_out : bool = false;
      var elem_flags : bits_fflags = zeros();

      foreach (s from 0 to (S_blocks - 1)) {
        if not(nan_out) then {
          let (blk_flags, blk_scale, blk_is_nan) = ime_block_scale(g, fmt_C, rm, i, j, s);
          elem_flags = elem_flags | blk_flags;
          nan_out = blk_is_nan;

          if not(nan_out) then {
            let k_lo : nat = s * block_size;
            let blk_end : nat = k_lo + block_size;
            let k_hi = ime_nat((if blk_end < g.K_eff then blk_end else g.K_eff) - 1);
            var dot : int = 0;
            foreach (k from k_lo to k_hi) {
              let a_flat = ime_mat_A_idx(i, k, g.K_eff, g.LMUL, g.lambda * g.W, g.epr_A);
              let b_flat = ime_mat_B_idx(k, j, g.K_eff, g.LMUL, g.lambda * g.W, g.epr_A);
              dot = dot + ime_read_in_signed(g.EEW_A, a_flat, vs1) * ime_read_in_signed(g.EEW_A, b_flat, vs2)
            };
            // int_to_fp(dot, fmt_C, rm): round the exact integer sum to the
            // C format before multiplying by the block scale.
            let (flags_cvt, fp_sum) = ime_fp_round(fmt_C, ime_fpx_of_int(dot), rm);
            let (flags_scale, term) = ime_fp_mul(fmt_C, blk_scale, fp_sum, rm);
            let (flags_add, new_acc) = ime_fp_add(fmt_C, acc, term, rm);
            acc = new_acc;
            elem_flags = elem_flags | flags_cvt | flags_scale | flags_add
          }
        }
      };

      accrue_fflags(elem_flags);
      ime_write_c(g.EEW_C, c_flat, vd, if nan_out then ime_fp_canonical_nan(fmt_C) else acc)
    }
  }
}

// ---------------------------------------------------------------------------
// Encoding-map legality (tbl-fp-encoding-map, tbl-intmx-encoding-map).
// ---------------------------------------------------------------------------

// Base (vm=1) FP row: covered by the coarse Zvvfmm, or implied by its MX
// extension at either block size (Zvvx* implies Zvvo*, Zvvxn* implies Zvvx*).
function ime_fp_base_ext_ok(x : extension, xn : extension) -> bool =
  currentlyEnabled(Ext_Zvvfmm) | currentlyEnabled(x) | currentlyEnabled(xn)

// MX (vm=0) cell: BS=32 needs Zvvx* (or Zvvxn*, which implies it); BS=16
// needs Zvvxn*.
function ime_mx_ext_ok(x : extension, xn : extension) -> bool =
  if vtype[vbs] == 0b0
  then currentlyEnabled(x) | currentlyEnabled(xn)
  else currentlyEnabled(xn)

// vm=1 legality per tbl-fp-encoding-map for the implemented rows. altfmt
// selects the C format; OFP4 inputs require altfmt_A = altfmt_B = 0.
function ime_fp_base_row_ok(W : nat, SEW : int) -> bool = {
  let same_inputs = vtype[altfmt_A] == vtype[altfmt_B];
  let default_inputs = vtype[altfmt_A] == 0b0 & vtype[altfmt_B] == 0b0;
  let bf16_c = vtype[altfmt] == 0b1;
  let zvvfmm = currentlyEnabled(Ext_Zvvfmm);
  match (W, SEW) {
    // FP16 x FP16 -> FP16 and BF16 x BF16 -> BF16 are legal; FP16 x FP16 ->
    // BF16 and BF16 x BF16 -> FP16 are reserved. A mixed FP16/BF16 input
    // pair is legal into either C format (S:7298-7305).
    (1, 16) => zvvfmm & (if same_inputs then vtype[altfmt] == vtype[altfmt_A] else true),
    // FP32 and FP64 inputs ignore altfmt_A/altfmt_B (S:1127, S:1490-1494).
    (1, 32) => not(bf16_c) & zvvfmm,
    (1, 64) => not(bf16_c) & zvvfmm,
    // FP16/BF16 -> FP32, FP32 -> FP64 (altfmt_A/altfmt_B ignored), FP16/BF16 -> FP64.
    (2, 32) => not(bf16_c) & zvvfmm,
    (2, 64) => not(bf16_c) & zvvfmm,
    (4, 64) => not(bf16_c) & zvvfmm,
    // OFP8 -> FP16/BF16, OFP4 -> FP16/BF16, OFP8 -> FP32.
    (2, 16) => if bf16_c then ime_fp_base_ext_ok(Ext_Zvvxofp8bf16mm, Ext_Zvvxnofp8bf16mm)
               else ime_fp_base_ext_ok(Ext_Zvvxofp8fp16mm, Ext_Zvvxnofp8fp16mm),
    (4, 16) => default_inputs &
               (if bf16_c then ime_fp_base_ext_ok(Ext_Zvvxofp4bf16mm, Ext_Zvvxnofp4bf16mm)
                else ime_fp_base_ext_ok(Ext_Zvvxofp4fp16mm, Ext_Zvvxnofp4fp16mm)),
    (4, 32) => not(bf16_c) & ime_fp_base_ext_ok(Ext_Zvvxofp8fp32mm, Ext_Zvvxnofp8fp32mm),
    // OFP4 -> FP32, OFP8 -> FP64.
    (8, 32) => default_inputs & not(bf16_c) & ime_fp_base_ext_ok(Ext_Zvvxofp4fp32mm, Ext_Zvvxnofp4fp32mm),
    (8, 64) => not(bf16_c) & ime_fp_base_ext_ok(Ext_Zvvxofp8fp64mm, Ext_Zvvxnofp8fp64mm),
    _       => false,
  }
}

// vm=0 legality of an FP-input MX row.
function ime_fp_mx_row_ok(W : nat, SEW : int) -> bool = {
  let ofp4_inputs = vtype[altfmt_A] == 0b0 & vtype[altfmt_B] == 0b0;
  let bf16_c = vtype[altfmt] == 0b1;
  match (W, SEW) {
    (2, 16) => if bf16_c then ime_mx_ext_ok(Ext_Zvvxofp8bf16mm, Ext_Zvvxnofp8bf16mm)
               else ime_mx_ext_ok(Ext_Zvvxofp8fp16mm, Ext_Zvvxnofp8fp16mm),
    (4, 16) => ofp4_inputs &
               (if bf16_c then ime_mx_ext_ok(Ext_Zvvxofp4bf16mm, Ext_Zvvxnofp4bf16mm)
                else ime_mx_ext_ok(Ext_Zvvxofp4fp16mm, Ext_Zvvxnofp4fp16mm)),
    (4, 32) => not(bf16_c) & ime_mx_ext_ok(Ext_Zvvxofp8fp32mm, Ext_Zvvxnofp8fp32mm),
    (8, 32) => ofp4_inputs & not(bf16_c) & ime_mx_ext_ok(Ext_Zvvxofp4fp32mm, Ext_Zvvxnofp4fp32mm),
    (8, 64) => not(bf16_c) & ime_mx_ext_ok(Ext_Zvvxofp8fp64mm, Ext_Zvvxnofp8fp64mm),
    _       => false,
  }
}

// vm=0 legality of an integer-input MX row. MXINT inputs are signed, so
// altfmt_A and altfmt_B must be 0.
function ime_int_mx_row_ok(W : nat, SEW : int) -> bool = {
  let signed_inputs = vtype[altfmt_A] == 0b0 & vtype[altfmt_B] == 0b0;
  let bf16_c = vtype[altfmt] == 0b1;
  signed_inputs &
  (match (W, SEW) {
    (2, 16) => if bf16_c then ime_mx_ext_ok(Ext_Zvvxi8bf16mm, Ext_Zvvxni8bf16mm)
               else ime_mx_ext_ok(Ext_Zvvxi8fp16mm, Ext_Zvvxni8fp16mm),
    (4, 16) => if bf16_c then ime_mx_ext_ok(Ext_Zvvxi4bf16mm, Ext_Zvvxni4bf16mm)
               else ime_mx_ext_ok(Ext_Zvvxi4fp16mm, Ext_Zvvxni4fp16mm),
    (4, 32) => not(bf16_c) & ime_mx_ext_ok(Ext_Zvvxi8fp32mm, Ext_Zvvxni8fp32mm),
    (8, 32) => not(bf16_c) & ime_mx_ext_ok(Ext_Zvvxi4fp32mm, Ext_Zvvxni4fp32mm),
    (8, 64) => not(bf16_c) & ime_mx_ext_ok(Ext_Zvvxi8fp64mm, Ext_Zvvxni8fp64mm),
    _       => false,
  })
}

// check_microscaling_legality: SEW * lambda >= 16, and for BS=16
// W * LMUL <= SEW. Also no operand group may overlap v0 (groups are
// aligned, so overlap means a base register of v0).
function ime_mx_operands_ok(g : ime_gemm_geom, vs1 : vregidx, vs2 : vregidx, vd : vregidx) -> bool =
  g.EEW_C * g.lambda >= IME_SCALE_PAIR_BITS &
  not(vtype[vbs] == 0b1 & g.W * g.LMUL > g.EEW_C) &
  vs1 != zvreg & vs2 != zvreg & vd != zvreg

// Register groups: vs1/vs2 aligned to LMUL, vd aligned to EMUL_C. The C
// accumulator group shall not overlap either input group, regardless of VL
// (spec S:551-559); the two input groups may overlap each other (S:561-564).
function ime_gemm_groups_ok(g : ime_gemm_geom, vs1 : vregidx, vs2 : vregidx, vd : vregidx) -> bool =
  valid_reg_group(vs1, ime_group_size_to_pow(g.LMUL)) &
  valid_reg_group(vs2, ime_group_size_to_pow(g.LMUL)) &
  valid_reg_group(vd, ime_group_size_to_pow(g.EMUL_C)) &
  ime_reg_groups_disjoint(vd, g.EMUL_C, vs1, g.LMUL) &
  ime_reg_groups_disjoint(vd, g.EMUL_C, vs2, g.LMUL)

// ---------------------------------------------------------------------------
// Execution entry points.
// ---------------------------------------------------------------------------

// vfmmacc.vv / vfwmmacc.vv / vfqmmacc.vv / vf8wmmacc.vv, vm=1 and vm=0.
function execute_ime_fp_engine(W : nat, vm : bits(1), vs1 : vregidx, vs2 : vregidx, vd : vregidx) -> ExecutionResult = {
  let SEW = get_sew();
  let rm_3b = fcsr[FRM];
  // vstart is VSTART_MANDATORY: the specification requires an illegal
  // instruction exception for any nonzero vstart (S:1272, S:5463). That
  // class ignores num_elem/EMUL_pow; operand A's LMUL-aligned register
  // group is passed only to match illegal_vstart's signature.
  let LMUL_pow = get_lmul_pow();
  if not(valid_vtype()) | illegal_vstart(VSTART_MANDATORY, get_num_elem(LMUL_pow, SEW), LMUL_pow) |
     not(valid_fp_op(SEW, rm_3b))
  then return Illegal_Instruction();

  let g : ime_gemm_geom = match ime_gemm_geometry(W) {
    Some(g) => g,
    None()  => return Illegal_Instruction(),
  };

  let scaling = if vm == 0b0 then IME_MX_SCALED else IME_UNSCALED;
  let row_ok = if scaling == IME_MX_SCALED
               then ime_fp_mx_row_ok(W, SEW) & ime_mx_operands_ok(g, vs1, vs2, vd)
               else ime_fp_base_row_ok(W, SEW);
  if not(row_ok) | not(ime_gemm_groups_ok(g, vs1, vs2, vd)) then return Illegal_Instruction();

  // tbl-fp-encoding-map has one EEW column for both Input A and Input B, so
  // g.EEW_A is also operand B's width; only altfmt_A vs. altfmt_B differs.
  let fmt_A = ime_fp_format_of(g.EEW_A, vtype[altfmt_A]);
  let fmt_B = ime_fp_format_of(g.EEW_A, vtype[altfmt_B]);
  let fmt_C = ime_fp_format_of(g.EEW_C, vtype[altfmt]);
  ime_fp_gemm(g, fmt_A, fmt_B, fmt_C, scaling, unsigned(rm_3b), vs1, vs2, vd);
  set_vstart(zeros());
  RETIRE_SUCCESS
}

// vfwimmacc.vv / vfqimmacc.vv / vf8wimmacc.vv (vm=0 of vwmmacc / vqmmacc /
// v8wmmacc).
function execute_ime_int_mx(W : nat, vs1 : vregidx, vs2 : vregidx, vd : vregidx) -> ExecutionResult = {
  let SEW = get_sew();
  let rm_3b = fcsr[FRM];
  // See the comment in execute_ime_fp_engine: vstart is VSTART_MANDATORY.
  let LMUL_pow = get_lmul_pow();
  if not(valid_vtype()) | illegal_vstart(VSTART_MANDATORY, get_num_elem(LMUL_pow, SEW), LMUL_pow) |
     not(valid_fp_op(SEW, rm_3b))
  then return Illegal_Instruction();

  let g : ime_gemm_geom = match ime_gemm_geometry(W) {
    Some(g) => g,
    None()  => return Illegal_Instruction(),
  };

  if not(ime_int_mx_row_ok(W, SEW)) |
     not(ime_mx_operands_ok(g, vs1, vs2, vd)) |
     not(ime_gemm_groups_ok(g, vs1, vs2, vd))
  then return Illegal_Instruction();

  let fmt_C = ime_fp_format_of(g.EEW_C, vtype[altfmt]);
  ime_int_scaled_gemm(g, fmt_C, unsigned(rm_3b), vs1, vs2, vd);
  set_vstart(zeros());
  RETIRE_SUCCESS
}
