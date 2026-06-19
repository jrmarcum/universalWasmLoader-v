#!/usr/bin/env nu
# Cut a release of universalWasmLoader-v consistently (cross-platform).
#
# Sibling of release.sh. The single source of truth for the version is the
# `version:` field in v.mod. This tags the current commit `v<version>`, pushes
# the branch and tag to `origin`, and (unless --no-release) creates the matching
# GitHub Release. It does NOT publish to VPM — that's publish.nu.
#
# Usage: nu scripts/release.nu [flags]

# Read the version from v.mod (single source of truth).
def read-version []: nothing -> string {
  let parsed = (open v.mod | parse --regex "version:\\s*'(?<v>[^']+)'")
  if ($parsed | is-empty) {
    print -e "error: could not read version from v.mod"
    exit 1
  }
  $parsed | get v.0
}

def main [
  --notes: string = ""    # Release notes body (default: a generic line)
  --no-release            # Push the tag only; skip creating a GitHub Release
  --no-build              # Skip the `v run examples/adder.v` verification
  --remote: string = "origin"
  --dry-run               # Print what would happen; make no tags/pushes/releases
] {
  let version = (read-version)
  let tag = $"v($version)"
  print $"Releasing ($tag) \(from v.mod)"

  # Preflight: clean tree.
  let status = (^git status --porcelain)
  if ($status | str trim | is-not-empty) {
    print -e "error: working tree is dirty — commit or stash before releasing."
    print -e $status
    exit 1
  }

  let branch = (^git rev-parse --abbrev-ref HEAD | str trim)
  print $"On branch: ($branch)"

  # If the tag already exists, it must point at the current commit.
  let head = (^git rev-parse HEAD | str trim)
  let tag_exists = (^git rev-parse -q --verify $"refs/tags/($tag)" | complete).exit_code == 0
  if $tag_exists {
    let tagcommit = (^git rev-parse $"($tag)^{commit}" | str trim)
    if $tagcommit != $head {
      print -e $"error: tag ($tag) exists but does not point at HEAD."
      print -e "       Bump version in v.mod or move the tag deliberately."
      exit 1
    }
    print $"tag ($tag) already exists at HEAD — reusing."
  }

  # Verify it builds. V's default tcc cannot link wasmtime. If VFLAGS already
  # selects a C compiler (-cc ...), trust it; otherwise prefer the Zig-cc
  # wrapper when `zig` is on PATH (OS-aware), else fall back to plain `v`.
  if not $no_build {
    print "Verifying build (v run examples/adder.v)…"
    let vflags = ($env.VFLAGS? | default "")
    if ($vflags | str contains "-cc") {
      print "+ v run examples/adder.v"
      if not $dry_run { ^v run examples/adder.v }
    } else if (which zig | is-not-empty) {
      let cc = (if $nu.os-info.name == "windows" {
        [(pwd) scripts zigcc.bat] | path join
      } else {
        [(pwd) scripts zigcc.sh] | path join
      })
      print $"+ v -cc ($cc) run examples/adder.v"
      if not $dry_run { ^v -cc $cc run examples/adder.v }
    } else {
      print -e "warning: no -cc in VFLAGS and zig not found; trying default compiler."
      print "+ v run examples/adder.v"
      if not $dry_run { ^v run examples/adder.v }
    }
  }

  # Tag.
  if not $tag_exists {
    print $"+ git tag -a ($tag) -m \"universalWasmLoader-v ($tag)\""
    if not $dry_run { ^git tag -a $tag -m $"universalWasmLoader-v ($tag)" }
  }

  # Push branch + tag.
  print $"+ git push ($remote) ($branch)"
  if not $dry_run { ^git push $remote $branch }
  print $"+ git push ($remote) ($tag)"
  if not $dry_run { ^git push $remote $tag }

  # GitHub Release.
  if not $no_release {
    if (which gh | is-empty) {
      print -e "warning: gh CLI not found — skipping GitHub Release (tag is pushed)."
    } else if (^gh release view $tag | complete).exit_code == 0 {
      print $"GitHub Release ($tag) already exists — leaving it untouched."
    } else {
      let body = (if ($notes | is-empty) {
        $"Release ($tag) of universalWasmLoader-v — idiomatic V binding for the Universal WASM Loader."
      } else { $notes })
      print $"+ gh release create ($tag) --title ($tag) --notes <body>"
      if not $dry_run { ^gh release create $tag --title $tag --notes $body }
    }
  }

  print $"Done: ($tag)"
}
