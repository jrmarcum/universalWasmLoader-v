#!/usr/bin/env nu
# Bump the project version in v.mod (the single source of truth).
#
# Cross-platform sibling of bump-version.sh. Updates the `version:` field to the
# next semver, commits the one-line change, and stops there — tagging/pushing is
# release.nu's job. Typical flow:
#
#     nu scripts/bump-version.nu minor   # 1.0.0 -> 1.1.0, commits the bump
#     nu scripts/release.nu              # tags v1.1.0, pushes, GitHub Release
#
# Usage: nu scripts/bump-version.nu <major|minor|patch|X.Y.Z> [flags]

# Read the current version from v.mod.
def read-version []: nothing -> string {
  let parsed = (open v.mod | parse --regex "version:\\s*'(?<v>[^']+)'")
  if ($parsed | is-empty) {
    print -e "error: could not read version from v.mod"
    exit 1
  }
  $parsed | get v.0
}

# True if semver list `a` is strictly greater than `b` (each [major minor patch]).
def semver-gt [a: list, b: list]: nothing -> bool {
  for i in 0..2 {
    let x = ($a | get $i)
    let y = ($b | get $i)
    if $x > $y { return true }
    if $x < $y { return false }
  }
  false
}

def main [
  spec?: string     # major | minor | patch | explicit X.Y.Z
  --no-commit       # edit v.mod only; don't commit
  --dry-run         # print the new version + planned actions; change nothing
] {
  # Match bump-version.sh: a friendly message + exit 2 on a missing spec, rather
  # than Nushell's bare "missing positional" parser error.
  if $spec == null {
    print -e "error: missing bump spec (major|minor|patch|X.Y.Z). See --help."
    exit 2
  }

  let cur = (read-version)
  if not ($cur =~ '^[0-9]+\.[0-9]+\.[0-9]+$') {
    print -e $"error: current version in v.mod is not plain semver: '($cur)'"
    exit 1
  }
  let cp = ($cur | split row '.' | each {|x| $x | into int})

  let new = (match $spec {
    "major" => $"(($cp | get 0) + 1).0.0"
    "minor" => $"($cp | get 0).(($cp | get 1) + 1).0"
    "patch" => $"($cp | get 0).($cp | get 1).(($cp | get 2) + 1)"
    _ => $spec
  })

  if not ($new =~ '^[0-9]+\.[0-9]+\.[0-9]+$') {
    print -e $"error: '($spec)' is not valid semver \(X.Y.Z)."
    exit 2
  }
  let np = ($new | split row '.' | each {|x| $x | into int})
  if not (semver-gt $np $cp) {
    print -e $"error: target ($new) is not greater than current ($cur)."
    exit 1
  }
  if (^git rev-parse -q --verify $"refs/tags/v($new)" | complete).exit_code == 0 {
    print -e $"error: tag v($new) already exists."
    exit 1
  }

  print $"Bumping version: ($cur) -> ($new)"

  # Preflight: clean tree (so the bump lands as an isolated commit).
  if (not $no_commit) and (not $dry_run) {
    let status = (^git status --porcelain)
    if ($status | str trim | is-not-empty) {
      print -e "error: working tree is dirty — commit or stash so the bump is isolated."
      print -e $status
      exit 1
    }
  }

  # Apply: replace only the version line, preserving formatting.
  let repl = ("${1}" + $new + "${2}")
  let newtext = (open v.mod | str replace --regex "(version:\\s*')[^']+(')" $repl)
  print $"+ set version: '($new)' in v.mod"
  if not $dry_run { $newtext | save --raw --force v.mod }

  if not $no_commit {
    print "+ git add v.mod"
    if not $dry_run { ^git add v.mod }
    print $"+ git commit -m \"Bump version: v($cur) -> v($new)\""
    if not $dry_run { ^git commit -m $"Bump version: v($cur) -> v($new)" }
  }

  print $"Done: ($new)"
  if not $no_commit {
    print $"Next: nu scripts/release.nu   # tags v($new), pushes, creates the GitHub Release"
  }
}
