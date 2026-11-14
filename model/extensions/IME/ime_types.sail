// =======================================================================================
// Integrated Matrix Extension (IME / Zvvm) draft extension plumbing.
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

// Largest C register group (EMUL_C) allowed by the specification. Used by
// both the microscaled engine in ime_mx.sail and the unscaled integer
// multiply-accumulate path in ime_mem_insts.sail.
let IME_EMUL_C_MAX = 16

// Zvvm family-level, individual computational, and microscaling
// extension dependencies, sorted alphabetically. Family-level flags
// (Zvvmm, Zvvfmm) imply every extension in their family; a BS=16 (xn)
// microscaling extension implies its matching BS=32 (x) extension; an
// FP-input (x) microscaling extension implies its base extension (the
// integer-input microscaling extensions imply no base extension, per
// tbl-mx-extensions S:7158-7160).
function clause currentlyEnabled(Ext_Zvvbf16fp32mm) =
  (hartSupports(Ext_Zvvbf16fp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvbf16fp64mm) =
  (hartSupports(Ext_Zvvbf16fp64mm) & currentlyEnabled(Ext_Zve64d)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvbf16mm) =
  (hartSupports(Ext_Zvvbf16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvfmm) =
  (hartSupports(Ext_Zvvfmm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvfp16fp32mm) =
  (hartSupports(Ext_Zvvfp16fp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvfp16fp64mm) =
  (hartSupports(Ext_Zvvfp16fp64mm) & currentlyEnabled(Ext_Zve64d)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvfp16mm) =
  (hartSupports(Ext_Zvvfp16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvfp32fp64mm) =
  (hartSupports(Ext_Zvvfp32fp64mm) & currentlyEnabled(Ext_Zve64d)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvfp32mm) =
  (hartSupports(Ext_Zvvfp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvfp64mm) =
  (hartSupports(Ext_Zvvfp64mm) & currentlyEnabled(Ext_Zve64d)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvi16i32mm) =
  (hartSupports(Ext_Zvvi16i32mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi16i64mm) =
  (hartSupports(Ext_Zvvi16i64mm) & currentlyEnabled(Ext_Zve64x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi16mm) =
  (hartSupports(Ext_Zvvi16mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi32i64mm) =
  (hartSupports(Ext_Zvvi32i64mm) & currentlyEnabled(Ext_Zve64x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi32mm) =
  (hartSupports(Ext_Zvvi32mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi4i16mm) =
  (hartSupports(Ext_Zvvi4i16mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi4i32mm) =
  (hartSupports(Ext_Zvvi4i32mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi4i8mm) =
  (hartSupports(Ext_Zvvi4i8mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi64mm) =
  (hartSupports(Ext_Zvvi64mm) & currentlyEnabled(Ext_Zve64x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi8i16mm) =
  (hartSupports(Ext_Zvvi8i16mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi8i32mm) =
  (hartSupports(Ext_Zvvi8i32mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi8i64mm) =
  (hartSupports(Ext_Zvvi8i64mm) & currentlyEnabled(Ext_Zve64x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvi8mm) =
  (hartSupports(Ext_Zvvi8mm) & currentlyEnabled(Ext_Zve32x)) |
  currentlyEnabled(Ext_Zvvmm)

function clause currentlyEnabled(Ext_Zvvmm) =
  (hartSupports(Ext_Zvvmm) & currentlyEnabled(Ext_Zve32x))

function clause currentlyEnabled(Ext_Zvvmtls) =
  (hartSupports(Ext_Zvvmtls) & currentlyEnabled(Ext_Zve32x))

function clause currentlyEnabled(Ext_Zvvmttls) =
  (hartSupports(Ext_Zvvmttls) & currentlyEnabled(Ext_Zve32x))

function clause currentlyEnabled(Ext_Zvvofp4bf16mm) =
  (hartSupports(Ext_Zvvofp4bf16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm) |
  currentlyEnabled(Ext_Zvvxofp4bf16mm)

function clause currentlyEnabled(Ext_Zvvofp4fp16mm) =
  (hartSupports(Ext_Zvvofp4fp16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm) |
  currentlyEnabled(Ext_Zvvxofp4fp16mm)

function clause currentlyEnabled(Ext_Zvvofp4fp32mm) =
  (hartSupports(Ext_Zvvofp4fp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm) |
  currentlyEnabled(Ext_Zvvxofp4fp32mm)

function clause currentlyEnabled(Ext_Zvvofp4ofp8mm) =
  (hartSupports(Ext_Zvvofp4ofp8mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm) |
  currentlyEnabled(Ext_Zvvxofp4ofp8mm)

function clause currentlyEnabled(Ext_Zvvofp8bf16mm) =
  (hartSupports(Ext_Zvvofp8bf16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm) |
  currentlyEnabled(Ext_Zvvxofp8bf16mm)

function clause currentlyEnabled(Ext_Zvvofp8fp16mm) =
  (hartSupports(Ext_Zvvofp8fp16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm) |
  currentlyEnabled(Ext_Zvvxofp8fp16mm)

function clause currentlyEnabled(Ext_Zvvofp8fp32mm) =
  (hartSupports(Ext_Zvvofp8fp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm) |
  currentlyEnabled(Ext_Zvvxofp8fp32mm)

function clause currentlyEnabled(Ext_Zvvofp8fp64mm) =
  (hartSupports(Ext_Zvvofp8fp64mm) & currentlyEnabled(Ext_Zve64d)) |
  currentlyEnabled(Ext_Zvvfmm) |
  currentlyEnabled(Ext_Zvvxofp8fp64mm)

function clause currentlyEnabled(Ext_Zvvofp8mm) =
  (hartSupports(Ext_Zvvofp8mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvfmm)

function clause currentlyEnabled(Ext_Zvvxi4bf16mm) =
  (hartSupports(Ext_Zvvxi4bf16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxni4bf16mm)

function clause currentlyEnabled(Ext_Zvvxi4fp16mm) =
  (hartSupports(Ext_Zvvxi4fp16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxni4fp16mm)

function clause currentlyEnabled(Ext_Zvvxi4fp32mm) =
  (hartSupports(Ext_Zvvxi4fp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxni4fp32mm)

function clause currentlyEnabled(Ext_Zvvxi8bf16mm) =
  (hartSupports(Ext_Zvvxi8bf16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxni8bf16mm)

function clause currentlyEnabled(Ext_Zvvxi8fp16mm) =
  (hartSupports(Ext_Zvvxi8fp16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxni8fp16mm)

function clause currentlyEnabled(Ext_Zvvxi8fp32mm) =
  (hartSupports(Ext_Zvvxi8fp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxni8fp32mm)

function clause currentlyEnabled(Ext_Zvvxi8fp64mm) =
  (hartSupports(Ext_Zvvxi8fp64mm) & currentlyEnabled(Ext_Zve64d)) |
  currentlyEnabled(Ext_Zvvxni8fp64mm)

function clause currentlyEnabled(Ext_Zvvxni4bf16mm) =
  (hartSupports(Ext_Zvvxni4bf16mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxni4fp16mm) =
  (hartSupports(Ext_Zvvxni4fp16mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxni4fp32mm) =
  (hartSupports(Ext_Zvvxni4fp32mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxni8bf16mm) =
  (hartSupports(Ext_Zvvxni8bf16mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxni8fp16mm) =
  (hartSupports(Ext_Zvvxni8fp16mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxni8fp32mm) =
  (hartSupports(Ext_Zvvxni8fp32mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxni8fp64mm) =
  (hartSupports(Ext_Zvvxni8fp64mm) & currentlyEnabled(Ext_Zve64d))

function clause currentlyEnabled(Ext_Zvvxnofp4bf16mm) =
  (hartSupports(Ext_Zvvxnofp4bf16mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxnofp4fp16mm) =
  (hartSupports(Ext_Zvvxnofp4fp16mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxnofp4fp32mm) =
  (hartSupports(Ext_Zvvxnofp4fp32mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxnofp4ofp8mm) =
  (hartSupports(Ext_Zvvxnofp4ofp8mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxnofp8bf16mm) =
  (hartSupports(Ext_Zvvxnofp8bf16mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxnofp8fp16mm) =
  (hartSupports(Ext_Zvvxnofp8fp16mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxnofp8fp32mm) =
  (hartSupports(Ext_Zvvxnofp8fp32mm) & currentlyEnabled(Ext_Zve32f))

function clause currentlyEnabled(Ext_Zvvxnofp8fp64mm) =
  (hartSupports(Ext_Zvvxnofp8fp64mm) & currentlyEnabled(Ext_Zve64d))

function clause currentlyEnabled(Ext_Zvvxofp4bf16mm) =
  (hartSupports(Ext_Zvvxofp4bf16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxnofp4bf16mm)

function clause currentlyEnabled(Ext_Zvvxofp4fp16mm) =
  (hartSupports(Ext_Zvvxofp4fp16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxnofp4fp16mm)

function clause currentlyEnabled(Ext_Zvvxofp4fp32mm) =
  (hartSupports(Ext_Zvvxofp4fp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxnofp4fp32mm)

function clause currentlyEnabled(Ext_Zvvxofp4ofp8mm) =
  (hartSupports(Ext_Zvvxofp4ofp8mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxnofp4ofp8mm)

function clause currentlyEnabled(Ext_Zvvxofp8bf16mm) =
  (hartSupports(Ext_Zvvxofp8bf16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxnofp8bf16mm)

function clause currentlyEnabled(Ext_Zvvxofp8fp16mm) =
  (hartSupports(Ext_Zvvxofp8fp16mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxnofp8fp16mm)

function clause currentlyEnabled(Ext_Zvvxofp8fp32mm) =
  (hartSupports(Ext_Zvvxofp8fp32mm) & currentlyEnabled(Ext_Zve32f)) |
  currentlyEnabled(Ext_Zvvxnofp8fp32mm)

function clause currentlyEnabled(Ext_Zvvxofp8fp64mm) =
  (hartSupports(Ext_Zvvxofp8fp64mm) & currentlyEnabled(Ext_Zve64d)) |
  currentlyEnabled(Ext_Zvvxnofp8fp64mm)

// IME tile load/store mode field (bits[2:1] of imm7).
enum ime_tile_mode = { IME_TILE_ORDERED, IME_TILE_TRANSPOSED, IME_TILE_RESERVED_2, IME_TILE_RESERVED_3 }

mapping encdec_ime_tile_mode : ime_tile_mode <-> bits(2) = {
  IME_TILE_ORDERED     <-> 0b00,
  IME_TILE_TRANSPOSED  <-> 0b01,
  IME_TILE_RESERVED_2  <-> 0b10,
  IME_TILE_RESERVED_3  <-> 0b11,
}

// Optional immediate lambda operand of the tile load/store assembly syntax.
// An omitted operand (lambda field 000) selects vtype.lambda.
mapping maybe_ime_lambda : string <-> bits(3) = {
  ""             <-> 0b000,
  sep() ^ "L1"   <-> 0b001,
  sep() ^ "L2"   <-> 0b010,
  sep() ^ "L4"   <-> 0b011,
  sep() ^ "L8"   <-> 0b100,
  sep() ^ "L16"  <-> 0b101,
  sep() ^ "L32"  <-> 0b110,
  sep() ^ "L64"  <-> 0b111,
}

// Optional microscaling operand of the widening FP matrix multiply assembly
// syntax. vm=0 selects MX-scaled operands with scales in v0.
mapping maybe_ime_vscale : string <-> bits(1) = {
  ""                 <-> 0b1,
  sep() ^ "v0.scale" <-> 0b0,
}
