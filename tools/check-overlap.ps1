# Two different questions about duplicates, both worth answering:
#
#  1) ACROSS the two resources -- the 512 names that exist in both: do they
#     actually point at the SAME animation? "present in both" only means the
#     command is accepted; if the current version re-pointed a name at a
#     different clip, the same /e gives a different move on different servers.
#
#  2) WITHIN one resource -- several names can share one animation
#     (dictionary + clip). Those are functional duplicates: putting both on the
#     deck gives you two buttons that do the same thing.

param(
    [string]$SourceDir = "$PSScriptRoot\..\data\sources",
    [string]$Origin    = 'dpemotes-andristum',
    [string]$Current   = 'rpemotes-reborn',
    [string]$TempDir   = "$env:TEMP\deckbuilder-overlap"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

function Load([string]$id) {
    $json = Join-Path $TempDir "$id.json"
    & "$PSScriptRoot\parse-emotes.ps1" -Lua (Join-Path $SourceDir "$id.lua") -Out $json -Quiet
    # assign from the pipeline first: PS 5.1 emits the array as one object
    $rows = [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    return @($rows)
}

$o = Load $Origin
$c = Load $Current
"{0,-24} {1,5} entries" -f $Origin, $o.Count
"{0,-24} {1,5} entries" -f $Current, $c.Count

# ---------- 1) across the two ----------
$oMap = @{}
# key on command+name: "Drunk" is both a walk and a mood
foreach ($e in $o) { if ($e.Command) { $oMap[$e.Command + '|' + $e.Name.ToLowerInvariant()] = $e } }

$same = 0; $diff = 0; $examples = New-Object System.Collections.ArrayList
foreach ($e in $c) {
    if (-not $e.Command) { continue }
    $k = $e.Command + '|' + $e.Name.ToLowerInvariant()
    if (-not $oMap.ContainsKey($k)) { continue }
    $x = $oMap[$k]
    if ($x.Dict -eq $e.Dict -and $x.Anim -eq $e.Anim) { $same++ }
    else {
        $diff++
        if ($examples.Count -lt 12) {
            [void]$examples.Add(("  {0,-6} {1,-16} 原典 {2} {3}   →   現行 {4} {5}" -f `
                $e.Command, $e.Name, $x.Dict, $x.Anim, $e.Dict, $e.Anim))
        }
    }
}

""
"=== 1) 両方にある名前の中身は一致するか ==="
"  両方にある      : $($same + $diff)"
"  中身も同じ      : $same"
"  中身が違う      : $diff"
if ($diff) { ""; "  中身が違う例:"; $examples | ForEach-Object { $_ } }

# ---------- 2) inside the current one ----------
""
"=== 2) 現行の中で同じアニメを指す名前 ==="
$byAnim = @{}
foreach ($e in $c) {
    if (-not $e.Command) { continue }
    if (-not $e.Dict -and -not $e.Anim) { continue }
    $k = "$($e.Dict)|$($e.Anim)|$($e.Prop)"
    if (-not $byAnim.ContainsKey($k)) { $byAnim[$k] = @() }
    $byAnim[$k] += $e.Name
}
$dupGroups = @($byAnim.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
$dupNames = 0
foreach ($g in $dupGroups) { $dupNames += $g.Value.Count }

"  名前の総数            : $(@($c | Where-Object { $_.Command }).Count)"
"  異なるアニメの数      : $($byAnim.Count)"
"  複数の名前が付いた数  : $($dupGroups.Count)"
"  そこに属する名前の数  : $dupNames"
""
"  多いものから:"
$dupGroups | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 10 | ForEach-Object {
    "    {0,2} 個: {1}" -f $_.Value.Count, (($_.Value | Select-Object -First 8) -join ', ')
    "         ← {0}" -f $_.Key
}
