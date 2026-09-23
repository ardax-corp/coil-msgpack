// Package root. Coil-side MessagePack encode/decode.
// Named-module recursive `Vec<MsgpackValue>` does not unify (`MsgpackValue` vs `msgpack::MsgpackValue`).
// The tree is an arena of primitive vecs; MsgpackValue is a (store, idx) handle.
// Integers are i64. A uint64 above i64 max is MsgpackError::Number.
// Floats are f64. float32 widens on decode; encode writes float64.
use string::{from_bytes, to_bytes};

const TAG_NIL: int = 0;
const TAG_BOOL: int = 1;
const TAG_INT: int = 2;
const TAG_FLOAT: int = 3;
const TAG_STR: int = 4;
const TAG_BIN: int = 5;
const TAG_ARR: int = 6;
const TAG_MAP: int = 7;
const TAG_EXT: int = 8;

const FLT_FINITE: int = 0;
const FLT_INF: int = 1;
const FLT_NAN: int = 2;

const I64_MAX: int = 9223372036854775807;
const I64_MIN: int = 0 - I64_MAX - 1;
const U32_MAX: int = 4294967295;
const U32: int = 4294967296;
// 2^31. Function-body literals above i32 max are miscompiled; consts are fine.
const TWO_31: int = 2147483648;
const MANT_52: int = 4503599627370496;
const NEG_INF_HI: int = 4293918720;
const F64_MANT: float = 4503599627370496.0;

class Store {
    pub tags: Vec<int>,
    pub flags: Vec<bool>,
    pub ints: Vec<int>,
    pub floats: Vec<float>,
    pub strs: Vec<string>,
    pub keys: Vec<string>,
    pub bins: Vec<Vec<byte>>,
    pub first: Vec<int>,
    last: Vec<int>,
    pub next: Vec<int>,
}

impl Store {
    pub static fn with_capacity(int n) -> Store {
        let cap = n;
        if cap < 4 {
            cap = 4;
        }
        let tags: Vec<int> = Vec::with_capacity(cap);
        let flags: Vec<bool> = Vec::with_capacity(cap);
        let ints: Vec<int> = Vec::with_capacity(cap);
        let floats: Vec<float> = Vec::with_capacity(cap);
        let strs: Vec<string> = Vec::with_capacity(cap);
        let keys: Vec<string> = Vec::with_capacity(cap);
        let bins: Vec<Vec<byte>> = Vec::with_capacity(cap);
        let first: Vec<int> = Vec::with_capacity(cap);
        let last: Vec<int> = Vec::with_capacity(cap);
        let next: Vec<int> = Vec::with_capacity(cap);
        return new Store(tags, flags, ints, floats, strs, keys, bins, first, last, next);
    }

    pub static fn new() -> Store {
        return Store::with_capacity(4);
    }

    pub static fn copy_bytes(Vec<byte> src) -> Vec<byte> {
        let out: Vec<byte> = Vec::with_capacity(len(src));
        let i = 0;
        while i < len(src) {
            out.push(src[i]);
            i = i + 1;
        }
        return out;
    }

    pub static fn inf_float(bool neg) -> float {
        let x = 1.0;
        let i = 0;
        while i < 2048 {
            x = x * 2.0;
            i = i + 1;
        }
        if neg {
            return 0.0 - x;
        }
        return x;
    }

    pub static fn nan_float() -> float {
        let x = Store::inf_float(false);
        return x - x;
    }

    pub fn add(int tag, bool flag, int n, float x, string s, string key, Vec<byte> bin) -> int {
        let idx = len(self.tags);
        self.tags.push(tag);
        self.flags.push(flag);
        self.ints.push(n);
        self.floats.push(x);
        self.strs.push(s);
        self.keys.push(key);
        self.bins.push(bin);
        self.first.push(-1);
        self.last.push(-1);
        self.next.push(-1);
        return idx;
    }

    pub fn attach(int parent, int child) {
        if self.first[parent] < 0 {
            self.first[parent] = child;
            self.last[parent] = child;
        } else {
            self.next[self.last[parent]] = child;
            self.last[parent] = child;
        }
    }

    pub fn nth_child(int parent, int n) -> int {
        let c = self.first[parent];
        let i = 0;
        while c >= 0 {
            if i == n {
                return c;
            }
            i = i + 1;
            c = self.next[c];
        }
        return -1;
    }
}

/// Holds both arenas so the recursive copy takes only an index.
/// A `Store` parameter on a recursive method does not unify (`Store` vs `msgpack::Store`).
class Copier {
    src: Store,
    dst: Store,
}

