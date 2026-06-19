#!/usr/bin/env bash
# Use `zig cc` as V's C compiler on Windows.
#
# V passes its flags in a response file (cc @file.rsp) and hardcodes
# `-Wl,-stack=...`, which zig's bundled lld rejects. We rewrite the response
# file to drop that one flag (zig's default stack size is fine) and force the
# MinGW-GNU target so the wasmtime GNU import library links.
newargs=()
for a in "$@"; do
  case "$a" in
    @*.rsp)
      rsp="${a#@}"; rsp="${rsp//\//}"
      filtered="${rsp%.rsp}.zig.rsp"
      sed 's/-Wl,-stack=[0-9]*//g' "$rsp" > "$filtered"
      newargs+=("@$filtered")
      ;;
    *) newargs+=("$a") ;;
  esac
done
exec zig cc -target x86_64-windows-gnu "${newargs[@]}"
