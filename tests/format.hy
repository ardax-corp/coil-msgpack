// Round-trip and error-position tests for Msgpack::standard.
// Test bodies use assert's string error; MessagePack Results are matched, not `?`.
use msgpack::{Msgpack, MsgpackValue, MsgpackError};
use string::{from_bytes, to_bytes};

const TWO_31: int = 2147483648;
const U32_MAX: int = 4294967295;
const TWO_32: int = 4294967296;
const I64_MAX: int = 9223372036854775807;

fn codec() -> Msgpack {
    return Msgpack::standard();
}

fn hex_val(byte c) -> int {
    if c >= "0" && c <= "9" {
        return (c as int) - ("0" as byte as int);
    }
    if c >= "a" && c <= "f" {
        return (c as int) - ("a" as byte as int) + 10;
    }
    if c >= "A" && c <= "F" {
        return (c as int) - ("A" as byte as int) + 10;
    }
    return -1;
}

fn from_hex(string s) -> Vec<byte> {
    let b = to_bytes(s);
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < len(b) {
        let hi = hex_val(b[i]);
        let lo = hex_val(b[i + 1]);
        let v = hi * 16 + lo;
        out.push(v as byte);
        i = i + 2;
    }
    return out;
}

fn hex_digit(int n) -> byte {
    let ten: int = 10;
    let zero = "0" as byte as int;
    let aye = "a" as byte as int;
    if n < ten {
        return (zero + n) as byte;
    }
    return (aye + (n - ten)) as byte;
}

fn to_hex(Vec<byte> buf) -> string {
    let out: Vec<byte> = Vec::with_capacity(len(buf) * 2);
    let i = 0;
    while i < len(buf) {
        let v = buf[i] as int;
        out.push(hex_digit(v / 16));
        out.push(hex_digit(v % 16));
        i = i + 1;
    }
    return match from_bytes(out) {
        Result::Ok(s) => s,
        Result::Err(_) => panic "hex",
    };
}

fn must_decode(Vec<byte> raw) -> MsgpackValue {
    return match codec().decode(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "decode failed",
    };
}

fn must_decode_hex(string h) -> MsgpackValue {
    return must_decode(from_hex(h));
}

fn enc_hex(MsgpackValue v) -> string {
    return match codec().encode(v) {
        Result::Ok(b) => to_hex(b),
        Result::Err(_) => panic "encode failed",
    };
}

fn must_append(MsgpackValue arr, MsgpackValue child) {
    match arr.append(child) {
        Result::Ok(_) => (),
        Result::Err(_) => panic "append",
    };
}

fn must_put(MsgpackValue map, MsgpackValue key, MsgpackValue val) {
    match map.put(key, val) {
        Result::Ok(_) => (),
        Result::Err(_) => panic "put",
    };
}

fn is_invalid_at(Result<MsgpackValue, MsgpackError> r, int line, int column) -> bool {
    return match r {
        Result::Ok(_) => false,
        Result::Err(e) => match e {
            MsgpackError::Invalid { line: ln, column: col } => ln == line && col == column,
            default => false,
        },
    };
}

fn is_number(Result<MsgpackValue, MsgpackError> r) -> bool {
    return match r {
        Result::Ok(_) => false,
        Result::Err(e) => match e {
            MsgpackError::Number { line, column } => line >= 1 && column >= 1,
            default => false,
        },
    };
}

fn is_utf8(Result<MsgpackValue, MsgpackError> r) -> bool {
    return match r {
        Result::Ok(_) => false,
        Result::Err(e) => match e {
            MsgpackError::Utf8 { line, column } => line >= 1 && column >= 1,
            default => false,
        },
    };
}

fn encode_is_utf8(Result<string, MsgpackError> r) -> bool {
    return match r {
        Result::Ok(_) => false,
        Result::Err(e) => match e {
            MsgpackError::Utf8 { line, column } => line >= 1 && column >= 1,
            default => false,
        },
    };
}

fn encode_is_number(Result<Vec<byte>, MsgpackError> r) -> bool {
    return match r {
        Result::Ok(_) => false,
        Result::Err(e) => match e {
            MsgpackError::Number { line, column } => line >= 1 && column >= 1,
            default => false,
        },
    };
}

fn i64_min() -> int {
    return 0 - I64_MAX - 1;
}

test("nil bool") {
    let n = must_decode_hex("c0");
    assert(n.is_nil(), "nil")?;
    assert(enc_hex(MsgpackValue::nil()) == "c0")?;
    let t = must_decode_hex("c3");
    assert(t.is_bool() && t.flag, "true")?;
    let f = must_decode_hex("c2");
    assert(f.is_bool() && !f.flag, "false")?;
    assert(enc_hex(MsgpackValue::from_bool(true)) == "c3")?;
    assert(enc_hex(MsgpackValue::from_bool(false)) == "c2")?;
}

