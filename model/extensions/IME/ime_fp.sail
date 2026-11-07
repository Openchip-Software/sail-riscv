// =======================================================================================
// Integrated Matrix Extension (IME / Zvvm) exact floating-point engine.
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

// The specification's FP matrix pseudocode works on an abstract exact value
// (fp_internal) and rounds it to the C accumulator format only at explicit
// points. This file models that value exactly with unbounded integers:
//
//   decode (E2M1/E4M3/E5M2/FP16/BF16/FP32/FP64)
//        |
//        v
//   ime_fpx = NaN | +-inf | (-1)^sign * mant * 2^exp      (exact)
//        |  ime_fpx_mul / ime_fpx_add (exact, NV flags only)
//        v
//   ime_fp_round (FP16/BF16/FP32/FP64, frm, RISC-V flags) -> C bits
//
// Results are IEEE 754 correctly rounded. Underflow uses tininess after
// rounding, as RISC-V does. Every materialized NaN is the canonical NaN.

// FP formats that IME matrix instructions read or write.
enum ime_fp_fmt = {
  IME_E2M1,
  IME_E4M3,
  IME_E5M2,
  IME_FP16,
  IME_BF16,
  IME_FP32,
  IME_FP64,
}

// Exact FP value. A finite value is (-1)^sign * mant * 2^exp with mant >= 0;
// mant = 0 is a signed zero. NaN payloads are not significant.
union ime_fpx = {
  IME_FPX_NAN : unit,
  IME_FPX_INF : bits(1),
  IME_FPX_FIN : (bits(1), int, int),
}

// RISC-V rounding modes (frm encoding).
let IME_RM_RNE = 0
let IME_RM_RTZ = 1
let IME_RM_RDN = 2
let IME_RM_RUP = 3
let IME_RM_RMM = 4

// 2^n for n >= 0.
function ime_pow2(n : int) -> int = shl_int(1, n)

function ime_fmt_ebits(f : ime_fp_fmt) -> int =
  match f {
    IME_E2M1 => 2,
    IME_E4M3 => 4,
    IME_E5M2 => 5,
    IME_FP16 => 5,
    IME_BF16 => 8,
    IME_FP32 => 8,
    IME_FP64 => 11,
  }

function ime_fmt_mbits(f : ime_fp_fmt) -> int =
  match f {
    IME_E2M1 => 1,
    IME_E4M3 => 3,
    IME_E5M2 => 2,
    IME_FP16 => 10,
    IME_BF16 => 7,
    IME_FP32 => 23,
    IME_FP64 => 52,
  }

function ime_fmt_bias(f : ime_fp_fmt) -> int =
  ime_pow2(ime_fmt_ebits(f) - 1) - 1

// Format of an FP element of width EEW; `alt` is altfmt/altfmt_A/altfmt_B.
// Example: (8, 0b1) -> E5M2, (16, 0b1) -> BF16.
function ime_fp_format_of(EEW : int, alt : bits(1)) -> ime_fp_fmt =
  match (EEW, alt) {
    (4, _)     => IME_E2M1,
    (8, 0b0)   => IME_E4M3,
    (8, 0b1)   => IME_E5M2,
    (16, 0b0)  => IME_FP16,
    (16, 0b1)  => IME_BF16,
    (32, _)    => IME_FP32,
    _          => IME_FP64,
  }

// Bits [lo + n - 1 .. lo] of the non-negative integer u.
function ime_field(u : int, lo : int, n : int) -> int =
  shr_int(u, lo) - shl_int(shr_int(u, lo + n), n)

// Number of significant bits of m >= 0. Example: 5 -> 3, 0 -> 0.
function ime_bit_len(m : int) -> int = {
  var n : int = 0;
  var v : int = m;
  while v > 0 do {
    v = shr_int(v, 1);
    n = n + 1
  };
  n
}

function ime_fpx_is_nan(x : ime_fpx) -> bool =
  match x {
    IME_FPX_NAN() => true,
    _             => false,
  }

