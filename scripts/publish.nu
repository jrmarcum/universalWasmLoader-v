#!/usr/bin/env nu
# Publish this package to VPM (the V package manager) — a SEPARATE, deliberate
# step (cross-platform sibling of publish.sh), intentionally kept out of
# release.nu.
#
# VPM has NO upload/CLI publish command. Like Go modules, VPM resolves a package
# from the git repository itself: a module is registered ONCE by submitting its
# git repo URL at https://vpm.vlang.io/new (no auth token, no per-version
# upload). After that, `v install jrmarcum.universal_wasm_loader` clones the repo
# and `v update` pulls new commits. There is nothing to upload per release — the
# pushed tag/commit IS the published artifact once the repo is registered.
#
# So this is a clearly-logged NO-OP: it confirms the released tag exists (so you
# "publish" exactly what was released), then prints what to do. It exists to keep
# the bump -> release -> publish ritual and shape uniform with the sibling ports.
#
# Prereq order:  bump-version.nu -> release.nu -> publish.nu
#
# Usage: nu scripts/publish.nu [flags]

# Read the version from v.mod (single source of truth).
def read-version []: nothing -> string {
  let parsed = (open v.mod | parse --regex "version:\\s*'(?<v>[^']+)'")
  if ($parsed | is-empty) {
    print -e "error: could not read version from v.mod"
    exit 1
  }
  $parsed | get v.0
}

# Read the module name from v.mod (best-effort; empty if absent).
def read-module []: nothing -> string {
  let parsed = (open v.mod | parse --regex "name:\\s*'(?<n>[^']+)'")
  if ($parsed | is-empty) { "" } else { $parsed | get n.0 }
}

# Fatal in a real run; downgraded to a warning under --dry-run so the flow is inspectable.
def guard [dry: bool, msg: string] {
  if $dry {
    print -e $"warning \(ignored under --dry-run): ($msg)"
  } else {
    print -e $"error: ($msg)"
    exit 1
  }
}

def main [
  --yes             # Accepted for shape parity; no irreversible upload to confirm
  --dry-run         # Print what would happen; change nothing
  --allow-dirty     # Skip the clean-working-tree check
  --skip-tag-check  # Don't require the v<version> tag locally + on remote
  --remote: string = "origin"
] {
  let version = (read-version)
  let tag = $"v($version)"
  let module = (read-module)
  let module_disp = (if ($module | is-empty) { "universal_wasm_loader" } else { $module })
  print $"Publishing ($tag) to VPM \(module: ($module_disp))"

  # Preflight: clean tree.
  if not $allow_dirty {
    let status = (^git status --porcelain)
    if ($status | str trim | is-not-empty) {
      guard $dry_run "working tree is dirty — commit/stash, or pass --allow-dirty."
    }
  }

  # Preflight: the release tag exists locally and on the remote.
  if not $skip_tag_check {
    if (^git rev-parse -q --verify $"refs/tags/($tag)" | complete).exit_code != 0 {
      guard $dry_run $"tag ($tag) not found locally — run scripts/release.nu first \(or --skip-tag-check)."
    }
    let lsr = (^git ls-remote --tags $remote $tag | complete)
    if not ($lsr.stdout | str contains $"refs/tags/($tag)") {
      guard $dry_run $"tag ($tag) not on ($remote) — push it \(scripts/release.nu) before publishing \(or --skip-tag-check)."
    }
  }

  # Publish: a no-op for VPM. --yes/--dry-run accepted for shape parity; there is
  # no irreversible action here to confirm or to simulate.
  let origin_url = (let r = (^git remote get-url $remote | complete); if $r.exit_code == 0 { $r.stdout | str trim } else { "<your repo URL>" })

  print ""
  print "VPM has no upload/CLI publish — this step is a no-op (by design)."
  print ""
  print "How VPM publishing actually works (like Go modules — it resolves off the repo):"
  print $"  1. ONE-TIME registration: submit the repo URL at https://vpm.vlang.io/new"
  print $"       repo: ($origin_url)"
  print "     Once registered the module is installable as:"
  print $"       v install ($module_disp)"
  print "       (VPM names it <author>.<module>, e.g. jrmarcum.universal_wasm_loader)"
  print "  2. UPDATES: there is no per-version upload. Consumers get new code by"
  print "       v update <module>"
  print $"     which pulls the repo. So pushing ($tag) \(done by scripts/release.nu) is all"
  print "     that \"publishing this version\" requires once the repo is registered."
  print ""
  print $"Nothing was changed. The pushed ($tag) tag/commit is the published artifact."
  print $"Done: VPM publish is a no-op; ($tag) is already the released state."
}
