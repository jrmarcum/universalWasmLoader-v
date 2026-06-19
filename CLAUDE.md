> **⚠️ PORTABLE PROJECT MEMORY LIVES IN `cmem/`** — start at [`cmem/INDEX.md`](cmem/INDEX.md).
> When saving new project memory, write it into the matching `cmem/` topic file (and refresh its
> pointer in `cmem/INDEX.md`). The **"update the project memory"** and **"look for code issues"**
> triggers are defined in `cmem/INDEX.md` and are binding on every agent.

# universalWasmLoader-v

Idiomatic V binding for the [Universal WASM Loader](https://github.com/jrmarcum/universalWasmLoader-c).
A thin wrapper over the C single-header loader (a small C shim + a V module): call `.wasm` exports with
native V values and `!`/`or` error handling. See [`README.md`](README.md) for user-facing docs and
[`cmem/overview.md`](cmem/overview.md) for the project memory.

## Quick orientation

- `universal_wasm_loader/uwl.v` — the binding (public `Module` API, `Arg` builders, the `#flag`
  compile/link directives, and the `C.uwlv_*` FFI declarations).
- `universal_wasm_loader/uwl_shim.{c,h}` — the C shim: compiles the loader and exposes a primitive
  `uwlv_*` surface (the loader's value constructors are `static inline` / awkward to pass by value).
- `universal_wasm_loader/universal_wasm_loader.h` — vendored copy of the upstream C loader.
- `scripts/fetch-wasmtime.sh` — fetches the wasmtime C API SDK into `vendor/` (gitignored).
- `scripts/zigcc.{bat,ps1,sh}` — Zig-as-C-compiler wrapper (V's default `tcc` can't link wasmtime).
- `scripts/bump-version.{sh,nu}` / `release.{sh,nu}` / `publish.{sh,nu}` — the release toolchain
  (`v.mod` version is the single source of truth; publish is a deliberate, separate, VPM step).
- Run the example: `export VFLAGS="-cc $(pwd -W)/scripts/zigcc.bat"; v run examples/adder.v`.
