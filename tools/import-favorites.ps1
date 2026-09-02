# Pulls the emote menu's "favorites" list out of FiveM's client key-value store
# and prints it in the format the builder's "+" -> paste box accepts.
#
# Why this exists: you cannot pick emotes off a list of English names unless you
# already know the animations. In-game you can SEE them. So star the ones you
# want in the emote menu's favorites tab, then run this.
#
# Where the data lives (confirmed from FiveM source, KVScriptFunctions.cpp):
#   store : LevelDB at fxd:/kvs/  ->  %APPDATA%\CitizenFX\kvs
#   key   : "res:" + resourceName + ":" + key
#   so rpemotes-reborn's favorites land under  res:<resource>:<keybindKVP>_favorites
#   and the value is JSON:  { "<emote id>": { "label": "...", ... }, ... }
#
# Values sit as plain text right after the key in the .ldb/.log blocks, so this
# does not need a real LevelDB reader -- it finds the key and brace-matches the
# JSON that follows.

param(
    [string]$Kvs = "$env:APPDATA\CitizenFX\kvs",
    [string]$Key,                       # exact key to dump, instead of hunting for favorites
    [switch]$List,                      # just show every key in the store
    [string]$Command = '/e',            # chat command to emit for each emote
    [string]$Out = "$PSScriptRoot\..\data\favorites.txt"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Kvs)) { throw "KVS store not found: $Kvs  (has FiveM ever run on this account?)" }

$latin1 = [System.Text.Encoding]::GetEncoding(28591)

# read every table in the store, tolerating files FiveM currently holds open
$blob = New-Object System.Text.StringBuilder
foreach ($f in Get-ChildItem $Kvs -File | Sort-Object LastWriteTime) {
    try {
        $fs = [System.IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')
        $buf = New-Object byte[] $fs.Length
        [void]$fs.Read($buf, 0, $buf.Length)
        $fs.Close()
        [void]$blob.Append($latin1.GetString($buf))
    } catch {
        Write-Warning "could not read $($f.Name): $($_.Exception.Message.Split('.')[0])"
    }
}
$text = $blob.ToString()

$keys = [regex]::Matches($text, 'res:[A-Za-z0-9_\-\.]{1,64}:[A-Za-z0-9_\-\.]{1,96}') |
        ForEach-Object { $_.Value } | Sort-Object -Unique

if ($List) {
    "store: $Kvs"
    "keys : $($keys.Count)"
    $keys | ForEach-Object { "  $_" }
    return
}

# pulls the JSON value that follows a key (skips LevelDB's internal suffix bytes)
function Get-JsonAfter([string]$hay, [string]$key) {
    $i = $hay.IndexOf($key, [System.StringComparison]::Ordinal)
    if ($i -lt 0) { return $null }
    $start = $hay.IndexOf('{', $i + $key.Length)
    if ($start -lt 0 -or $start - ($i + $key.Length) -gt 64) { return $null }

    $depth = 0; $inStr = $false; $esc = $false
    for ($p = $start; $p -lt $hay.Length; $p++) {
        $c = $hay[$p]
        if ($esc) { $esc = $false; continue }
        if ($c -eq '\') { $esc = $true; continue }
        if ($c -eq '"') { $inStr = -not $inStr; continue }
        if ($inStr) { continue }
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $hay.Substring($start, $p - $start + 1) } }
    }
    return $null
}

if ($Key) {
    $json = Get-JsonAfter $text $Key
    if (-not $json) { throw "no JSON value found after '$Key'" }
    "key   : $Key"
    "bytes : $($json.Length)"
    $json
    return
}

$favKeys = @($keys | Where-Object { $_ -match 'favorit' })
if (-not $favKeys.Count) {
    "store : $Kvs"
    "keys  : $($keys.Count)"
    $keys | ForEach-Object { "  $_" }
    ""
    "No '*favorit*' key in the store -- nothing has been starred yet."
    ""
    "To fill it:"
    "  1. In game, open the emote menu and go to the favorites tab (お気に入り)."
    "  2. Star the emotes you actually want. You can see them there, which is the point."
    "  3. Leave the server (rpemotes writes with SetResourceKvpNoSync, so it may only"
    "     land on disk once the game shuts down cleanly)."
    "  4. Run this script again."
    return
}

$rows = @()
foreach ($k in $favKeys) {
    $json = Get-JsonAfter $text $k
    if (-not $json) { Write-Warning "found key '$k' but could not read its value"; continue }
    "key   : $k"
    $obj = $json | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) {
        if ($null -eq $p.Value) { continue }        # rpemotes leaves JSON nulls when you un-star
        $label = if ($p.Value.label) { $p.Value.label } else { $p.Name }
        $rows += "{0} | {1} | {2}" -f $p.Name, $label, $Command
    }
}

if (-not $rows.Count) { "key found but no live entries (all un-starred)."; return }

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Out, ($rows -join "`r`n"), $utf8NoBom)

""
"emotes: $($rows.Count)"
"wrote : $Out"
""
"Paste this into the builder:  ＋  ->  手打ちリスト"
"---------------------------------------------"
$rows | ForEach-Object { $_ }
