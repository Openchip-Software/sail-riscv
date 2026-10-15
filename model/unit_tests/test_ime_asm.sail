// IME assembly mapping regression tests.
$[test]
function test_ime_tile_ls_assembly() -> unit = {
  let a0 = encdec_reg(0b01010);
  let a1 = encdec_reg(0b01011);
  let v4 = encdec_vreg(0b00100);
  let v16 = encdec_vreg(0b10000);
  // Register names depend on the use_abi_names config.
  let mem = "(" ^ reg_name(a0) ^ "), " ^ reg_name(a1);

  // Lambda field 000 omits the immediate lambda and selects vtype.lambda.
  assert(assembly(VMTLTYPE(0b000, IME_TILE_ORDERED, 0b1, a1, a0, v16)) == "vmtl.v v16, " ^ mem);
  assert(assembly(VMTLTYPE(0b010, IME_TILE_TRANSPOSED, 0b0, a1, a0, v16)) == "vmttl.v v16, " ^ mem ^ ", L2, v0.t");
  assert(assembly(VMTSTYPE(0b001, IME_TILE_ORDERED, 0b1, a1, a0, v4)) == "vmts.v v4, " ^ mem ^ ", L1");
  assert(assembly(VMTSTYPE(0b111, IME_TILE_TRANSPOSED, 0b0, a1, a0, v4)) == "vmtts.v v4, " ^ mem ^ ", L64, v0.t");
}

$[test]
function test_ime_mmacc_assembly() -> unit = {
  let v8 = encdec_vreg(0b01000);
  let v2 = encdec_vreg(0b00010);
  let v4 = encdec_vreg(0b00100);

  assert(assembly(IMEVMMACCTYPE(0b1, v4, v2, v8)) == "vmmacc.vv v8, v2, v4");
  assert(assembly(IMEVFMMACCTYPE(0b1, v4, v2, v8)) == "vfmmacc.vv v8, v2, v4");

  // vm=0 selects the integer-input microscaled forms.
  assert(assembly(IMEVWMMACCTYPE(0b1, v4, v2, v8)) == "vwmmacc.vv v8, v2, v4");
  assert(assembly(IMEVWMMACCTYPE(0b0, v4, v2, v8)) == "vfwimmacc.vv v8, v2, v4, v0.scale");
  assert(assembly(IMEVQMMACCTYPE(0b0, v4, v2, v8)) == "vfqimmacc.vv v8, v2, v4, v0.scale");
  assert(assembly(IMEV8WMMACCTYPE(0b0, v4, v2, v8)) == "vf8wimmacc.vv v8, v2, v4, v0.scale");

  // vm=0 selects MX-scaled operands.
  assert(assembly(IMEVFWMMACCTYPE(0b1, v4, v2, v8)) == "vfwmmacc.vv v8, v2, v4");
  assert(assembly(IMEVFWMMACCTYPE(0b0, v4, v2, v8)) == "vfwmmacc.vv v8, v2, v4, v0.scale");
  assert(assembly(IMEVFQMMACCTYPE(0b0, v4, v2, v8)) == "vfqmmacc.vv v8, v2, v4, v0.scale");
}
