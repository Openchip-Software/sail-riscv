// IME exact FP engine regression tests: cross-check the engine's IEEE add
// and multiply (result bits and fflags) against SoftFloat for FP16, FP32,
// and FP64 under all five rounding modes.

// 64-bit LCG (Knuth MMIX constants) for reproducible operands.
function ime_test_lcg(x : bits(64)) -> bits(64) =
  to_bits_unsafe(64, unsigned(x) * 6364136223846793005 + 1442695040888963407)

// Operand of format f from random bits r. The exponent class cycles through
// any encoding (incl. NaN/inf), a narrow band around 1.0 (so additions
// cancel and round), and the subnormal/minimum-normal range (underflow).
function ime_test_operand(f : ime_fp_fmt, r : bits(64), n : int) -> bits(64) = {
  let ebits = ime_fmt_ebits(f);
  let mbits = ime_fmt_mbits(f);
  let u = unsigned(r);
  let sign : bits(1) = if ime_field(u, 63, 1) == 1 then 0b1 else 0b0;
  let frac = ime_field(u, 0, mbits);
  let class = tmod_int(n, 3);
  let biased =
    if class == 0 then ime_field(u, mbits, ebits)
    else if class == 1 then ime_fmt_bias(f) - 2 + ime_field(u, 40, 2)
    else ime_field(u, 40, 1);
  ime_fp_pack(f, sign, biased, frac)
}

enum ime_test_op = { IME_TEST_ADD, IME_TEST_MUL }

// Run the engine op; return (fflags, result). ime_fp_mul/ime_fp_add report
// their flags directly and do not accrue them, so no fcsr save/restore is
// needed here.
function ime_test_engine(f : ime_fp_fmt, op : ime_test_op, a : bits(64), b : bits(64), rm : int) -> (bits(5), bits(64)) =
  if op == IME_TEST_MUL then ime_fp_mul(f, a, b, rm) else ime_fp_add(f, a, b, rm)

$[test]
function test_ime_fp_vs_softfloat() -> unit = {
  let saved_fcsr = fcsr;
  var seed : bits(64) = 0x0123456789abcdef;

  foreach (n from 0 to 2999) {
    seed = ime_test_lcg(seed);
    let ra = seed;
    seed = ime_test_lcg(seed);
    let rb = seed;
    let rm = tmod_int(n, 5);
    let rm_bits : bits(3) = to_bits_unsafe(3, rm);
    let op = if tmod_int(n, 2) == 1 then IME_TEST_MUL else IME_TEST_ADD;
    let is_mul = op == IME_TEST_MUL;

    let a16 = ime_test_operand(IME_FP16, ra, n);
    let b16 = ime_test_operand(IME_FP16, rb, n + 1);
    let (fl16, r16) = ime_test_engine(IME_FP16, op, a16, b16, rm);
    let (sf_fl16, sf_r16) = if is_mul then riscv_f16Mul(rm_bits, a16[15 .. 0], b16[15 .. 0])
                            else riscv_f16Add(rm_bits, a16[15 .. 0], b16[15 .. 0]);
    assert(r16[15 .. 0] == sf_r16 & fl16 == sf_fl16, "IME engine FP16 mismatch vs SoftFloat");

    let a32 = ime_test_operand(IME_FP32, ra, n);
    let b32 = ime_test_operand(IME_FP32, rb, n + 1);
    let (fl32, r32) = ime_test_engine(IME_FP32, op, a32, b32, rm);
    let (sf_fl32, sf_r32) = if is_mul then riscv_f32Mul(rm_bits, a32[31 .. 0], b32[31 .. 0])
                            else riscv_f32Add(rm_bits, a32[31 .. 0], b32[31 .. 0]);
    assert(r32[31 .. 0] == sf_r32 & fl32 == sf_fl32, "IME engine FP32 mismatch vs SoftFloat");

    let a64 = ime_test_operand(IME_FP64, ra, n);
    let b64 = ime_test_operand(IME_FP64, rb, n + 1);
    let (fl64, r64) = ime_test_engine(IME_FP64, op, a64, b64, rm);
    let (sf_fl64, sf_r64) = if is_mul then riscv_f64Mul(rm_bits, a64, b64)
                            else riscv_f64Add(rm_bits, a64, b64);
    assert(r64 == sf_r64 & fl64 == sf_fl64, "IME engine FP64 mismatch vs SoftFloat")
  };

  fcsr = saved_fcsr
}
