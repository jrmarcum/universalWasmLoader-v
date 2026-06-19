# Use `zig cc` as V's C compiler on Windows (no Git Bash required).
#
# V passes its flags in a response file (cc @file.rsp) and hardcodes
# `-Wl,-stack=...`, which zig's bundled lld rejects. We rewrite the response
# file to drop that one flag (zig's default stack size is fine) and force the
# MinGW-GNU target so the wasmtime GNU import library links.
$ErrorActionPreference = 'Stop'

$out = @()
foreach ($a in $args) {
    if ($a -like '@*' -and $a.EndsWith('.rsp')) {
        $rsp = $a.Substring(1)
        $filtered = $rsp + '.zig.rsp'
        (Get-Content -Raw -LiteralPath $rsp) -replace '-Wl,-stack=\d+', '' |
            Set-Content -NoNewline -Encoding Ascii -LiteralPath $filtered
        $out += '@' + $filtered
    } else {
        $out += $a
    }
}

& zig cc -target x86_64-windows-gnu @out
exit $LASTEXITCODE