impl Copier {
    #[max_depth(256)]
    pub fn copy(int src_idx) -> int {
        let tag = self.src.tags[src_idx];
        let flag = self.src.flags[src_idx];
        let n = self.src.ints[src_idx];
        let x = self.src.floats[src_idx];
        let s = self.src.strs[src_idx];
        let key = self.src.keys[src_idx];
        let bin = Store::copy_bytes(self.src.bins[src_idx]);
        let child = self.src.first[src_idx];
        let idx = self.dst.add(tag, flag, n, x, s, key, bin);
        while child >= 0 {
            let nxt = self.src.next[child];
            let copied = self.copy(child);
            self.dst.attach(idx, copied);
            child = nxt;
        }
        return idx;
    }
}

/// Decode/encode failure. `line` is 1. `column` is the 1-based byte offset.
enum MsgpackError {
    Invalid { line: int, column: int },
    Io { line: int, column: int },
    Utf8 { line: int, column: int },
    Number { line: int, column: int },
}

/// MessagePack value. Maps are ordered key/value children. Duplicates are kept.
class MsgpackValue {
    store: Store,
    idx: int,
    tag: int,
    pub flag: bool,
    pub i: int,
    pub f: float,
    pub s: string,
}

class Parser {
    bytes: Vec<byte>,
    i: int,
    pub store: Store,
}

/// MessagePack codec. `Msgpack::standard()` is the one format.
class Msgpack {}

impl MsgpackValue {
    pub static fn wrap(Store store, int idx) -> MsgpackValue {
        return new MsgpackValue(
            store,
            idx,
            store.tags[idx],
            store.flags[idx],
            store.ints[idx],
            store.floats[idx],
            store.strs[idx],
        );
    }

