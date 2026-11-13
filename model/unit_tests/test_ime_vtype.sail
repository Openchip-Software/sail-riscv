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
  // Default unit-test config is rv64d_v256_e64 (VLEN=256). A nonzero lambda
  // is permissible for a given SEW only when
  // EMUL_C = VLEN / (SEW * lambda^2) is an integer in {1,2,4,8,16}:
  // e8 (0b000) -> {2,4}, e16 (0b001) -> {1,2,4}, e32 (0b010) -> {1,2},
  // e64 (0b011) -> {1,2}.
  assert(ime_lambda_supported_for_vsew(0b010, 0b010));
  assert(not(ime_lambda_supported_for_vsew(0b100, 0b010)));
  assert(ime_largest_supported_lambda_for_vsew(0b010) == 0b010);

  // requested = 000 is a preserve-or-initialize request: a current lambda
  // that is still supported after a SEW change is retained ...
  assert(ime_select_vtype_lambda(0b000, 0b001, 0b010) == 0b001);
  // ... and a current lambda that is no longer supported is replaced by the
  // largest value supported for the new SEW.
  assert(ime_select_vtype_lambda(0b000, 0b100, 0b010) == 0b010);

  // A nonzero request for a supported value is kept.
  assert(ime_select_vtype_lambda(0b010, 0b001, 0b010) == 0b010);
  // A request of lambda=8 at e32 is unsupported ({1,2} only); the largest
  // supported value <= the request (lambda=2) is selected.
  assert(ime_select_vtype_lambda(0b100, 0b001, 0b010) == 0b010);
  // A request of lambda=1 at e8 ({2,4} only) is unsupported and no supported
  // value is <= the request; the smallest supported value (lambda=2) is
  // selected.
  assert(ime_select_vtype_lambda(0b001, 0b001, 0b000) == 0b010);
}

$[test]
function test_ime_vtype_high_fields_are_addressable() -> unit = {
  let saved_vtype = vtype;
  vtype = [Mk_Vtype(zeros()) with
    vlambda = 0b010,
    vbs = 0b1,
    altfmt_A = 0b1,
    altfmt_B = 0b0,
    altfmt = 0b1,
  ];

  assert(vtype[vlambda] == 0b010);
  assert(vtype[vbs] == 0b1);
  assert(vtype[altfmt_A] == 0b1);
  assert(vtype[altfmt_B] == 0b0);
  // altfmt (Zvfbfa position) is vtype bit 8 and selects the C format.
  assert(vtype[altfmt] == 0b1);
  assert(vtype.bits[8] == bitone);

  vtype = saved_vtype;
}
