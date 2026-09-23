# Consuming coil-msgpack

This package is `msgpack`. `use msgpack::{Msgpack, MsgpackValue, MsgpackError}` resolves from `src/msgpack.hy`. One-shot encode/decode ships here. Do not add a native/FFI dep.

Coil-to-Coil deps will be spool-owned once a public `spool` CLI exists. Until then `{ git }` parses and the pin is `coil.lock` `rev` + `content_hash`.

## Sibling checkout

Clone this repo next to your project. In the consumer `coil.toml`:

```toml
[module]
roots = ["./src", "../coil-msgpack/src"]
```

`roots` is what loads `src/msgpack.hy`. The compiler does not follow path deps for discovery.

## Git dep and coil.lock

```toml
[dependencies]
msgpack = { git = "https://github.com/ardax-corp/coil-msgpack.git" }

[module]
roots = ["./src", "./.spool/deps/msgpack/src"]
```

This repo has no tags. The pin is `coil.lock` `rev` + `content_hash`. Omit `tag`. Use sibling checkout until spool materializes `.spool/deps`. The compiler does not read `coil.lock` and does not inject roots.

```
# spool lockfile v1
[[package]]
name = 'msgpack'
git = 'https://github.com/ardax-corp/coil-msgpack.git'
rev = '<commit SHA>'
content_hash = '<tree SHA>'
```

`rev` is the commit. `content_hash` is that commit's git tree (`git rev-parse 'HEAD^{tree}'`). Replace both when you move the pin.

## Call Msgpack::standard()

Signatures are in [`src/msgpack.hy`](../src/msgpack.hy). Call patterns are in [`tests/format.hy`](../tests/format.hy).

```coil
use msgpack::{Msgpack, MsgpackValue, MsgpackError};

let m = Msgpack::standard();
let v = m.decode(bytes)?;
let out = m.encode(v)?;
```

`decode` takes `Vec<byte>` and returns `Result<MsgpackValue, MsgpackError>`. `encode` takes `MsgpackValue` and returns `Result<Vec<byte>, MsgpackError>`.

`decode_str` is `to_bytes` then `decode`. `encode_str` is `encode` then `from_bytes`. A `from_bytes` failure on encode is `MsgpackError::Utf8`. MessagePack frames are binary, so prefer `decode` / `encode`.

Prefer matching directly on `decode` results. Storing `Result<MsgpackValue, MsgpackError>` in a `let` before matching can mis-handle the payload until a compiler fix lands.

### MsgpackValue

`MsgpackValue` is a class plus arena handle, not an enum. Nested arrays and maps come from decode, or from `append` / `put`, which copy into the parent store.

```coil
MsgpackValue::nil()
MsgpackValue::from_bool(true)
MsgpackValue::from_int(7)
MsgpackValue::from_float(1.5)
MsgpackValue::nan()
MsgpackValue::inf(false)
MsgpackValue::from_string("hi")
MsgpackValue::from_bin(raw)
MsgpackValue::from_ext(-1, raw)
MsgpackValue::empty_array()
MsgpackValue::empty_map()
```

Predicates: `is_nil`, `is_bool`, `is_int`, `is_float`, `is_string`, `is_bin`, `is_array`, `is_map`, `is_ext`. Lengths: `array_len`, `map_len`, `bin_len`. Access: `child(n)`, `key_at(n)`, `has(key)`, `get(key)`, `bytes()`, `ext_type()`. Scalar payloads on the handle are `flag`, `i`, `f`, `s`.

`child(n)` is the nth array element or the nth map value. `key_at(n)` is the nth map key as a `MsgpackValue`. `get` returns the first value whose key is that string. A missing key returns the map itself.

```coil
let arr = MsgpackValue::empty_array();
arr.append(MsgpackValue::from_int(1))?;
let map = MsgpackValue::empty_map();
map.put(MsgpackValue::from_string("a"), arr)?;
let out = m.encode(map)?;
```

An integer that fits in i64 stays an int. uint64 values above i64 max are `MsgpackError::Number`. A float32 decodes as f64. Encode writes float64. NaN encodes as canonical `0x7ff8000000000000`. Non-finite floats use `i` as a kind (`1` inf, `2` nan) and `flag` for the sign of inf. `MsgpackValue::nan()` and `MsgpackValue::inf(neg)` set that kind. Host floats may not preserve a NaN, so do not use `f != f` as the check.

### MsgpackError

```coil
enum MsgpackError {
    Invalid { line: int, column: int },
    Io { line: int, column: int },
    Utf8 { line: int, column: int },
    Number { line: int, column: int },
}
```

`line` is 1. `column` is the 1-based byte offset. Malformed input returns `MsgpackError::Invalid` with position, not a panic. A string payload that is not UTF-8 is `MsgpackError::Utf8`.

```coil
match m.decode(bytes) {
    Result::Ok(_) => false,
    Result::Err(e) => match e {
        MsgpackError::Invalid { line, column } => line >= 1 && column >= 1,
        default => false,
    },
}
```
