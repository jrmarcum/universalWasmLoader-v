# cmem — Portable Project Memory for universalWasmLoader-v

This folder is the **authoritative, portable project memory** for `universalWasmLoader-v`. It lives
inside the project tree, so it travels with the repo and is committed to git. Keep files small and
single-topic.

## Policy

- **`cmem/` is the single home for ALL project memory.** When the owner says "**update the project
  memory**," update the matching `cmem/` topic file with the latest decisions, found bugs, design
  changes, and current state — then add/refresh its one-line pointer in the table below. Convert
  relative dates to absolute; update existing entries rather than duplicating.
- **`README` is NOT project memory.** It is the public, user-facing doc. Keep internal decision logs /
  bug post-mortems out of it — those live here in `cmem/`.

### The "update the project memory" trigger (binding on every agent)
When the owner says **"update the project memory"** (or a synonym — "update memory", "record this"),
do BOTH: (1) revise all relevant `cmem/` files and refresh the Files-table pointers (absolute dates;
update, don't duplicate); and (2) sync the user-facing README only where the change is user-relevant —
never copy internal decision logs into it.

### The "look for code issues" trigger (binding on every agent)
When the owner says **"look for code issues"** (or "code audit" / "audit the code"), perform a
comprehensive audit of the V binding (`universal_wasm_loader/uwl.v`) and its C-link glue
(`universal_wasm_loader/uwl_shim.c`, `uwl_shim.h`, the `#flag` link lines in `uwl.v`) for: (1)
workarounds / temporary hacks; (2) dead code; (3) bugs (wrong `kind` discriminant in the `Arg`
builders or the shim `switch`, leaked C-owned strings, missing `uwlv_free_str`/`uwl_val_free`, missing
`nil` checks on `&char`/handle returns, unsafe pointer lifetimes across the FFI boundary); and (4)
silent fall-throughs (returning a default kind instead of erroring). Report `file:line` + severity, fix
the safe ones, and confirm the example still prints the expected adder output (see `overview.md` for
the exact build command and output).

## Files

| File | What it holds |
| --- | --- |
| [overview.md](overview.md) | What this V port is, its language/runtime, API surface, how it links the C loader + wasmtime via the shim, build/run flow (verified output + date), the release/publish toolchain, and known gaps |
