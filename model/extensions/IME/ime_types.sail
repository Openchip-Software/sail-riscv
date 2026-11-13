// =======================================================================================
// Integrated Matrix Extension (IME / Zvvm) draft extension plumbing.
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

function clause currentlyEnabled(Ext_Zvvmm) =
  hartSupports(Ext_Zvvmm) & currentlyEnabled(Ext_Zve32x)

function clause currentlyEnabled(Ext_Zvvmtls) =
  hartSupports(Ext_Zvvmtls) & currentlyEnabled(Ext_Zve32x)

function clause currentlyEnabled(Ext_Zvvmttls) =
  hartSupports(Ext_Zvvmttls) & currentlyEnabled(Ext_Zve32x)

// Zvvfmm reads vtype.altfmt_A/altfmt_B and frm and writes fflags, so it
// requires Zve32f (tbl-extensions S:808-843), not just Zve32x. Zve32f
// requires Ext_F, which adds the mstatus.FS check.
function clause currentlyEnabled(Ext_Zvvfmm) =
  hartSupports(Ext_Zvvfmm) & currentlyEnabled(Ext_Zve32f)

// The FP-input microscaling extensions (Zvvx*/Zvvxn*, tbl-mx-extensions
// S:7164-7206) require Zve32f for the same reason as Zvvfmm. The
// integer-input microscaling extensions (Zvvxi*/Zvvxni*) accumulate into a
// floating-point C and read frm, so they require Zve32f too, although the
// MX table names no dependency for them (AMB-06). Each *fp64mm extension
// requires Zve64d instead, which implies Zve32f.
function clause currentlyEnabled(Ext_Zvvxi4bf16mm) =
  hartSupports(Ext_Zvvxi4bf16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxi4fp16mm) =
  hartSupports(Ext_Zvvxi4fp16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxi4fp32mm) =
  hartSupports(Ext_Zvvxi4fp32mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxi8bf16mm) =
  hartSupports(Ext_Zvvxi8bf16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxi8fp16mm) =
  hartSupports(Ext_Zvvxi8fp16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxi8fp32mm) =
  hartSupports(Ext_Zvvxi8fp32mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxi8fp64mm) =
  hartSupports(Ext_Zvvxi8fp64mm) & currentlyEnabled(Ext_Zve64d)

function clause currentlyEnabled(Ext_Zvvxni4bf16mm) =
  hartSupports(Ext_Zvvxni4bf16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxni4fp16mm) =
  hartSupports(Ext_Zvvxni4fp16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxni4fp32mm) =
  hartSupports(Ext_Zvvxni4fp32mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxni8bf16mm) =
  hartSupports(Ext_Zvvxni8bf16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxni8fp16mm) =
  hartSupports(Ext_Zvvxni8fp16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxni8fp32mm) =
  hartSupports(Ext_Zvvxni8fp32mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxni8fp64mm) =
  hartSupports(Ext_Zvvxni8fp64mm) & currentlyEnabled(Ext_Zve64d)

function clause currentlyEnabled(Ext_Zvvxnofp4bf16mm) =
  hartSupports(Ext_Zvvxnofp4bf16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxnofp4fp16mm) =
  hartSupports(Ext_Zvvxnofp4fp16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxnofp4fp32mm) =
  hartSupports(Ext_Zvvxnofp4fp32mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxnofp8bf16mm) =
  hartSupports(Ext_Zvvxnofp8bf16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxnofp8fp16mm) =
  hartSupports(Ext_Zvvxnofp8fp16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxnofp8fp32mm) =
  hartSupports(Ext_Zvvxnofp8fp32mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxnofp8fp64mm) =
  hartSupports(Ext_Zvvxnofp8fp64mm) & currentlyEnabled(Ext_Zve64d)

function clause currentlyEnabled(Ext_Zvvxofp4bf16mm) =
  hartSupports(Ext_Zvvxofp4bf16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxofp4fp16mm) =
  hartSupports(Ext_Zvvxofp4fp16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxofp4fp32mm) =
  hartSupports(Ext_Zvvxofp4fp32mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxofp8bf16mm) =
  hartSupports(Ext_Zvvxofp8bf16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxofp8fp16mm) =
  hartSupports(Ext_Zvvxofp8fp16mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxofp8fp32mm) =
  hartSupports(Ext_Zvvxofp8fp32mm) & currentlyEnabled(Ext_Zve32f)

function clause currentlyEnabled(Ext_Zvvxofp8fp64mm) =
  hartSupports(Ext_Zvvxofp8fp64mm) & currentlyEnabled(Ext_Zve64d)

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
