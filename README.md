# universalWasmLoader-v

Idiomatic **V** binding for the [Universal WASM Loader](https://github.com/jrmarcum/universalWasmLoader-c).
It wraps the C single-header loader so you call `.wasm` exports with native V
values and `!`/`or` error handling — the V sibling of the reference JS loader
[`@jrmarcum/universal-wasm-loader`](https://jsr.io/@jrmarcum/universal-wasm-loader).

The hard parts (WIT parsing, Canonical ABI marshalling, `cabi_post` string
returns, version pinning) live **once**, in the C loader. This repo is a thin
wrapper over it (a small C shim + a V module) — built on the
[wasmtime C API](https://docs.wasmtime.dev/c-api/).

## Quick start

```v
import universal_wasm_loader as uwl

m := uwl.import_module('examples/math_50.wasm')!
defer { m.free() }

sum := m.call_i32('add', uwl.i32(3), uwl.i32(4))!            // 7
prod := m.call_f64('multiply', uwl.f64(2.5), uwl.f64(4.0))!  // 10.0
greeting := m.call_str('greet', uwl.text('World'))!          // "Hello, World!"
```

Wrap each argument with `uwl.i32` / `i64` / `f32` / `f64` / `boolean` / `text`
so the WIT type is unambiguous, and pick the call by its result type
(`call_i32` / `call_i64` / `call_f64` / `call_bool` / `call_str`). A companion
`.wit` next to the `.wasm` is required.

## Build & run

```sh
scripts/fetch-wasmtime.sh        # downloads the wasmtime C API SDK into vendor/ (gitignored)
```

V's default `tcc` cannot link the wasmtime import library, so pick a C compiler:

**Use Zig as the C compiler** (recommended — no separate MinGW install needed; Zig
bundles a C toolchain). A small wrapper adapts Zig for V (see notes below):

```sh
v -cc "$(pwd -W)/scripts/zigcc.bat" run examples/adder.v
```

Make it the default for every `v` command in the shell via `VFLAGS` (use a
Windows-style path):

```sh
export VFLAGS="-cc $(pwd -W)/scripts/zigcc.bat"
v run examples/adder.v
```

**Or use MinGW gcc:**

```sh
v -cc gcc run examples/adder.v
```

Either way prints:

```
adder(3, 4) = 7
multiply(2.5, 4.0) = 10.0
square(5) = 25
```

## API

- `uwl.import_module(path string) !Module` — load a module (its `.wit` is
  auto-detected; a `@N` path suffix pins the version).
- `m.call_i32 / call_i64 / call_f64 / call_bool / call_str(name, ...Arg) !T` —
  call an export. Build args with `uwl.i32/i64/f32/f64/boolean/text`.
- `m.free()` — free the module.

Errors propagate as V results (`!`), so use `!` or `or { ... }`.

## How it works

`universal_wasm_loader/uwl_shim.{h,c}` is a tiny C shim that compiles the loader
and exposes a primitive-only surface (`uwlv_*`). It exists because the loader's
value constructors are `static inline` (not linkable) and `uwl_val_t` is awkward
to pass by value across V's FFI — the shim marshals through a flat `uwlv_arg`
array and out-parameters instead. The shim header deliberately avoids including
the wasmtime headers, keeping them out of V's translation unit.

## Requirements & notes

- **Choose a C compiler** (V's default `tcc` cannot link the wasmtime import
  library):
  - **Zig** (`scripts/zigcc.bat`) — needs `zig` on `PATH`, plus `bash`+`sed`
    (e.g. Git Bash) for the wrapper. The wrapper compiles via `zig cc`, forces
    the `x86_64-windows-gnu` target, and strips V's hardcoded `-Wl,-stack=` flag
    (V emits it in MSVC form, which Zig's bundled `lld` rejects). On Linux/macOS
    `zig cc` can usually be used directly without the wrapper.
  - **MinGW gcc** (`-cc gcc`) — needs a MinGW gcc on `PATH`.
- **`wasmtime.dll` must be findable at runtime** — copy
  `vendor/.../lib/wasmtime.dll` next to your binary (or the repo root for
  `v run`), or add that `lib` directory to `PATH`.
- The binding links the wasmtime **import library** (`libwasmtime.dll.a`), not the
  static archive (which pulls in the Rust std unwinder).
- The vendored C loader header is `universal_wasm_loader/universal_wasm_loader.h`;
  keep it in sync with the upstream
  [`universalWasmLoader-c`](https://github.com/jrmarcum/universalWasmLoader-c) release you target.
- Host import callbacks are not yet exposed from V (pure-compute / library
  modules only).

## License

MIT.
