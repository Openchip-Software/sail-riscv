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

function clause currentlyEnabled(Ext_Zvvfmm) =
  hartSupports(Ext_Zvvfmm) & currentlyEnabled(Ext_Zve32x)

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
