#!/usr/bin/env bash
# Bump the project version in v.mod (the single source of truth).
#
# Updates the `version:` field to the next semver, commits the one-line change,
# and stops there — tagging/pushing/releasing is scripts/release.sh's job.
# Typical flow:
#
#     scripts/bump-version.sh minor   # 1.0.0 -> 1.1.0, commits the bump
#     scripts/release.sh              # tags v1.1.0, pushes, GitHub Release
#
# Usage: scripts/bump-version.sh <major|minor|patch|X.Y.Z> [options]
#   major|minor|patch   Increment that semver component (resets lower ones).
#   X.Y.Z               Set an explicit version (must be valid semver).
#   --no-commit         Edit v.mod only; don't commit.
#   --dry-run           Print the new version + planned actions; change nothing.
#   -h, --help          Show this help.
#
# Refuses to run on a dirty tree (so the bump lands as an isolated commit) and
# rejects a target that isn't strictly greater than the current version or whose
# tag already exists.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
MOD="v.mod"

DO_COMMIT=1
DRY_RUN=0
SPEC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --no-commit) DO_COMMIT=0; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^#//'; exit 0 ;;
    major|minor|patch) SPEC="$1"; shift ;;
    [0-9]*.[0-9]*.[0-9]*) SPEC="$1"; shift ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SPEC" ]; then
  echo "error: missing bump spec (major|minor|patch|X.Y.Z). See --help." >&2
  exit 2
fi

run() { echo "+ $*"; if [ "$DRY_RUN" -eq 0 ]; then "$@"; fi; }

# --- Current version --------------------------------------------------------
CUR="$(grep -oE "version:[[:space:]]*'[^']+'" "$MOD" \
       | grep -oE "'[^']+'" | tr -d "'")"
if ! [[ "$CUR" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: current version in $MOD is not plain semver: '${CUR:-<empty>}'" >&2
  exit 1
fi
IFS='.' read -r MA MI PA <<<"$CUR"

# --- Compute target ---------------------------------------------------------
case "$SPEC" in
  major) NEW="$((MA+1)).0.0" ;;
  minor) NEW="${MA}.$((MI+1)).0" ;;
  patch) NEW="${MA}.${MI}.$((PA+1))" ;;
  *)
    if ! [[ "$SPEC" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "error: '$SPEC' is not valid semver (X.Y.Z)." >&2
      exit 2
    fi
    NEW="$SPEC" ;;
esac

# --- Validate (strictly greater, tag free) ----------------------------------
greater() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ] && [ "$1" != "$2" ]; }
if ! greater "$NEW" "$CUR"; then
  echo "error: target $NEW is not greater than current $CUR." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$NEW" >/dev/null; then
  echo "error: tag v$NEW already exists." >&2
  exit 1
fi

echo "Bumping version: $CUR -> $NEW"

# --- Preflight: clean tree --------------------------------------------------
if [ "$DO_COMMIT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty — commit or stash so the bump is isolated." >&2
  git status --short >&2
  exit 1
fi

# --- Apply ------------------------------------------------------------------
if [ "$DRY_RUN" -eq 0 ]; then
  # Replace only the version line, preserving formatting.
  tmp="$(mktemp)"
  sed -E "s/(version:[[:space:]]*')[^']+(')/\1$NEW\2/" "$MOD" >"$tmp"
  mv "$tmp" "$MOD"
fi
echo "+ set version: '$NEW' in $MOD"

if [ "$DO_COMMIT" -eq 1 ]; then
  run git add "$MOD"
  run git commit -m "Bump version: v$CUR -> v$NEW"
fi

echo "Done: $NEW"
if [ "$DO_COMMIT" -eq 1 ]; then
  echo "Next: scripts/release.sh   # tags v$NEW, pushes, creates the GitHub Release"
fi