    pub static fn nil() -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_NIL, false, 0, 0.0, "", "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn from_bool(bool flag) -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_BOOL, flag, 0, 0.0, "", "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn from_int(int n) -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_INT, false, n, 0.0, "", "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn nan() -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_FLOAT, false, FLT_NAN, Store::nan_float(), "", "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn inf(bool neg) -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_FLOAT, neg, FLT_INF, Store::inf_float(neg), "", "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn from_float(float x) -> MsgpackValue {
        let kind = FLT_FINITE;
        let neg = false;
        if x != x {
            kind = FLT_NAN;
        } else {
            if x == 0.0 {
                let inv = 1.0 / x;
                if inv < 0.0 {
                    neg = true;
                }
            } else {
                if x * 2.0 == x {
                    kind = FLT_INF;
                    if x < 0.0 {
                        neg = true;
                    }
                }
            }
        }
        let st = Store::new();
        let idx = st.add(TAG_FLOAT, neg, kind, x, "", "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn from_string(string s) -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_STR, false, 0, 0.0, s, "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn from_bin(Vec<byte> data) -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_BIN, false, len(data), 0.0, "", "", data);
        return MsgpackValue::wrap(st, idx);
    }

    /// `ty` is the extension type code (-128..=127). Out of range fails at encode.
    pub static fn from_ext(int ty, Vec<byte> data) -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_EXT, false, ty, 0.0, "", "", data);
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn empty_array() -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_ARR, false, 0, 0.0, "", "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub static fn empty_map() -> MsgpackValue {
        let st = Store::new();
        let idx = st.add(TAG_MAP, false, 0, 0.0, "", "", Vec::new());
        return MsgpackValue::wrap(st, idx);
    }

    pub fn is_nil() -> bool {
        return self.tag == TAG_NIL;
    }

    pub fn is_bool() -> bool {
        return self.tag == TAG_BOOL;
    }

    pub fn is_int() -> bool {
        return self.tag == TAG_INT;
    }

    pub fn is_float() -> bool {
        return self.tag == TAG_FLOAT;
    }

    pub fn is_string() -> bool {
        return self.tag == TAG_STR;
    }

    pub fn is_bin() -> bool {
        return self.tag == TAG_BIN;
    }

    pub fn is_array() -> bool {
        return self.tag == TAG_ARR;
    }

    pub fn is_map() -> bool {
        return self.tag == TAG_MAP;
    }

    pub fn is_ext() -> bool {
        return self.tag == TAG_EXT;
    }

    pub fn array_len() -> int {
        if self.tag != TAG_ARR {
            return 0;
        }
        return self.store.ints[self.idx];
    }

    pub fn map_len() -> int {
        if self.tag != TAG_MAP {
            return 0;
        }
        return self.store.ints[self.idx];
    }

    pub fn bin_len() -> int {
        if self.tag != TAG_BIN && self.tag != TAG_EXT {
            return 0;
        }
        return len(self.store.bins[self.idx]);
    }

    pub fn ext_type() -> int {
        if self.tag != TAG_EXT {
            return 0;
        }
        return self.i;
    }

    pub fn bytes() -> Vec<byte> {
        if self.tag != TAG_BIN && self.tag != TAG_EXT {
            return Vec::new();
        }
        return Store::copy_bytes(self.store.bins[self.idx]);
    }

    /// Nth array element, or nth map value. Out of range returns `self`.
    pub fn child(int n) -> MsgpackValue {
        let c = -1;
        if self.tag == TAG_ARR {
            c = self.store.nth_child(self.idx, n);
        } else {
            if self.tag == TAG_MAP {
                c = self.store.nth_child(self.idx, n * 2 + 1);
            }
        }
        if c < 0 {
            return self;
        }
        return MsgpackValue::wrap(self.store, c);
    }

    /// Nth map key. Out of range returns `self`.
    pub fn key_at(int n) -> MsgpackValue {
        if self.tag != TAG_MAP {
            return self;
        }
        let c = self.store.nth_child(self.idx, n * 2);
        if c < 0 {
            return self;
        }
        return MsgpackValue::wrap(self.store, c);
    }

    pub fn has(string key) -> bool {
        return self.find_key(key) >= 0;
    }

    /// First string-key match. Missing returns `self`.
    pub fn get(string key) -> MsgpackValue {
        let c = self.find_key(key);
        if c < 0 {
            return self;
        }
        return MsgpackValue::wrap(self.store, c);
    }

    fn find_key(string key) -> int {
        if self.tag != TAG_MAP {
            return -1;
        }
        let n = self.store.ints[self.idx];
        let i = 0;
        while i < n {
            let k = self.store.nth_child(self.idx, i * 2);
            if k >= 0 {
                if self.store.tags[k] == TAG_STR {
                    if self.store.strs[k] == key {
                        return self.store.nth_child(self.idx, i * 2 + 1);
                    }
                }
            }
            i = i + 1;
        }
        return -1;
    }

    /// Copy `child` onto the end of this array.
    pub fn append(MsgpackValue child) -> Result<(), MsgpackError> {
        if self.tag != TAG_ARR {
            raise MsgpackError::Invalid { line: 1, column: 1 };
        }
        let copied = (new Copier(child.store, self.store)).copy(child.idx);
        self.store.attach(self.idx, copied);
        self.store.ints[self.idx] = self.store.ints[self.idx] + 1;
        return ();
    }

    /// Copy `key` and `val` onto the end of this map. Duplicate keys are kept.
    pub fn put(MsgpackValue key, MsgpackValue val) -> Result<(), MsgpackError> {
        if self.tag != TAG_MAP {
            raise MsgpackError::Invalid { line: 1, column: 1 };
        }
        let k = (new Copier(key.store, self.store)).copy(key.idx);
        let v = (new Copier(val.store, self.store)).copy(val.idx);
        self.store.attach(self.idx, k);
        self.store.attach(self.idx, v);
        self.store.ints[self.idx] = self.store.ints[self.idx] + 1;
        return ();
    }

    fn push_u8(Vec<byte> out, int n) {
        let v = n % 256;
        if v < 0 {
            v = v + 256;
        }
        out.push(v as byte);
    }

    fn push_u16(Vec<byte> out, int n) {
        self.push_u8(out, n / 256);
        self.push_u8(out, n);
    }

    fn push_u32(Vec<byte> out, int n) {
        self.push_u8(out, n / 16777216);
        self.push_u8(out, n / 65536);
        self.push_u8(out, n / 256);
        self.push_u8(out, n);
    }

    fn push_u64(Vec<byte> out, int n) {
        let hi = n / U32;
        let lo = n % U32;
        self.push_u32(out, hi);
        self.push_u32(out, lo);
    }

    /// Two's-complement int64. `n` is negative and not i32.
    fn push_i64(Vec<byte> out, int n) {
        if n == I64_MIN {
            self.push_u32(out, TWO_31);
            self.push_u32(out, 0);
            return;
        }
        let mag = 0 - n;
        let mhi = mag / U32;
        let mlo = mag % U32;
        let hi = 0;
        let lo = 0;
        if mlo == 0 {
            lo = 0;
            hi = U32 - mhi;
        } else {
            lo = U32 - mlo;
            hi = U32_MAX - mhi;
        }
        self.push_u32(out, hi);
        self.push_u32(out, lo);
    }

    fn write_int(Vec<byte> out, int n) {
        if n >= 0 {
            if n <= 127 {
                self.push_u8(out, n);
                return;
            }
            if n <= 255 {
                self.push_u8(out, 204);
                self.push_u8(out, n);
                return;
            }
            if n <= 65535 {
                self.push_u8(out, 205);
                self.push_u16(out, n);
                return;
            }
            if n <= U32_MAX {
                self.push_u8(out, 206);
                self.push_u32(out, n);
                return;
            }
            self.push_u8(out, 207);
            self.push_u64(out, n);
            return;
        }
        if n >= -32 {
            self.push_u8(out, n + 256);
            return;
        }
        if n >= -128 {
            self.push_u8(out, 208);
            self.push_u8(out, n + 256);
            return;
        }
        if n >= -32768 {
            self.push_u8(out, 209);
            self.push_u16(out, n + 65536);
            return;
        }
        if n >= (0 - TWO_31) {
            self.push_u8(out, 210);
            self.push_u32(out, n + U32);
            return;
        }
        self.push_u8(out, 211);
        self.push_i64(out, n);
    }

    fn write_len_header(Vec<byte> out, int n, int fix_base, int fix_max, int op16, int op32) -> Result<(), MsgpackError> {
        if n < 0 {
            raise MsgpackError::Number { line: 1, column: 1 };
        }
        if n <= fix_max {
            self.push_u8(out, fix_base + n);
            return ();
        }
        if n <= 65535 {
            self.push_u8(out, op16);
            self.push_u16(out, n);
            return ();
        }
        if n <= U32_MAX {
            self.push_u8(out, op32);
            self.push_u32(out, n);
            return ();
        }
        raise MsgpackError::Number { line: 1, column: 1 };
    }

    fn write_counted(Vec<byte> out, int n, int op8, int op16, int op32) -> Result<(), MsgpackError> {
        if n < 0 {
            raise MsgpackError::Number { line: 1, column: 1 };
        }
        if n <= 255 {
            self.push_u8(out, op8);
            self.push_u8(out, n);
            return ();
        }
        if n <= 65535 {
            self.push_u8(out, op16);
            self.push_u16(out, n);
            return ();
        }
        if n <= U32_MAX {
            self.push_u8(out, op32);
            self.push_u32(out, n);
            return ();
        }
        raise MsgpackError::Number { line: 1, column: 1 };
    }

    fn round_mant(float mant_f) -> int {
        if mant_f <= 0.0 {
            return 0;
        }
        let base = (floor(mant_f)) as int;
        let frac = mant_f - (base as float);
        if frac >= 0.5 {
            base = base + 1;
        }
        if base < 0 {
            return 0;
        }
        return base;
    }

    fn write_inf(Vec<byte> out, bool neg) {
        self.push_u8(out, 203);
        if neg {
            self.push_u32(out, NEG_INF_HI);
        } else {
            self.push_u32(out, 2146435072);
        }
        self.push_u32(out, 0);
    }

    fn write_nan(Vec<byte> out) {
        self.push_u8(out, 203);
        self.push_u32(out, 2146959360);
        self.push_u32(out, 0);
    }

    fn write_f64(Vec<byte> out, float x, bool neg_zero) -> Result<(), MsgpackError> {
        if x != x {
            self.write_nan(out);
            return ();
        }
        let neg = false;
        if x < 0.0 {
            neg = true;
        }
        if x == 0.0 {
            if neg_zero {
                neg = true;
            } else {
                let inv = 1.0 / x;
                if inv < 0.0 {
                    neg = true;
                }
            }
            self.push_u8(out, 203);
            if neg {
                self.push_u32(out, TWO_31);
            } else {
                self.push_u32(out, 0);
            }
            self.push_u32(out, 0);
            return ();
        }
        let ax = x;
        if neg {
            ax = 0.0 - x;
        }
        if ax * 2.0 == ax {
            self.write_inf(out, neg);
            return ();
        }
        let exp = 0;
        let sig = ax;
        let steps = 0;
        while sig >= 2.0 {
            sig = sig / 2.0;
            exp = exp + 1;
            steps = steps + 1;
            if steps > 2048 {
                raise MsgpackError::Number { line: 1, column: 1 };
            }
        }
        while sig < 1.0 && exp > -1022 {
            sig = sig * 2.0;
            exp = exp - 1;
        }
        let mant = 0;
        let biased = 0;
        if sig < 1.0 {
            mant = self.round_mant(sig * F64_MANT);
            if mant >= MANT_52 {
                mant = 0;
                biased = 1;
            }
        } else {
            mant = self.round_mant((sig - 1.0) * F64_MANT);
            if mant >= MANT_52 {
                mant = 0;
                exp = exp + 1;
            }
            if exp > 1023 {
                self.write_inf(out, neg);
                return ();
            }
            biased = exp + 1023;
        }
        let sign = 0;
        if neg {
            sign = 1;
        }
        let mant_lo = mant & U32_MAX;
        let mant_hi = (mant >> 32) & 1048575;
        let hi = (sign << 31) | (biased << 20) | mant_hi;
        self.push_u8(out, 203);
        self.push_u32(out, hi);
        self.push_u32(out, mant_lo);
        return ();
    }

    fn push_raw(Vec<byte> out, Vec<byte> raw) {
        let i = 0;
        while i < len(raw) {
            out.push(raw[i]);
            i = i + 1;
        }
    }

    fn write_ext_type(Vec<byte> out, int ty) -> Result<(), MsgpackError> {
        if ty < -128 || ty > 127 {
            raise MsgpackError::Number { line: 1, column: 1 };
        }
        let b = ty;
        if b < 0 {
            b = b + 256;
        }
        self.push_u8(out, b);
        return ();
    }

    #[max_depth(256)]
    fn emit_idx(Vec<byte> out, int idx) -> Result<(), MsgpackError> {
        let tag = self.store.tags[idx];
        if tag == TAG_NIL {
            self.push_u8(out, 192);
            return ();
        }
        if tag == TAG_BOOL {
            if self.store.flags[idx] {
                self.push_u8(out, 195);
            } else {
                self.push_u8(out, 194);
            }
            return ();
        }
        if tag == TAG_INT {
            self.write_int(out, self.store.ints[idx]);
            return ();
        }
        if tag == TAG_FLOAT {
            let kind = self.store.ints[idx];
            if kind == FLT_NAN {
                self.write_nan(out);
                return ();
            }
            if kind == FLT_INF {
                self.write_inf(out, self.store.flags[idx]);
                return ();
            }
            self.write_f64(out, self.store.floats[idx], self.store.flags[idx])?;
            return ();
        }
        if tag == TAG_STR {
            let raw = to_bytes(self.store.strs[idx]);
            let n = len(raw);
            if n <= 31 {
                self.push_u8(out, 160 + n);
            } else {
                self.write_counted(out, n, 217, 218, 219)?;
            }
            self.push_raw(out, raw);
            return ();
        }
        if tag == TAG_BIN {
            let raw = self.store.bins[idx];
            self.write_counted(out, len(raw), 196, 197, 198)?;
            self.push_raw(out, raw);
            return ();
        }
        if tag == TAG_EXT {
            let raw = self.store.bins[idx];
            let n = len(raw);
            let ty = self.store.ints[idx];
            if n == 1 {
                self.push_u8(out, 212);
                self.write_ext_type(out, ty)?;
            } else {
                if n == 2 {
                    self.push_u8(out, 213);
                    self.write_ext_type(out, ty)?;
                } else {
                    if n == 4 {
                        self.push_u8(out, 214);
                        self.write_ext_type(out, ty)?;
                    } else {
                        if n == 8 {
                            self.push_u8(out, 215);
                            self.write_ext_type(out, ty)?;
                        } else {
                            if n == 16 {
                                self.push_u8(out, 216);
                                self.write_ext_type(out, ty)?;
                            } else {
                                self.write_counted(out, n, 199, 200, 201)?;
                                self.write_ext_type(out, ty)?;
                            }
                        }
                    }
                }
            }
            self.push_raw(out, raw);
            return ();
        }
        if tag == TAG_ARR {
            let n = self.store.ints[idx];
            self.write_len_header(out, n, 144, 15, 220, 221)?;
            let c = self.store.first[idx];
            while c >= 0 {
                self.emit_idx(out, c)?;
                c = self.store.next[c];
            }
            return ();
        }
        if tag == TAG_MAP {
            let n = self.store.ints[idx];
            self.write_len_header(out, n, 128, 15, 222, 223)?;
            let c = self.store.first[idx];
            let pairs = 0;
            while c >= 0 {
                self.emit_idx(out, c)?;
                c = self.store.next[c];
                if c < 0 {
                    raise MsgpackError::Invalid { line: 1, column: 1 };
                }
                self.emit_idx(out, c)?;
                c = self.store.next[c];
                pairs = pairs + 1;
            }
            if pairs != n {
                raise MsgpackError::Invalid { line: 1, column: 1 };
            }
            return ();
        }
        raise MsgpackError::Invalid { line: 1, column: 1 };
    }

    pub fn encode_buf() -> Result<Vec<byte>, MsgpackError> {
        let n = len(self.store.tags) * 8;
        if n < 16 {
            n = 16;
        }
        let out: Vec<byte> = Vec::with_capacity(n);
        self.emit_idx(out, self.idx)?;
        return out;
    }
}

