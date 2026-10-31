# coil-msgpack

Userland MessagePack for [coil](https://github.com/ardax-corp/coil-lang). Package name is `msgpack`, so `use msgpack::{Msgpack, MsgpackValue, MsgpackError}` resolves here.

Pure Coil encode/decode. No native library. The tree is an arena of primitive vecs; a `MsgpackValue` is a `(store, idx)` handle — named-module recursive `Vec<MsgpackValue>` does not unify (`MsgpackValue` vs `msgpack::MsgpackValue`).

One module, `msgpack` (`src/msgpack.coil`): the `Msgpack` codec, the `MsgpackValue` handle it decodes to and builds with, and the `MsgpackError` it reports.

## Example

```coil
use msgpack::{Msgpack, MsgpackValue, MsgpackError};
use io::sync::{println};
use string::{format};

fn main() {
    let m = Msgpack::standard();
    let doc = MsgpackValue::empty_map();
    let _ = doc.put(MsgpackValue::from_string("name"), MsgpackValue::from_string("coil"));
    let _ = doc.put(MsgpackValue::from_string("stars"), MsgpackValue::from_int(7));
    match m.encode(doc) {
        Result::Ok(bytes) => {
            println(format("%i bytes", bytes.len()))?;
            match m.decode(bytes) {
                Result::Ok(v) => {
                    println(v.get("name").s)?;
                },
                Result::Err(MsgpackError::Invalid { offset }) => {
                    println(format("invalid at byte %i", offset))?;
                },
                Result::Err(_) => {
                    println("bad number or UTF-8")?;
                },
            }
        },
        Result::Err(_) => {
            println("encode failed")?;
        },
    }
}
```

Run it with `coil --root ../coil-stdlib/src --root ../coil-msgpack/src main.coil` (prints `18 bytes`, then `coil`).

## API

```coil
use msgpack::{Msgpack, MsgpackValue, MsgpackError};

let m = Msgpack::standard();
let v = m.decode(bytes)?;
let out = m.encode(v)?;
```

`Msgpack::standard()` is the MessagePack format. Invalid input returns `MsgpackError` with the 0-based byte `offset` of the failure (`Invalid`, `Utf8`, `Number`), not a panic.

| Method | Role |
|--------|------|
| `Msgpack::standard()` | MessagePack codec |
| `decode` / `encode` | `Vec<byte>` |
| `decode_str` / `encode_str` | UTF-8 views of those bytes |

`decode_str` is `to_bytes` then `decode`. `encode_str` is `encode` then `from_bytes`. MessagePack is binary, so most documents are not valid UTF-8: `encode_str` then returns `MsgpackError::Utf8`. Prefer `decode` / `encode`.

Values: nil, bool, int, float, string, binary, array, map, extension. Maps are ordered key/value children. Keys may be any value. Duplicate keys are kept in encounter order. `get` / `has` match the first string key.

Integers are i64. Encode writes the smallest family that fits. A uint64 above i64 max is `MsgpackError::Number`. Floats are f64. float32 widens on decode. Encode writes float64. NaN encodes as a canonical quiet NaN. `+inf` / `-inf` round-trip. Signed zero round-trips. Non-finite kind is `i` (`1` inf, `2` nan) and `flag` is the inf sign. `MsgpackValue::nan()` and `MsgpackValue::inf(neg)` set that kind. Host floats may not preserve a NaN.

Extension data is raw `(type, bytes)`, including timestamp type `-1`. An extension type outside -128..=127 fails at encode with `MsgpackError::Number`.

`append` and `put` copy into the parent arena. There is no shared child across arenas.

## Layout

| Path | Role |
|------|------|
| `src/msgpack.coil` | `Msgpack`, `MsgpackValue`, `MsgpackError`, parser/encoder |
| `coil.toml` | spool manifest (`[package] name = "msgpack"`); coil does not read it |

## Consume

```bash
spool add msgpack --git https://github.com/ardax-corp/coil-msgpack.git --rev <commit SHA>
```

No tags yet, so pin a commit. Without spool, pass `--root ../coil-msgpack/src` to `coil`. See [docs/consume.md](docs/consume.md).

## Test

```bash
# from coil-msgpack, with coil on PATH and coil-stdlib checked out next to it
coil test --root ../coil-stdlib/src
```

This runs `tests/` and the examples in the `///` docs of `src/msgpack.coil`.

## License

MIT. See [LICENSE](LICENSE).
