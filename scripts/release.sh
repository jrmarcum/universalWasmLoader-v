#!/usr/bin/env bash
# Cut a release of universalWasmLoader-v consistently.
#
# The single source of truth for the version is the `version:` field in v.mod.
# This script reads it, tags the current commit `v<version>`, pushes the branch
# and tag to `origin`, and (unless --no-release) creates the matching GitHub
# Release. VPM (the V package manager) resolves the package from the git repo
# itself, so the pushed tag/commit is the part that actually matters; the GitHub
# Release is human-readable polish. Publishing to VPM is a separate, deliberate
# step — see scripts/publish.sh.
#
# Usage: scripts/release.sh [options]
#   --notes <text>   Release notes body (default: a generic line).
#   --no-release     Push the tag only; skip creating a GitHub Release.
#   --no-build       Skip the `v run examples/adder.v` verification.
#   --remote <name>  Git remote to push to (default: origin).
#   --dry-run        Print what would happen; make no tags/pushes/releases.
#   -h, --help       Show this help.
#
# Idempotent: if the tag already exists it is reused (must point at HEAD); an
# existing GitHub Release is left untouched.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

NOTES=""
MAKE_RELEASE=1
DO_BUILD=1
REMOTE="origin"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --notes)      NOTES="${2:-}"; shift 2 ;;
    --no-release) MAKE_RELEASE=0; shift ;;
    --no-build)   DO_BUILD=0; shift ;;
    --remote)     REMOTE="${2:-}"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^#//'; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

run() {  # echo + execute, or just echo under --dry-run
  echo "+ $*"
  if [ "$DRY_RUN" -eq 0 ]; then "$@"; fi
}

# --- Derive version from v.mod (source of truth) ----------------------------
VERSION="$(grep -oE "version:[[:space:]]*'[^']+'" v.mod \
           | grep -oE "'[^']+'" | tr -d "'")"
if [ -z "$VERSION" ]; then
  echo "error: could not read version from v.mod" >&2
  exit 1
fi
TAG="v$VERSION"
echo "Releasing $TAG (from v.mod)"

# --- Preflight checks -------------------------------------------------------
if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty — commit or stash before releasing." >&2
  git status --short >&2
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "On branch: $BRANCH"

# If the tag already exists, it must point at the current commit.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if [ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]; then
    echo "error: tag $TAG exists but does not point at HEAD." >&2
    echo "       Bump version in v.mod or move the tag deliberately." >&2
    exit 1
  fi
  echo "tag $TAG already exists at HEAD — reusing."
  TAG_EXISTS=1
else
  TAG_EXISTS=0
fi

# --- Verify it builds -------------------------------------------------------
# V's default tcc cannot link wasmtime. If VFLAGS already selects a C compiler
# (-cc ...), trust it and run plain `v`. Otherwise prefer the Zig-cc wrapper
# when `zig` is on PATH (OS-aware), else fall back to plain `v` (may fail).
if [ "$DO_BUILD" -eq 1 ]; then
  echo "Verifying build (v run examples/adder.v)…"
  if [ -n "${VFLAGS:-}" ] && printf '%s' "$VFLAGS" | grep -q -- '-cc'; then
    run v run examples/adder.v
  elif command -v zig >/dev/null 2>&1; then
    case "$(uname -s 2>/dev/null || echo unknown)" in
      MINGW*|MSYS*|CYGWIN*) CC="$(pwd -W)/scripts/zigcc.bat" ;;
      *)                    CC="$HERE/scripts/zigcc.sh" ;;
    esac
    run v -cc "$CC" run examples/adder.v
  else
    echo "warning: no -cc in VFLAGS and zig not found; trying default compiler." >&2
    run v run examples/adder.v
  fi
fi

# --- Tag, push, release -----------------------------------------------------
if [ "$TAG_EXISTS" -eq 0 ]; then
  run git tag -a "$TAG" -m "universalWasmLoader-v $TAG"
fi

run git push "$REMOTE" "$BRANCH"
run git push "$REMOTE" "$TAG"

if [ "$MAKE_RELEASE" -eq 1 ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "warning: gh CLI not found — skipping GitHub Release (tag is pushed)." >&2
  elif gh release view "$TAG" >/dev/null 2>&1; then
    echo "GitHub Release $TAG already exists — leaving it untouched."
  else
    BODY="${NOTES:-Release $TAG of universalWasmLoader-v — idiomatic V binding for the Universal WASM Loader.}"
    run gh release create "$TAG" --title "$TAG" --notes "$BODY"
  fi
fi

echo "Done: $TAG"