test("positive and negative fixint") {
    let z = must_decode_hex("00");
    assert(z.is_int() && z.i == 0, "0")?;
    assert(enc_hex(z) == "00")?;
    let p = must_decode_hex("7f");
    assert(p.is_int() && p.i == 127, "127")?;
    assert(enc_hex(p) == "7f")?;
    let n = must_decode_hex("ff");
    assert(n.is_int() && n.i == (0 - 1), "-1")?;
    assert(enc_hex(n) == "ff")?;
    let m = must_decode_hex("e0");
    assert(m.is_int() && m.i == (0 - 32), "-32")?;
    assert(enc_hex(m) == "e0")?;
    assert(enc_hex(MsgpackValue::from_int(7)) == "07")?;
}

test("wider integers round-trip to smallest") {
    assert(must_decode_hex("cc80").i == 128, "uint8")?;
    assert(enc_hex(MsgpackValue::from_int(128)) == "cc80")?;
    assert(must_decode_hex("ccff").i == 255, "255")?;
    assert(enc_hex(MsgpackValue::from_int(255)) == "ccff")?;
    assert(must_decode_hex("cd0100").i == 256, "uint16")?;
    assert(enc_hex(MsgpackValue::from_int(256)) == "cd0100")?;
    assert(must_decode_hex("cdffff").i == 65535, "65535")?;
    assert(enc_hex(MsgpackValue::from_int(65535)) == "cdffff")?;
    assert(must_decode_hex("ce00010000").i == 65536, "uint32")?;
    assert(enc_hex(MsgpackValue::from_int(65536)) == "ce00010000")?;
    assert(must_decode_hex("ceffffffff").i == U32_MAX, "u32 max")?;
    assert(enc_hex(MsgpackValue::from_int(U32_MAX)) == "ceffffffff")?;
    assert(must_decode_hex("cf0000000100000000").i == TWO_32, "uint64")?;
    assert(enc_hex(MsgpackValue::from_int(TWO_32)) == "cf0000000100000000")?;
    let max = must_decode_hex("cf7fffffffffffffff");
    assert(max.i == I64_MAX, "i64 max")?;
    assert(enc_hex(max) == "cf7fffffffffffffff")?;
}

test("signed integer families") {
    assert(must_decode_hex("d0df").i == (0 - 33), "int8 -33")?;
    assert(enc_hex(MsgpackValue::from_int(0 - 33)) == "d0df")?;
    assert(must_decode_hex("d080").i == (0 - 128), "int8 min")?;
    assert(enc_hex(MsgpackValue::from_int(0 - 128)) == "d080")?;
    assert(must_decode_hex("d1ff7f").i == (0 - 129), "int16")?;
    assert(enc_hex(MsgpackValue::from_int(0 - 129)) == "d1ff7f")?;
    assert(must_decode_hex("d18000").i == (0 - 32768), "int16 min")?;
    assert(enc_hex(MsgpackValue::from_int(0 - 32768)) == "d18000")?;
    assert(must_decode_hex("d2ffff7fff").i == (0 - 32769), "int32")?;
    assert(enc_hex(MsgpackValue::from_int(0 - 32769)) == "d2ffff7fff")?;
    assert(must_decode_hex("d280000000").i == (0 - TWO_31), "int32 min")?;
    assert(enc_hex(MsgpackValue::from_int(0 - TWO_31)) == "d280000000")?;
    let below = 0 - TWO_31 - 1;
    assert(must_decode_hex("d3ffffffff7fffffff").i == below, "int64")?;
    assert(enc_hex(MsgpackValue::from_int(below)) == "d3ffffffff7fffffff")?;
    let min = i64_min();
    assert(must_decode_hex("d38000000000000000").i == min, "i64 min")?;
    assert(enc_hex(MsgpackValue::from_int(min)) == "d38000000000000000")?;
}

test("wide integer forms shrink on encode") {
    assert(must_decode_hex("cd0001").i == 1, "uint16 1")?;
    assert(enc_hex(must_decode_hex("cd0001")) == "01")?;
    assert(must_decode_hex("d3ffffffffffffffff").i == (0 - 1), "int64 -1")?;
    assert(enc_hex(must_decode_hex("d3ffffffffffffffff")) == "ff")?;
}

test("uint64 above i64 max is number") {
    assert(is_number(codec().decode(from_hex("cf8000000000000000"))), "2^63")?;
    assert(is_number(codec().decode(from_hex("cfffffffffffffffff"))), "u64 max")?;
}