impl Parser {
    pub fn at_end() -> bool {
        return self.i >= len(self.bytes);
    }

    pub fn column() -> int {
        return self.i + 1;
    }

    fn pos(int at) -> int {
        if at < 0 {
            return 1;
        }
        return at + 1;
    }

    fn byte_at(int at) -> int {
        let b = self.bytes[at] as int;
        if b < 0 {
            b = b + 256;
        }
        return b;
    }

    fn need(int n, int at) -> Result<(), MsgpackError> {
        if n < 0 {
            raise MsgpackError::Invalid { line: 1, column: self.pos(at) };
        }
        let rest = len(self.bytes) - self.i;
        if n > rest {
            raise MsgpackError::Invalid { line: 1, column: self.pos(self.i) };
        }
        return ();
    }

    fn read_u8(int at) -> Result<int, MsgpackError> {
        self.need(1, at)?;
        let b = self.byte_at(self.i);
        self.i = self.i + 1;
        return b;
    }

    fn read_be(int width, int at) -> Result<int, MsgpackError> {
        self.need(width, at)?;
        let n = 0;
        let k = 0;
        while k < width {
            n = n * 256 + self.byte_at(self.i);
            self.i = self.i + 1;
            k = k + 1;
        }
        return n;
    }

    fn read_bytes(int n, int at) -> Result<Vec<byte>, MsgpackError> {
        self.need(n, at)?;
        let out: Vec<byte> = Vec::with_capacity(n);
        let k = 0;
        while k < n {
            out.push(self.bytes[self.i]);
            self.i = self.i + 1;
            k = k + 1;
        }
        return out;
    }

