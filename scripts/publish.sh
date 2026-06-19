#!/usr/bin/env bash
# Publish this package to VPM (the V package manager) — a SEPARATE, deliberate
# step, intentionally kept out of release.sh.
#
# VPM has NO upload/CLI publish command. Like Go modules, VPM resolves a package
# from the git repository itself: a module is registered ONCE by submitting its
# git repo URL at https://vpm.vlang.io/new (no auth token, no per-version
# upload). After that, `v install jrmarcum.universal_wasm_loader` clones the repo
# and `v update` pulls new commits. There is nothing to upload per release — the
# pushed tag/commit IS the published artifact once the repo is registered.
#
# So this script is a clearly-logged NO-OP: it confirms the released tag exists
# (so you "publish" exactly what was released), then prints what to do. It exists
# to keep the bump -> release -> publish ritual and shape uniform with the sibling
# ports (crates.io/npm/PyPI, which DO need a real upload).
#
# Prereq order:  scripts/bump-version.sh -> scripts/release.sh -> scripts/publish.sh
#
# Usage: scripts/publish.sh [options]
#   --yes             Accepted for shape parity; there is no irreversible upload
#                     to confirm (VPM publish is a no-op), so it changes nothing.
#   --dry-run         Print what would happen; change nothing.
#   --allow-dirty     Skip the clean-working-tree check.
#   --skip-tag-check  Don't require the v<version> tag to exist locally + on remote.
#   --remote <name>   Git remote to check the tag against (default: origin).
#   -h, --help        Show this help.
#
# Idempotent by nature: re-running changes nothing (no upload happens).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

ASSUME_YES=0
DRY_RUN=0
ALLOW_DIRTY=0
SKIP_TAG_CHECK=0
REMOTE="origin"

while [ $# -gt 0 ]; do
  case "$1" in
    --yes)            ASSUME_YES=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --allow-dirty)    ALLOW_DIRTY=1; shift ;;
    --skip-tag-check) SKIP_TAG_CHECK=1; shift ;;
    --remote)         REMOTE="${2:-}"; shift 2 ;;
    -h|--help)        sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; s/^#//'; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Fatal in a real run; downgraded to a warning under --dry-run so the flow is inspectable.
guard() { # guard <message>
  if [ "$DRY_RUN" -eq 1 ]; then echo "warning (ignored under --dry-run): $1" >&2; return 0; fi
  echo "error: $1" >&2; exit 1
}

# --- Version / tag (source of truth: v.mod) ---------------------------------
VERSION="$(grep -oE "version:[[:space:]]*'[^']+'" v.mod \
           | grep -oE "'[^']+'" | tr -d "'")"
[ -n "$VERSION" ] || { echo "error: could not read version from v.mod" >&2; exit 1; }
TAG="v$VERSION"
MODULE="$(grep -oE "name:[[:space:]]*'[^']+'" v.mod | grep -oE "'[^']+'" | head -1 | tr -d "'")"
echo "Publishing $TAG to VPM (module: ${MODULE:-universal_wasm_loader})"

# --- Preflight: clean tree --------------------------------------------------
if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
  guard "working tree is dirty — commit/stash, or pass --allow-dirty."
fi

# --- Preflight: the release tag exists locally and on the remote ------------
if [ "$SKIP_TAG_CHECK" -eq 0 ]; then
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    || guard "tag $TAG not found locally — run scripts/release.sh first (or --skip-tag-check)."
  if ! git ls-remote --tags "$REMOTE" "$TAG" | grep -q "refs/tags/$TAG"; then
    guard "tag $TAG not on $REMOTE — push it (scripts/release.sh) before publishing (or --skip-tag-check)."
  fi
fi

# --- Publish: a no-op for VPM -----------------------------------------------
# Nothing to upload. --yes/--dry-run are accepted for shape parity with the
# other ports; there is no irreversible action here to confirm or to simulate.
ORIGIN_URL="$(git remote get-url "$REMOTE" 2>/dev/null || echo '<your repo URL>')"

cat <<EOF
VPM has no upload/CLI publish — this step is a no-op (by design).

How VPM publishing actually works (like Go modules — it resolves off the repo):
  1. ONE-TIME registration: submit the repo URL at https://vpm.vlang.io/new
       repo: $ORIGIN_URL
     Once registered the module is installable as:
       v install ${MODULE:-jrmarcum.universal_wasm_loader}
       (VPM names it <author>.<module>, e.g. jrmarcum.universal_wasm_loader)
  2. UPDATES: there is no per-version upload. Consumers get new code by
       v update <module>
     which pulls the repo. So pushing $TAG (done by scripts/release.sh) is all
     that "publishing this version" requires once the repo is registered.

Nothing was changed. The pushed $TAG tag/commit is the published artifact.
EOF

echo "Done: VPM publish is a no-op; $TAG is already the released state."
