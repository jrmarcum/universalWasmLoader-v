# overview — universalWasmLoader-v

## What this is

`universalWasmLoader-v` is the **idiomatic V binding** of the Universal WASM Loader family. It is a
thin wrapper over the C single-header loader
([`universalWasmLoader-c`](https://github.com/jrmarcum/universalWasmLoader-c)) — the V sibling of the
reference JS loader [`@jrmarcum/universal-wasm-loader`](https://jsr.io/@jrmarcum/universal-wasm-loader).
The hard parts (WIT parsing, Canonical ABI marshalling, `cabi_post` string returns, version pinning)
live **once** in the C loader; this repo only adds a V-native call surface (a small C shim + a V
module) on top.

- **Language / runtime:** V (developed against **V 0.5.1**), built on the
  [wasmtime C API](https://docs.wasmtime.dev/c-api/) (**v45.0.2**) as the WASM engine.
- **What it gives V callers:** native V argument/result values, `!`/`or` result-based error handling
  (no out-params surfaced to V), and a small typed call surface — no manual `uwl_val_t` boxing.
- **Distribution:** a V module (`v.mod` name `uwl`, v1.0.0, MIT) published via **VPM** (the V package
  manager, https://vpm.vlang.io). The MIT `LICENSE` file ships with the repo; README's License section
  links it. **Naming note:** the VPM registry name MUST be letters/digits/dots only (no underscores,
  2–35 chars; see `is_valid_mod_name` in `vlang/vpm`), so the package is `uwl` (full registry name
  `jrmarcum.uwl`, installed via `v install jrmarcum.uwl`). The V module is correspondingly `module uwl`
  in the `uwl/` directory and imported as `import uwl` — matching how the `-zig` sibling exposes its
  importable module as `uwl` even though its package name is longer.

## Current state — IMPLEMENTED v1 (2026-06-19)

Working tree:

- `uwl/uwl.v` — the binding (`module uwl`; public API + `#flag` compile/link directives + the
  `C.uwlv_*` FFI declarations). Marshals V `Arg` values into a flat `C.uwlv_arg` array and reads
  results back through out-params. Every public symbol carries a doc comment (see "Documentation
  conventions" below).
- `uwl/uwl_shim.c` — the C shim: `#define UWL_IMPLEMENTATION` + includes the loader header to compile
  its body, and implements the primitive-only `uwlv_*` surface (import/free/call) by marshalling the
  `uwlv_arg` array into `uwl_val_t` and back.
- `uwl/uwl_shim.h` — the self-contained V-facing C header. Deliberately does **not** include
  `universal_wasm_loader.h` or `wasm.h`, so V parses it into its own translation unit without the
  wasmtime headers.
- `uwl/universal_wasm_loader.h` — **vendored copy** of the upstream C single-header loader (keeps its
  upstream filename inside the `uwl/` module dir). Keep in sync with the `universalWasmLoader-c`
  release being targeted.
- `examples/adder.v` — the runnable example (`v run examples/adder.v`). `examples/math_50.wasm` +
  `math_50.wit` are the reference fixture.
- `scripts/fetch-wasmtime.sh` — downloads the wasmtime C API SDK into `vendor/` (gitignored).
- `scripts/zigcc.{bat,ps1,sh}` — the Zig-as-C-compiler wrapper (see "How it links").
- `scripts/bump-version.{sh,nu}` / `release.{sh,nu}` / `publish.{sh,nu}` — the release toolchain, in
  Bash and equivalent cross-platform Nushell forms (see "Release / publish flow").
- `vendor/` — wasmtime C API SDK (headers + `libwasmtime.dll.a` + `wasmtime.dll`). **gitignored**;
  fetched on demand. `wasmtime.dll` is also staged at the repo root for `v run` (gitignored).
- `LICENSE` — MIT (Copyright (c) 2026 Jon Marcum), identical text to the `-c` port. README License
  section links it; `v.mod` declares `license: 'MIT'`.
- `CLAUDE.md` + `cmem/` — the auto-loaded pointer banner and this portable project memory.

Build environment used for v1: V 0.5.1 + Zig 0.16.0 (as the C compiler) + wasmtime C API **v45.0.2**
`x86_64-mingw`.

## Documentation conventions (added 2026-06-19)

`uwl/uwl.v` is documented for clarity in a way familiar to the TypeScript sibling's contributors:
every public symbol (the `Module`/`Arg` types, `import_module`, `free`, the six arg builders, and the
`call_i32/i64/f64/bool/str` family) and the internal helpers (`invoke`, `take_err`) carry a doc
comment. Each comment keeps **V's name-prefixed first line** (so `v doc` renders it) and then adds
**JSDoc-style `@param` / `@returns` / `@error` notations** for the parameters, result, and failure
mode. The raw `C.uwlv_*` FFI block is grouped under a banner comment describing it as the only
cross-into-C surface (the V equivalent of a hand-written `.d.ts`), and the `k_*` discriminants and
struct fields have inline notes. **`v fmt` is authoritative** — the file is kept `v fmt`-clean (run
`v fmt -w uwl/uwl.v`; `v fmt -verify` passes). `examples/adder.v` follows the same comment style.

## Public API surface (implemented)

All in `uwl/uwl.v`. Idiomatic V over the C loader's explicit `uwl_call` core, reached through the
`uwlv_*` shim.

- **`uwl.import_module(path string) !Module`** — load a `.wasm`; its companion `.wit` is auto-detected,
  a `@N` path suffix pins the version. Returns an error (the C error string, freed after copying) on
  failure. Wraps `uwlv_import` → `uwl_import(path, NULL, 0, err)`.
- **`uwl.Module`** — a loaded, ABI-translated module (`handle &C.uwl_module_t`).
- **`m.free()`** — `uwlv_free` → `uwl_free`; releases the module and all resources it owns.
- **Typed calls** — pick the call by the export's result type:
  - `m.call_i32(name string, args ...Arg) !int` — export returning `s32`.
  - `m.call_i64(name string, args ...Arg) !i64` — export returning `s64`.
  - `m.call_f64(name string, args ...Arg) !f64` — export returning `f32` **or** `f64`.
  - `m.call_bool(name string, args ...Arg) !bool` — export returning `bool`.
  - `m.call_str(name string, args ...Arg) !string` — export returning `string` (the C heap string is
    copied into a V string, then freed with `uwlv_free_str`).
- **Arg builders** — wrap each argument so its WIT type is unambiguous: `uwl.i32`, `uwl.i64`,
  `uwl.f32`, `uwl.f64`, `uwl.boolean`, `uwl.text`. (`Arg` is a tagged struct; only the field matching
  its `kind` is marshalled.)
- Errors propagate as V results (`!`), so callers use `!` or `or { ... }`.

### Arg/result marshalling (across the FFI)

`Module.invoke` builds a `[]C.uwlv_arg` from the `[]Arg`, passing the string pointer only for `k_str`
args, then calls `C.uwlv_call` with out-params (`out_kind`, `out_i`, `out_d`, `out_s`, `err`). The
shim (`uwl_shim.c`) converts each `uwlv_arg` into a `uwl_val_t` via the loader's `uwl_i32/i64/f32/
f64/bool/str` constructors, invokes `uwl_call`, frees any string args, then writes the result back
into the matching out-param. For a string result the shim **transfers ownership** of the heap string
to V (`*out_s = out.str; out.str = NULL`), and V frees it with `uwlv_free_str` after copying. The
`k_*` discriminants in `uwl.v` must stay in lockstep with `uwl_kind_t` in the loader header
(`1=i32 2=i64 3=f32 4=f64 5=bool 6=str`, `0=void`).

**A companion `.wit` is required** (it is the source of per-arg WIT types the loader re-narrows to).

## How it links

V's default `tcc` cannot link the wasmtime import library, so a C compiler must be chosen. The
`#flag` lines in `uwl.v` add the include paths (the shim dir + the wasmtime SDK `include/`), compile
`uwl_shim.c`, link the wasmtime **import library** (`libwasmtime.dll.a`) — NOT the static archive
(which pulls in the Rust std unwinder) — and link the MinGW syslibs wasmtime needs (`ws2_32 bcrypt
userenv ntdll ole32 Shlwapi advapi32 kernel32 uuid`).

Two compiler paths (README "Requirements & notes"):

- **Zig as the C compiler (recommended)** — `scripts/zigcc.bat` (Windows; dispatches to
  `scripts/zigcc.ps1`, no Git Bash needed) or `scripts/zigcc.sh` (Unix). The wrapper runs `zig cc
  -target x86_64-windows-gnu` and strips V's hardcoded MSVC-form `-Wl,-stack=` flag, which Zig's
  bundled `lld` rejects. Use it via `v -cc <wrapper> run ...` or `export VFLAGS="-cc <wrapper>"`.
- **MinGW gcc** — `v -cc gcc run ...` (needs MinGW gcc on `PATH`).

`wasmtime.dll` must be findable at runtime: it is staged at the repo root for `v run` (and lives in
the SDK `lib/`).

## Build / run flow

- `scripts/fetch-wasmtime.sh [VERSION] [PLATFORM]` — fetch the wasmtime C API SDK into `vendor/`
  (needs `curl`, `unzip`; defaults `45.0.2` / `x86_64-mingw`).
- Run the example (Zig-cc path, from the repo root):
  ```sh
  export VFLAGS="-cc $(pwd -W)/scripts/zigcc.bat"   # Windows; on Unix use scripts/zigcc.sh
  v run examples/adder.v
  ```
  Expected output:
  ```
  adder(3, 4) = 7
  multiply(2.5, 4.0) = 10.0
  square(5) = 25
  ```
  **Verified 2026-06-19** (V 0.5.1 + Zig 0.16.0, wasmtime v45.0.2) — matches the README.

## Release / publish flow (AUTHORED 2026-06-19)

The version in `v.mod` (the `version:` field) is the **single source of truth**. Three scripts, run in
order, keep the git tag, GitHub Release, and VPM listing consistent with it. Each ships in **two
equivalent forms** (same flags/guards/behavior — including error messages and exit codes): a Bash
`.sh` and a cross-platform Nushell `.nu` (needs `nu` ≥0.113; runs on Windows/macOS/Linux without Git
Bash). Use whichever the machine has — e.g. `nu scripts/release.nu` or `bash scripts/release.sh`.
`fetch-wasmtime.sh` and the `zigcc` wrappers stay as they are (dev setup, not part of the release
toolchain). **Parity note (2026-06-19):** `bump-version.nu` takes its `spec` as an *optional*
positional and checks for it explicitly, so a missing spec prints the same friendly
`error: missing bump spec …` and exits `2` as the `.sh` form — rather than Nushell's bare
`missing_positional` parser error with a different exit code.

1. **`scripts/bump-version.{sh,nu}` `<major|minor|patch|X.Y.Z>`** — rewrites the `version:` field in
   `v.mod` and commits the isolated bump. Guards: clean tree, strictly-greater target, no pre-existing
   tag, valid semver. `--dry-run` / `--no-commit`.
2. **`scripts/release.{sh,nu}`** — reads `version:` from `v.mod`, verifies a clean tree + a fresh
   `v run examples/adder.v` build (Zig-cc path, OS-aware; honours `$VFLAGS` if it already sets `-cc`,
   else uses the `zigcc` wrapper when `zig` is on `PATH`), tags `v<version>`, pushes branch + tag to
   `origin`, and creates the matching **GitHub Release** via `gh` (skippable). Idempotent (reuses a
   tag only if it points at HEAD; skips an existing Release; degrades if `gh` is unauthenticated).
   Does **not** publish to VPM. `--dry-run` / `--no-release` / `--no-build` / `--remote`.
3. **`scripts/publish.{sh,nu}`** — the deliberate VPM step, decoupled from `release`. **VPM has no
   CLI/push publish command**: a module is registered **once** by submitting its git repo URL at
   https://vpm.vlang.io/new (no auth token, no per-version upload), after which `v install
   jrmarcum.uwl` clones the repo and `v update` pulls new commits. So this script is
   a **clearly-logged no-op**: it reads the version, verifies the `v<version>` tag exists locally + on
   `origin` (so you "publish" exactly what was released), then prints the one-time registration
   instructions and that updates resolve off the pushed repo. Kept present (both forms) so the
   three-script shape is identical across all ports. `--dry-run` / `--yes` / `--allow-dirty` /
   `--skip-tag-check` / `--remote`.

**Why a no-op publish:** unlike crates.io/npm/PyPI (which need a real upload + token), VPM — like Go
modules — resolves the package from the git repository itself. There is nothing to upload per release;
the pushed tag/commit *is* the published artifact once the repo is registered. The script exists to
keep the release/publish ritual and shape uniform with the sibling ports.

**v1.0.0 status (2026-06-19):** version `1.0.0` set in `v.mod`. The V module + VPM package name is
`uwl` (renamed from `universal_wasm_loader` because VPM rejects underscores — see the Naming note
above). Tagged `v1.0.0` at HEAD locally; while the tag is still unpushed it has been moved forward to
keep pace with release-readying commits (the `uwl` rename and the API doc-comment pass), so the
released state carries the VPM-valid name and the documented API. **Remote state:** the owner pushed
`main` through the rename commit (`447db51`) to `origin` (so the `uwl` name is live on GitHub for VPM
registration); the later doc-comment commit is local-only and fast-forwards cleanly. The `v1.0.0` tag
is **not on the remote** and **no GitHub Release** exists yet (pending owner confirmation). Outward-
facing steps that remain (owner-gated): push the remaining commit(s), push the `v1.0.0` tag, create the
GitHub Release via `release`, and register the repo once at https://vpm.vlang.io/new (`publish` is
otherwise a no-op). The tag is what a tag/repo-resolving
registry (VPM, like Go) uses; there is no separate package upload for this ecosystem.

## Known gaps / not yet done

- **No test suite.** Unlike `-c` (`spec_tests.c`, 29 assertions), this repo only ships the `adder`
  example as a smoke test. A `v test` over the SPEC §8 fixtures is not yet authored.
- **No `call_f32`.** `f32` results are returned through `call_f64` (the C loader widens). A dedicated
  `f32`-typed accessor is not surfaced.
- **Host import callbacks** are not exposed from V — `uwlv_import` passes `NULL, 0` for callbacks.
  Pure-compute / library modules work; modules needing host imports are not supported from V.
- **String/aggregate args beyond flat scalars + strings** rely entirely on the C loader; there is no
  V-side validation beyond the `Arg` builder `kind` tags.
- **Vendored header drift:** `uwl/universal_wasm_loader.h` is a manual copy of upstream
  `universalWasmLoader-c`; there is no automated sync — bump it deliberately per targeted release.
- **C-compiler requirement:** V's default `tcc` cannot link wasmtime; a build needs Zig (via the
  `zigcc` wrapper) or MinGW gcc. The `release` build step depends on one being available (or
  `--no-build`).
