# Compares a zip produced by the builder against a real export from the
# Stream Deck app, so "it should import" stops being an assumption.
#
# It checks SHAPE, not content: the two profiles hold different buttons, but if
# the generated one is missing package.json, or puts the .sdProfile at the zip
# root instead of under Profiles/, or writes a BOM, the app will reject it.
# Those are exactly the three things the first version of this generator got
# wrong, and none of them were visible without a real export to compare to.

param(
    [Parameter(Mandatory = $true)][string]$Generated,
    [string]$Reference = "$env:USERPROFILE\Downloads\Default Profile.streamDeckProfile"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-Shape([string]$path) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
    $shape = [ordered]@{
        entries      = $zip.Entries.Count
        hasPackage   = $false
        package      = $null
        sdProfileAt  = $null
        topManifest  = $null
        pageCount    = 0
        bom          = @()
    }
    foreach ($e in $zip.Entries) {
        if ($e.FullName -eq 'package.json') {
            $shape.hasPackage = $true
            $shape.package = (New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json
        }
        if ($e.FullName -match '^(.*?)([^/]+\.sdProfile)/manifest\.json$') {
            $shape.sdProfileAt = $matches[1]        # '' = zip root, 'Profiles/' = correct
            $shape.topManifest = (New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json
        }
        if ($e.FullName -match '\.sdProfile/Profiles/[^/]+/manifest\.json$') { $shape.pageCount++ }

        if ($e.Name -eq 'manifest.json' -or $e.Name -eq 'package.json') {
            $ms = New-Object System.IO.MemoryStream
            $e.Open().CopyTo($ms)
            $b = $ms.ToArray()
            if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $shape.bom += $e.FullName }
        }
    }
    $zip.Dispose()
    return $shape
}

if (-not (Test-Path $Reference)) { throw "reference export not found: $Reference" }
if (-not (Test-Path $Generated)) { throw "generated zip not found: $Generated" }

$ref = Get-Shape $Reference
$gen = Get-Shape $Generated

$fail = 0
function Check([string]$label, $refVal, $genVal, [switch]$MustMatch) {
    $ok = if ($MustMatch) { "$refVal" -eq "$genVal" } else { $true }
    $mark = if ($MustMatch) { if ($ok) { 'OK  ' } else { 'FAIL' } } else { '--  ' }
    "{0}  {1,-26} 手本: {2,-28} 生成: {3}" -f $mark, $label, $refVal, $genVal
    if ($MustMatch -and -not $ok) { $script:fail++ }
}

"reference : $Reference"
"generated : $Generated"
""
Check 'package.json あり'   $ref.hasPackage            $gen.hasPackage            -MustMatch
Check '.sdProfile の位置'   "'$($ref.sdProfileAt)'"    "'$($gen.sdProfileAt)'"    -MustMatch
Check 'FormatVersion'       $ref.package.FormatVersion $gen.package.FormatVersion -MustMatch
Check 'OSType'              $ref.package.OSType        $gen.package.OSType        -MustMatch
Check 'manifest Version'    $ref.topManifest.Version   $gen.topManifest.Version   -MustMatch
Check 'Pages.Current'       $ref.topManifest.Pages.Current $gen.topManifest.Pages.Current -MustMatch
Check 'BOM の数'            $ref.bom.Count             $gen.bom.Count             -MustMatch
""
Check 'DeviceModel'         $ref.package.DeviceModel   $gen.package.DeviceModel
Check 'エントリ数'          $ref.entries               $gen.entries
Check 'ページ数'            $ref.pageCount             $gen.pageCount

# Device.UUID must be a plain GUID, not a hardware serial (those look like
# "@(n)[...]" and identify one particular deck on one particular machine)
$genUuid = "$($gen.topManifest.Device.UUID)"
$isGuid = $genUuid -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
"{0}  {1,-26} {2}" -f $(if ($isGuid) { 'OK  ' } else { 'FAIL' }), 'Device.UUID が素のGUID', $genUuid
if (-not $isGuid) { $fail++ }

# every action UUID used must be declared in RequiredPlugins
$zip = [System.IO.Compression.ZipFile]::OpenRead($Generated)
$used = New-Object System.Collections.Generic.HashSet[string]
foreach ($e in $zip.Entries) {
    if ($e.FullName -notmatch '\.sdProfile/Profiles/[^/]+/manifest\.json$') { continue }
    $t = (New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)).ReadToEnd()
    foreach ($m in [regex]::Matches($t, '"UUID"\s*:\s*"([^"]+)"')) { [void]$used.Add($m.Groups[1].Value) }
}
$zip.Dispose()
$declared = @($gen.package.RequiredPlugins)
$missing = @($used | Where-Object { $declared -notcontains $_ })
"{0}  {1,-26} 使用 {2} 種 / 宣言 {3} 種{4}" -f `
    $(if ($missing.Count -eq 0) { 'OK  ' } else { 'FAIL' }), 'RequiredPlugins の網羅', `
    $used.Count, $declared.Count, $(if ($missing.Count) { "  未宣言: $($missing -join ', ')" } else { '' })
if ($missing.Count) { $fail++ }

""
if ($fail -eq 0) { "STRUCTURE MATCHES  ($($used.Count) 種のアクションを使用)" }
else { "MISMATCH: $fail 件"; exit 1 }