    fn read_str(int n, int at) -> Result<string, MsgpackError> {
        let raw = self.read_bytes(n, at)?;
        return match from_bytes(raw) {
            Result::Ok(s) => s,
            Result::Err(_) => raise MsgpackError::Utf8 { line: 1, column: self.pos(at) },
        };
    }

    fn rethrow(MsgpackError err) -> Result<MsgpackValue, MsgpackError> {
        return match err {
            MsgpackError::Invalid { line, column } => raise MsgpackError::Invalid { line: line, column: column },
            MsgpackError::Io { line, column } => raise MsgpackError::Io { line: line, column: column },
            MsgpackError::Utf8 { line, column } => raise MsgpackError::Utf8 { line: line, column: column },
            MsgpackError::Number { line, column } => raise MsgpackError::Number { line: line, column: column },
        };
    }

    /// `let root = parse_value()?` inside `Result<MsgpackValue, _>` dropped the error.
    pub fn finish() -> Result<MsgpackValue, MsgpackError> {
        match self.parse_value() {
            Result::Ok(root) => {
                if !self.at_end() {
                    raise MsgpackError::Invalid { line: 1, column: self.column() };
                }
                return MsgpackValue::wrap(self.store, root);
            },
            Result::Err(err) => {
                return self.rethrow(err)?;
            },
        };
    }