test("float64 known values") {
    let a = must_decode_hex("cb3ff8000000000000");
    assert(a.is_float() && a.f > 1.4 && a.f < 1.6, "1.5")?;
    assert(enc_hex(a) == "cb3ff8000000000000")?;
    assert(enc_hex(MsgpackValue::from_float(1.5)) == "cb3ff8000000000000")?;
    let two = must_decode_hex("cb4000000000000000");
    assert(two.f > 1.9 && two.f < 2.1, "2")?;
    assert(enc_hex(two) == "cb4000000000000000")?;
    let neg = must_decode_hex("cbbff0000000000000");
    assert(neg.f < -0.9 && neg.f > -1.1, "-1")?;
    assert(enc_hex(neg) == "cbbff0000000000000")?;
    assert(enc_hex(must_decode_hex("cb0000000000000000")) == "cb0000000000000000")?;
    assert(enc_hex(must_decode_hex("cb8000000000000000")) == "cb8000000000000000")?;
}

test("float extremes round-trip bits") {
    assert(enc_hex(must_decode_hex("cb0010000000000000")) == "cb0010000000000000")?;
    assert(enc_hex(must_decode_hex("cb0000000000000001")) == "cb0000000000000001")?;
    assert(enc_hex(must_decode_hex("cb7fefffffffffffff")) == "cb7fefffffffffffff")?;
    let inf = must_decode_hex("cb7ff0000000000000");
    assert(inf.is_float() && inf.i == 1 && !inf.flag, "+inf")?;
    assert(enc_hex(inf) == "cb7ff0000000000000")?;
    let ninf = must_decode_hex("cbfff0000000000000");
    assert(ninf.i == 1 && ninf.flag, "-inf")?;
    assert(enc_hex(ninf) == "cbfff0000000000000")?;
    let nan = must_decode_hex("cb7ff8000000000001");
    assert(nan.i == 2 && !nan.flag, "nan")?;
    assert(enc_hex(nan) == "cb7ff8000000000000")?;
}

test("float32 widens to float64") {
    let v = must_decode_hex("ca3fc00000");
    assert(v.is_float() && v.f > 1.4 && v.f < 1.6, "f32 1.5")?;
    assert(enc_hex(v) == "cb3ff8000000000000")?;
    assert(enc_hex(must_decode_hex("ca00000000")) == "cb0000000000000000")?;
    assert(enc_hex(must_decode_hex("ca80000000")) == "cb8000000000000000")?;
    assert(enc_hex(must_decode_hex("ca7f800000")) == "cb7ff0000000000000")?;
    assert(enc_hex(must_decode_hex("caff800000")) == "cbfff0000000000000")?;
}

test("strings") {
    let hi = must_decode_hex("a26869");
    assert(hi.is_string() && hi.s == "hi", "fixstr")?;
    assert(enc_hex(hi) == "a26869")?;
    assert(enc_hex(MsgpackValue::from_string("hi")) == "a26869")?;
    assert(enc_hex(must_decode_hex("d9026869")) == "a26869")?;
    let empty = must_decode_hex("a0");
    assert(empty.is_string() && empty.s == "", "empty")?;
    assert(enc_hex(empty) == "a0")?;
    let e = must_decode_hex("a2c3a9");
    let raw = to_bytes(e.s);
    assert(len(raw) == 2 && (raw[0] as int) == 195 && (raw[1] as int) == 169, "utf8")?;
}

test("binary and ext") {
    let b = must_decode_hex("c403010203");
    assert(b.is_bin() && b.bin_len() == 3, "bin8")?;
    let raw = b.bytes();
    assert((raw[0] as int) == 1 && (raw[2] as int) == 3, "bytes")?;
    assert(enc_hex(b) == "c403010203")?;
    assert(enc_hex(must_decode_hex("c50001ab")) == "c401ab")?;
    let e = must_decode_hex("d405ab");
    assert(e.is_ext() && e.ext_type() == 5 && e.bin_len() == 1, "fixext1")?;
    assert(enc_hex(e) == "d405ab")?;
    let ts = must_decode_hex("d4ff01");
    assert(ts.ext_type() == (0 - 1), "type -1")?;
    assert(enc_hex(ts) == "d4ff01")?;
    assert(enc_hex(must_decode_hex("c7010203")) == "d40203")?;
    let wide = MsgpackValue::from_ext(128, from_hex("01"));
    assert(encode_is_number(codec().encode(wide)), "ext type")?;
}

