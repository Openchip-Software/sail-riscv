// IME vtype helper regression tests.
$[test]
function test_ime_lambda_encoding_helpers() -> unit = {
  assert(ime_lambda_field_to_value(0b000) == 0);
  assert(ime_lambda_field_to_value(0b001) == 1);
  assert(ime_lambda_field_to_value(0b010) == 2);
  assert(ime_lambda_field_to_value(0b100) == 8);
  assert(ime_lambda_field_to_value(0b111) == 64);

  assert(ime_lambda_value_to_field(1) == 0b001);
  assert(ime_lambda_value_to_field(8) == 0b100);
  assert(ime_lambda_value_to_field(64) == 0b111);
}

$[test]
function test_ime_lambda_warl_selection_for_default_vlen() -> unit = {
  // Default unit-test config is rv64d_v256_e64.  For SEW=32 the largest
  // lambda that leaves at least one row in the tile is 8; lambda=16 is too large.
  assert(ime_lambda_supported_for_vsew(0b100, 0b010));
  assert(not(ime_lambda_supported_for_vsew(0b101, 0b010)));
  assert(ime_select_vtype_lambda(0b000, 0b010) == 0b100);
  assert(ime_select_vtype_lambda(0b010, 0b010) == 0b010);
  assert(ime_select_vtype_lambda(0b101, 0b010) == 0b100);
}

$[test]
function test_ime_vtype_high_fields_are_addressable() -> unit = {
  let saved_vtype = vtype;
  vtype = [Mk_Vtype(zeros()) with
    vlambda = 0b010,
    vbs = 0b1,
    altfmt_A = 0b1,
    altfmt_B = 0b0,
  ];

  assert(vtype[vlambda] == 0b010);
  assert(vtype[vbs] == 0b1);
  assert(vtype[altfmt_A] == 0b1);
  assert(vtype[altfmt_B] == 0b0);

  vtype = saved_vtype;
}
