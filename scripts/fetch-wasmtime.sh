#!/usr/bin/env bash
# Fetch the wasmtime C API SDK into vendor/ (gitignored). The SDK provides the
# headers (wasm.h / wasmtime.h / wasi.h) and the static/import libraries the
# loader links against.
#
# Usage: scripts/fetch-wasmtime.sh [VERSION] [PLATFORM]
#   VERSION  default: 45.0.2
#   PLATFORM default: x86_64-mingw  (gcc/MinGW on Windows)
#            others:  x86_64-windows (MSVC), x86_64-linux, aarch64-linux,
#                     x86_64-macos, aarch64-macos
set -euo pipefail

VERSION="${1:-45.0.2}"
PLATFORM="${2:-x86_64-mingw}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$HERE/vendor"
NAME="wasmtime-v${VERSION}-${PLATFORM}-c-api"
URL="https://github.com/bytecodealliance/wasmtime/releases/download/v${VERSION}/${NAME}.zip"

mkdir -p "$VENDOR"
if [ -d "$VENDOR/$NAME/include" ]; then
  echo "wasmtime C API already present: $VENDOR/$NAME"
  exit 0
fi

echo "Downloading $URL"
curl -fSL --retry 3 -o "$VENDOR/$NAME.zip" "$URL"
echo "Extracting"
( cd "$VENDOR" && unzip -q -o "$NAME.zip" )
rm -f "$VENDOR/$NAME.zip"
echo "Done: $VENDOR/$NAME"