test("array and map values") {
    let a = must_decode_hex("9301c3c0");
    assert(a.is_array() && a.array_len() == 3, "len")?;
    assert(a.child(0).is_int() && a.child(0).i == 1, "0")?;
    assert(a.child(1).is_bool() && a.child(1).flag, "1")?;
    assert(a.child(2).is_nil(), "2")?;
    assert(enc_hex(a) == "9301c3c0")?;
    let empty = must_decode_hex("90");
    assert(empty.is_array() && empty.array_len() == 0, "empty arr")?;
    assert(enc_hex(empty) == "90")?;
    assert(enc_hex(must_decode_hex("dc0000")) == "90")?;
    let m = must_decode_hex("81a1619301c3c0");
    assert(m.is_map() && m.map_len() == 1, "map")?;
    assert(m.has("a") && m.get("a").is_array() && m.get("a").array_len() == 3, "a")?;
    assert(enc_hex(m) == "81a1619301c3c0")?;
    let dup = must_decode_hex("82a16101a16102");
    assert(dup.map_len() == 2, "dup len")?;
    assert(dup.get("a").is_int() && dup.get("a").i == 1, "first")?;
    assert(dup.key_at(1).s == "a" && dup.child(1).i == 2, "second")?;
    assert(enc_hex(dup) == "82a16101a16102")?;
    let ik = must_decode_hex("8101c3");
    assert(ik.key_at(0).is_int() && ik.key_at(0).i == 1, "int key")?;
    assert(ik.child(0).is_bool() && ik.child(0).flag, "bool val")?;
    assert(enc_hex(MsgpackValue::empty_map()) == "80")?;
    assert(enc_hex(must_decode_hex("df00000000")) == "80")?;
}

test("builder copies into the parent arena") {
    let inner = MsgpackValue::empty_array();
    must_append(inner, MsgpackValue::from_int(1));
    let m = MsgpackValue::empty_map();
    must_put(m, MsgpackValue::from_string("a"), inner);
    must_put(m, MsgpackValue::from_int(2), MsgpackValue::from_bool(false));
    assert(enc_hex(m) == "82a161910102c2")?;
    let arr = MsgpackValue::empty_array();
    must_append(arr, MsgpackValue::from_bin(from_hex("0102")));
    must_append(arr, MsgpackValue::from_ext(0 - 1, from_hex("03")));
    assert(enc_hex(arr) == "92c4020102d4ff03")?;
}

test("append and put reject the wrong container") {
    let n = MsgpackValue::nil();
    assert(match n.append(MsgpackValue::from_int(1)) {
        Result::Ok(_) => false,
        Result::Err(e) => match e {
            MsgpackError::Invalid { line, column } => line == 1 && column == 1,
            default => false,
        },
    }, "append nil")?;
    assert(match MsgpackValue::empty_array().put(MsgpackValue::from_string("a"), MsgpackValue::nil()) {
        Result::Ok(_) => false,
        Result::Err(e) => match e {
            MsgpackError::Invalid { line, column } => line == 1 && column == 1,
            default => false,
        },
    }, "put array")?;
}

test("missing key returns the map") {
    let m = MsgpackValue::empty_map();
    assert(!m.has("no"), "has")?;
    assert(m.get("no").is_map() && m.get("no").map_len() == 0, "get")?;
}

test("truncated and reserved") {
    assert(is_invalid_at(codec().decode(from_hex("")), 1, 1), "empty")?;
    assert(is_invalid_at(codec().decode(from_hex("c1")), 1, 1), "reserved")?;
    assert(is_invalid_at(codec().decode(from_hex("cc")), 1, 2), "uint8 short")?;
    assert(is_invalid_at(codec().decode(from_hex("81")), 1, 2), "map short")?;
    assert(is_invalid_at(codec().decode(from_hex("c0c0")), 1, 2), "trailing")?;
    assert(is_utf8(codec().decode(from_hex("a1ff"))), "bad str")?;
}

test("utf8 string helpers") {
    let raw: Vec<byte> = Vec::new();
    raw.push(1 as byte);
    let s = match from_bytes(raw) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "utf8",
    };
    let v = match codec().decode_str(s) {
        Result::Ok(x) => x,
        Result::Err(_) => panic "decode_str",
    };
    assert(v.is_int() && v.i == 1, "decode_str")?;
    assert(encode_is_utf8(codec().encode_str(MsgpackValue::nil())), "encode_str")?;
}

test("non-finite constructors") {
    assert(enc_hex(MsgpackValue::nan()) == "cb7ff8000000000000")?;
    assert(enc_hex(MsgpackValue::inf(false)) == "cb7ff0000000000000")?;
    assert(enc_hex(MsgpackValue::inf(true)) == "cbfff0000000000000")?;
    let inf = exp(1000.0);
    assert(enc_hex(MsgpackValue::from_float(inf)) == "cb7ff0000000000000")?;
    assert(enc_hex(MsgpackValue::from_float(0.0 - inf)) == "cbfff0000000000000")?;
}