    fn read_u64_fit(int at) -> Result<int, MsgpackError> {
        let hi = self.read_be(4, at)?;
        let lo = self.read_be(4, at)?;
        if hi >= TWO_31 {
            raise MsgpackError::Number { line: 1, column: self.pos(at) };
        }
        return hi * U32 + lo;
    }

    fn read_i64() -> Result<int, MsgpackError> {
        let at = self.i;
        let hi = self.read_be(4, at)?;
        let lo = self.read_be(4, at)?;
        if hi < TWO_31 {
            return hi * U32 + lo;
        }
        if hi == TWO_31 && lo == 0 {
            return I64_MIN;
        }
        let inv_lo = (lo ^ U32_MAX) + 1;
        let inv_hi = hi ^ U32_MAX;
        if inv_lo > U32_MAX {
            inv_lo = inv_lo - U32;
            inv_hi = inv_hi + 1;
        }
        let mag = inv_hi * U32 + inv_lo;
        return 0 - mag;
    }

    fn add_float(bool neg, int kind, float x) -> int {
        let bin: Vec<byte> = Vec::new();
        return self.store.add(TAG_FLOAT, neg, kind, x, "", "", bin);
    }

    fn scale_pow2(float sig, int exp) -> float {
        let value = sig;
        if exp > 0 {
            let k = 0;
            while k < exp {
                value = value * 2.0;
                k = k + 1;
            }
        } else {
            let k = 0;
            let n = 0 - exp;
            while k < n {
                value = value / 2.0;
                k = k + 1;
            }
        }
        return value;
    }

    fn finish_f64(int sign, int biased, int mant) -> int {
        if biased == 2047 {
            if mant == 0 {
                let neg = sign != 0;
                return self.add_float(neg, FLT_INF, Store::inf_float(neg));
            }
            return self.add_float(false, FLT_NAN, Store::nan_float());
        }
        if biased == 0 && mant == 0 {
            let neg = sign != 0;
            return self.add_float(neg, FLT_FINITE, 0.0);
        }
        let value = 0.0;
        if biased == 0 {
            value = self.scale_pow2(mant as float, -1074);
        } else {
            let sig = 1.0 + ((mant as float) / F64_MANT);
            value = self.scale_pow2(sig, biased - 1023);
        }
        if sign != 0 {
            value = 0.0 - value;
        }
        return self.add_float(false, FLT_FINITE, value);
    }

    fn read_f64(int at) -> Result<int, MsgpackError> {
        let hi = self.read_be(4, at)?;
        let lo = self.read_be(4, at)?;
        let sign = (hi >> 31) & 1;
        let biased = (hi >> 20) & 2047;
        let mant_hi = hi & 1048575;
        let mant = (mant_hi << 32) | lo;
        return self.finish_f64(sign, biased, mant);
    }

