# coil-msgpack

Userland MessagePack for [coil](https://github.com/ardax-corp/coil-lang). Package name is `msgpack`, so `use msgpack::{Msgpack, MsgpackValue, MsgpackError}` resolves here.

Pure Coil encode/decode. No native library. The tree is an arena of primitive vecs; a `MsgpackValue` is a `(store, idx)` handle — named-module recursive `Vec<MsgpackValue>` does not unify (`MsgpackValue` vs `msgpack::MsgpackValue`).

## API

```coil
use msgpack::{Msgpack, MsgpackValue, MsgpackError};

let m = Msgpack::standard();
let v = m.decode(bytes)?;
let out = m.encode(v)?;
```

`Msgpack::standard()` is the MessagePack format. Invalid input returns `MsgpackError` with `line` and `column` (`Invalid`, `Io`, `Utf8`, `Number`), not panic. `line` is 1. `column` is the 1-based byte offset of the failure.

| Method | Role |
|--------|------|
| `Msgpack::standard()` | MessagePack codec |
| `decode` / `encode` | `Vec<byte>` |
| `decode_str` / `encode_str` | UTF-8 views of those bytes |

`decode_str` is `to_bytes` then `decode`. `encode_str` is `encode` then `from_bytes`. MessagePack is binary, so most documents are not valid UTF-8: `encode_str` then returns `MsgpackError::Utf8`. Prefer `decode` / `encode`.

Values: nil, bool, int, float, string, binary, array, map, extension. Maps are ordered key/value children. Keys may be any value. Duplicate keys are kept in encounter order. `get` / `has` match the first string key.

Integers are i64. Encode writes the smallest family that fits. A uint64 above i64 max is `MsgpackError::Number`. Floats are f64. float32 widens on decode. Encode writes float64. NaN encodes as a canonical quiet NaN. `+inf` / `-inf` round-trip. Signed zero round-trips. Non-finite kind is `i` (`1` inf, `2` nan) and `flag` is the inf sign. `MsgpackValue::nan()` and `MsgpackValue::inf(neg)` set that kind. Host floats may not preserve a NaN.

Extension data is raw `(type, bytes)`, including timestamp type `-1`. Nesting is bounded at 256 frames.

`append` and `put` copy into the parent arena. There is no shared child across arenas.

## Layout

| Path | Role |
|------|------|
| `src/msgpack.hy` | `Msgpack`, `MsgpackValue`, `MsgpackError`, parser/encoder |
| `coil.toml` | `[package] name = "msgpack"` so `use msgpack::{…}` resolves |

## Consume

Sibling checkout, or a git dep plus `coil.lock` pin. Call `Msgpack::standard()` from [docs/consume.md](docs/consume.md).

```toml
[dependencies]
msgpack = { git = "https://github.com/ardax-corp/coil-msgpack.git" }
```

`{ git }` is the parseable form. `version` is optional schema, not a tag. The pin is `coil.lock` `rev` + `content_hash`. coil-stdlib is a sibling `[module] roots` entry, not a spool dependency of this package.

## Test

```bash
# from coil-msgpack (coil on PATH or ../coil-lang/target/debug/coil)
coil test
```

## License

MIT. See [LICENSE](LICENSE).