// Decode raw format bits (zero-extended in v) to an exact value. Returns the
// value and whether it is a signaling NaN (IEEE formats only; OFP NaNs are
// quiet). Examples: FP16 0x3c00 -> (+, 1, 0); E4M3 0x7f -> NaN.
function ime_fp_decode(f : ime_fp_fmt, v : bits(64)) -> (ime_fpx, bool) = {
  let ebits = ime_fmt_ebits(f);
  let mbits = ime_fmt_mbits(f);
  let bias = ime_fmt_bias(f);
  let u = unsigned(v);
  let m = ime_field(u, 0, mbits);
  let e = ime_field(u, mbits, ebits);
  let sign : bits(1) = if ime_field(u, mbits + ebits, 1) == 1 then 0b1 else 0b0;
  let e_all_ones = ime_pow2(ebits) - 1;
  let m_all_ones = ime_pow2(mbits) - 1;
  let ieee_specials = f != IME_E2M1 & f != IME_E4M3;

  // Specials: IEEE-style encodings, and the single E4M3 NaN (S.1111.111).
  if ieee_specials & e == e_all_ones & m == 0 then return (IME_FPX_INF(sign), false);
  if ieee_specials & e == e_all_ones then {
    let quiet = ime_field(m, mbits - 1, 1) == 1;
    let signaling = not(quiet) & f != IME_E5M2;
    return (IME_FPX_NAN(), signaling)
  };
  if f == IME_E4M3 & e == e_all_ones & m == m_all_ones then return (IME_FPX_NAN(), false);

  // Subnormal: m * 2^(1 - bias - mbits). Normal: (2^mbits + m) * 2^(e - bias - mbits).
  if e == 0
  then (IME_FPX_FIN(sign, m, 1 - bias - mbits), false)
  else (IME_FPX_FIN(sign, ime_pow2(mbits) + m, e - bias - mbits), false)
}

// Decode and raise NV for a signaling NaN operand.
function ime_fp_decode_flags(f : ime_fp_fmt, v : bits(64)) -> ime_fpx = {
  let (x, signaling) = ime_fp_decode(f, v);
  if signaling then accrue_fflags(nvFlag());
  x
}

// Exact product. 0 * inf raises NV and yields NaN.
function ime_fpx_mul(a : ime_fpx, b : ime_fpx) -> ime_fpx =
  match (a, b) {
    (IME_FPX_NAN(), _) => IME_FPX_NAN(),
    (_, IME_FPX_NAN()) => IME_FPX_NAN(),
    (IME_FPX_INF(sa), IME_FPX_INF(sb)) => IME_FPX_INF(sa ^ sb),
    (IME_FPX_INF(sa), IME_FPX_FIN(sb, mb, _)) => {
      if mb == 0 then { accrue_fflags(nvFlag()); IME_FPX_NAN() } else IME_FPX_INF(sa ^ sb)
    },
    (IME_FPX_FIN(sa, ma, _), IME_FPX_INF(sb)) => {
      if ma == 0 then { accrue_fflags(nvFlag()); IME_FPX_NAN() } else IME_FPX_INF(sa ^ sb)
    },
    (IME_FPX_FIN(sa, ma, ea), IME_FPX_FIN(sb, mb, eb)) => IME_FPX_FIN(sa ^ sb, ma * mb, ea + eb),
  }

// Exact sum. inf + -inf raises NV and yields NaN. An exact zero sum keeps
// the sign of two equal-signed zeros; otherwise it is +0, or -0 under RDN
// (IEEE 754 6.3). Example: (+3) + (-3) -> +0 (RNE), -0 (RDN).
function ime_fpx_add(a : ime_fpx, b : ime_fpx, rm : int) -> ime_fpx =
  match (a, b) {
    (IME_FPX_NAN(), _) => IME_FPX_NAN(),
    (_, IME_FPX_NAN()) => IME_FPX_NAN(),
    (IME_FPX_INF(sa), IME_FPX_INF(sb)) => {
      if sa == sb then IME_FPX_INF(sa) else { accrue_fflags(nvFlag()); IME_FPX_NAN() }
    },
    (IME_FPX_INF(sa), _) => IME_FPX_INF(sa),
    (_, IME_FPX_INF(sb)) => IME_FPX_INF(sb),
    (IME_FPX_FIN(sa, ma, ea), IME_FPX_FIN(sb, mb, eb)) => {
      let e = if ea < eb then ea else eb;
      let va = shl_int(ma, ea - e);
      let vb = shl_int(mb, eb - e);
      let sum = (if sa == 0b1 then negate(va) else va) + (if sb == 0b1 then negate(vb) else vb);
      if sum > 0 then IME_FPX_FIN(0b0, sum, e)
      else if sum < 0 then IME_FPX_FIN(0b1, negate(sum), e)
      else if ma == 0 & mb == 0 & sa == sb then IME_FPX_FIN(sa, 0, e)
      else if rm == IME_RM_RDN then IME_FPX_FIN(0b1, 0, e)
      else IME_FPX_FIN(0b0, 0, e)
    },
  }

// Round m * 2^e (m > 0, sign s) to an integer multiple of 2^q under rm.
// Returns (r, inexact) with the rounded value r * 2^q.
function ime_round_int(s : bits(1), m : int, e : int, q : int, rm : int) -> (int, bool) = {
  if e >= q then return (shl_int(m, e - q), false);
  let shift = q - e;
  let r0 = shr_int(m, shift);
  let rem = m - shl_int(r0, shift);
  let half = shl_int(1, shift - 1);
  let r0_odd = ime_field(r0, 0, 1) == 1;
  let round_up : bool =
    if rm == IME_RM_RNE then rem > half | (rem == half & r0_odd)
    else if rm == IME_RM_RDN then s == 0b1 & rem > 0
    else if rm == IME_RM_RUP then s == 0b0 & rem > 0
    else if rm == IME_RM_RMM then rem >= half
    else false;
  (if round_up then r0 + 1 else r0, rem != 0)
}