    fn read_f32(int at) -> Result<int, MsgpackError> {
        let bits = self.read_be(4, at)?;
        let sign = (bits >> 31) & 1;
        let biased = (bits >> 23) & 255;
        let mant = bits & 8388607;
        if biased == 255 {
            if mant == 0 {
                return self.finish_f64(sign, 2047, 0);
            }
            return self.finish_f64(sign, 2047, 1);
        }
        if biased == 0 {
            if mant == 0 {
                return self.finish_f64(sign, 0, 0);
            }
            let value = self.scale_pow2(mant as float, -149);
            if sign != 0 {
                value = 0.0 - value;
            }
            return self.add_float(false, FLT_FINITE, value);
        }
        let f64_mant = mant << 29;
        let f64_biased = biased - 127 + 1023;
        return self.finish_f64(sign, f64_biased, f64_mant);
    }

    fn read_ext_type(int at) -> Result<int, MsgpackError> {
        let t = self.read_u8(at)?;
        if t >= 128 {
            t = t - 256;
        }
        return t;
    }

    fn add_ext(int ty, Vec<byte> data) -> int {
        return self.store.add(TAG_EXT, false, ty, 0.0, "", "", data);
    }

    #[max_depth(256)]
    fn parse_array(int count) -> Result<int, MsgpackError> {
        let bin: Vec<byte> = Vec::new();
        let arr = self.store.add(TAG_ARR, false, 0, 0.0, "", "", bin);
        let k = 0;
        while k < count {
            let kid = self.parse_value()?;
            self.store.attach(arr, kid);
            k = k + 1;
        }
        self.store.ints[arr] = count;
        return arr;
    }

    #[max_depth(256)]
    fn parse_map(int count) -> Result<int, MsgpackError> {
        let bin: Vec<byte> = Vec::new();
        let obj = self.store.add(TAG_MAP, false, 0, 0.0, "", "", bin);
        let k = 0;
        while k < count {
            let key = self.parse_value()?;
            let val = self.parse_value()?;
            self.store.attach(obj, key);
            self.store.attach(obj, val);
            k = k + 1;
        }
        self.store.ints[obj] = count;
        return obj;
    }

    fn add_int(int n) -> int {
        let bin: Vec<byte> = Vec::new();
        return self.store.add(TAG_INT, false, n, 0.0, "", "", bin);
    }

    fn add_nil() -> int {
        let bin: Vec<byte> = Vec::new();
        return self.store.add(TAG_NIL, false, 0, 0.0, "", "", bin);
    }

    fn add_bool(bool flag) -> int {
        let bin: Vec<byte> = Vec::new();
        return self.store.add(TAG_BOOL, flag, 0, 0.0, "", "", bin);
    }

    fn add_str(string s) -> int {
        let bin: Vec<byte> = Vec::new();
        return self.store.add(TAG_STR, false, 0, 0.0, s, "", bin);
    }

    fn parse_str_n(int n, int at) -> Result<int, MsgpackError> {
        let s = self.read_str(n, at)?;
        return self.add_str(s);
    }

    fn parse_bin(int b, int at) -> Result<int, MsgpackError> {
        let n = 0;
        if b == 196 {
            n = self.read_u8(at)?;
        } else {
            if b == 197 {
                n = self.read_be(2, at)?;
            } else {
                n = self.read_be(4, at)?;
            }
        }
        let data = self.read_bytes(n, at)?;
        return self.store.add(TAG_BIN, false, n, 0.0, "", "", data);
    }

    fn parse_ext_sized(int n, int at) -> Result<int, MsgpackError> {
        let ty = self.read_ext_type(at)?;
        let data = self.read_bytes(n, at)?;
        return self.add_ext(ty, data);
    }

    fn parse_ext_len(int b, int at) -> Result<int, MsgpackError> {
        let n = 0;
        if b == 199 {
            n = self.read_u8(at)?;
        } else {
            if b == 200 {
                n = self.read_be(2, at)?;
            } else {
                n = self.read_be(4, at)?;
            }
        }
        return self.parse_ext_sized(n, at)?;
    }

    fn parse_fixext(int b, int at) -> Result<int, MsgpackError> {
        let n = 1;
        if b == 213 {
            n = 2;
        }
        if b == 214 {
            n = 4;
        }
        if b == 215 {
            n = 8;
        }
        if b == 216 {
            n = 16;
        }
        return self.parse_ext_sized(n, at)?;
    }

    fn parse_uint(int b, int at) -> Result<int, MsgpackError> {
        if b == 204 {
            return self.add_int(self.read_u8(at)?);
        }
        if b == 205 {
            return self.add_int(self.read_be(2, at)?);
        }
        if b == 206 {
            return self.add_int(self.read_be(4, at)?);
        }
        return self.add_int(self.read_u64_fit(at)?);
    }

    fn parse_signed(int b, int at) -> Result<int, MsgpackError> {
        if b == 208 {
            let n = self.read_u8(at)?;
            if n >= 128 {
                n = n - 256;
            }
            return self.add_int(n);
        }
        if b == 209 {
            let n = self.read_be(2, at)?;
            if n >= 32768 {
                n = n - 65536;
            }
            return self.add_int(n);
        }
        if b == 210 {
            let n = self.read_be(4, at)?;
            if n >= TWO_31 {
                n = n - U32;
            }
            return self.add_int(n);
        }
        let n = self.read_i64()?;
        return self.add_int(n);
    }

    fn parse_str_len(int b, int at) -> Result<int, MsgpackError> {
        let n = 0;
        if b == 217 {
            n = self.read_u8(at)?;
        } else {
            if b == 218 {
                n = self.read_be(2, at)?;
            } else {
                n = self.read_be(4, at)?;
            }
        }
        return self.parse_str_n(n, at)?;
    }

    fn parse_seq(bool is_map, int width, int at) -> Result<int, MsgpackError> {
        let n = self.read_be(width, at)?;
        if is_map {
            return self.parse_map(n)?;
        }
        return self.parse_array(n)?;
    }

    pub fn parse_value() -> Result<int, MsgpackError> {
        let at = self.i;
        let b = self.read_u8(at)?;
        return self.branch_fix(b, at)?;
    }

    fn branch_fix(int b, int at) -> Result<int, MsgpackError> {
        if b <= 127 {
            return self.add_int(b);
        }
        if b >= 224 {
            return self.add_int(b - 256);
        }
        if b >= 128 && b <= 143 {
            return self.parse_map(b - 128)?;
        }
        if b >= 144 && b <= 159 {
            return self.parse_array(b - 144)?;
        }
        if b >= 160 && b <= 191 {
            return self.parse_str_n(b - 160, at)?;
        }
        return self.branch_atom(b, at)?;
    }

    fn branch_atom(int b, int at) -> Result<int, MsgpackError> {
        if b == 192 {
            return self.add_nil();
        }
        if b == 194 {
            return self.add_bool(false);
        }
        if b == 195 {
            return self.add_bool(true);
        }
        if b >= 196 && b <= 198 {
            return self.parse_bin(b, at)?;
        }
        return self.branch_ext(b, at)?;
    }

    fn branch_ext(int b, int at) -> Result<int, MsgpackError> {
        if b >= 199 && b <= 201 {
            return self.parse_ext_len(b, at)?;
        }
        if b == 202 {
            return self.read_f32(at)?;
        }
        if b == 203 {
            return self.read_f64(at)?;
        }
        if b >= 204 && b <= 207 {
            return self.parse_uint(b, at)?;
        }
        return self.branch_tail(b, at)?;
    }

    fn branch_tail(int b, int at) -> Result<int, MsgpackError> {
        if b >= 208 && b <= 211 {
            return self.parse_signed(b, at)?;
        }
        if b >= 212 && b <= 216 {
            return self.parse_fixext(b, at)?;
        }
        if b >= 217 && b <= 219 {
            return self.parse_str_len(b, at)?;
        }
        if b == 220 {
            return self.parse_seq(false, 2, at)?;
        }
        if b == 221 {
            return self.parse_seq(false, 4, at)?;
        }
        if b == 222 {
            return self.parse_seq(true, 2, at)?;
        }
        if b == 223 {
            return self.parse_seq(true, 4, at)?;
        }
        raise MsgpackError::Invalid { line: 1, column: self.pos(at) };
    }
}

impl Msgpack {
    /// The MessagePack format: one-shot encode and decode.
    pub static fn standard() -> Msgpack {
        return new Msgpack();
    }

    pub fn encode(MsgpackValue value) -> Result<Vec<byte>, MsgpackError> {
        return value.encode_buf()?;
    }

    pub fn decode(Vec<byte> bytes) -> Result<MsgpackValue, MsgpackError> {
        let guess = len(bytes) / 2;
        if guess < 4 {
            guess = 4;
        }
        let p = new Parser(bytes, 0, Store::with_capacity(guess));
        return p.finish()?;
    }

    pub fn encode_str(MsgpackValue value) -> Result<string, MsgpackError> {
        let bytes = self.encode(value)?;
        return match from_bytes(bytes) {
            Result::Ok(s) => s,
            Result::Err(_) => raise MsgpackError::Utf8 { line: 1, column: 1 },
        };
    }

    pub fn decode_str(string s) -> Result<MsgpackValue, MsgpackError> {
        return self.decode(to_bytes(s))?;
    }
}