// Assemble an IEEE-style encoding from sign, biased exponent, and fraction.
function ime_fp_pack(f : ime_fp_fmt, s : bits(1), biased : int, frac : int) -> bits(64) = {
  let mbits = ime_fmt_mbits(f);
  let ebits = ime_fmt_ebits(f);
  let sign_val = if s == 0b1 then shl_int(1, mbits + ebits) else 0;
  to_bits_unsafe(64, sign_val + shl_int(biased, mbits) + frac)
}

// Canonical NaN: sign 0, exponent all ones, fraction MSB set.
// Examples: FP16 0x7e00, BF16 0x7fc0, FP32 0x7fc00000.
function ime_fp_canonical_nan(f : ime_fp_fmt) -> bits(64) = {
  let mbits = ime_fmt_mbits(f);
  ime_fp_pack(f, 0b0, ime_pow2(ime_fmt_ebits(f)) - 1, shl_int(1, mbits - 1))
}

// Round an exact value to IEEE format f (FP16/BF16/FP32/FP64) under rm and
// accrue NX/UF/OF. Returns the encoding zero-extended to 64 bits.
function ime_fp_round(f : ime_fp_fmt, x : ime_fpx, rm : int) -> bits(64) = {
  let mbits = ime_fmt_mbits(f);
  let bias = ime_fmt_bias(f);
  let emax_field = ime_pow2(ime_fmt_ebits(f)) - 1;
  let emin = 1 - bias;

  match x {
    IME_FPX_NAN() => ime_fp_canonical_nan(f),
    IME_FPX_INF(s) => ime_fp_pack(f, s, emax_field, 0),
    IME_FPX_FIN(s, m, e) => {
      if m == 0 then return ime_fp_pack(f, s, 0, 0);

      // Unbiased exponent of the leading one: value in [2^E, 2^(E+1)).
      let E = ime_bit_len(m) - 1 + e;

      // Tininess after rounding: round to mbits+1 bits with unbounded range.
      let (r_unb, _) = ime_round_int(s, m, e, E - mbits, rm);
      let E_after = if r_unb == ime_pow2(mbits + 1) then E + 1 else E;
      let tiny = E_after < emin;

      // Round to the format's precision; subnormals share quantum 2^(emin - mbits).
      var q : int = (if E > emin then E else emin) - mbits;
      let (r0, inexact) = ime_round_int(s, m, e, q, rm);
      var r : int = r0;
      if r == ime_pow2(mbits + 1) then {
        r = shr_int(r, 1);
        q = q + 1
      };

      let normal = r >= ime_pow2(mbits);
      let biased = if normal then q + mbits + bias else 0;
      let frac = if normal then r - ime_pow2(mbits) else r;

      // Overflow: inf or the largest finite value, depending on rm and sign.
      if biased >= emax_field then {
        accrue_fflags(ofFlag() | nxFlag());
        let to_inf = rm == IME_RM_RNE | rm == IME_RM_RMM |
                     (rm == IME_RM_RUP & s == 0b0) | (rm == IME_RM_RDN & s == 0b1);
        return if to_inf
               then ime_fp_pack(f, s, emax_field, 0)
               else ime_fp_pack(f, s, emax_field - 1, ime_pow2(mbits) - 1)
      };

      if inexact then accrue_fflags(if tiny then ufFlag() | nxFlag() else nxFlag());
      ime_fp_pack(f, s, biased, frac)
    },
  }
}

// fp_add / fp_mul of the specification: operands and result in format f.
function ime_fp_add(f : ime_fp_fmt, a : bits(64), b : bits(64), rm : int) -> bits(64) =
  ime_fp_round(f, ime_fpx_add(ime_fp_decode_flags(f, a), ime_fp_decode_flags(f, b), rm), rm)

function ime_fp_mul(f : ime_fp_fmt, a : bits(64), b : bits(64), rm : int) -> bits(64) =
  ime_fp_round(f, ime_fpx_mul(ime_fp_decode_flags(f, a), ime_fp_decode_flags(f, b)), rm)

// Exact value of an integer. Example: -3 -> (-, 3, 0).
function ime_fpx_of_int(v : int) -> ime_fpx =
  if v < 0 then IME_FPX_FIN(0b1, negate(v), 0) else IME_FPX_FIN(0b0, v, 0)
