# Parses an rpemotes/dpemotes AnimationList.lua into emotes.json.
#
# Entry shape:   ["key"] = { dictionary, animation, label, targetEmote, AnimationOptions = {...} }
# Scenarios:     ["key"] = { ScenarioType.X, "WORLD_HUMAN_CHEERING", label }
# Walks:         ["Key"] = { walkAnim, label }        <- label is at index 1, not 2
# Expressions:   ["Key"] = { moodAnim }               <- no label at all
#
# The formats in the wild differ more than they look:
#   * keys use BOTH quote styles      ["umbrella"]  and  ['umbrella2']
#   * table prefixes differ           RP.Emotes (rpemotes)  vs  DP.Emotes (dpemotes)
#   * indentation differs             4 spaces vs 3 vs tabs
#   * entries may be ONE line         ["drink"] = {"dict", "loop", "Drink", AnimationOptions = {...}}
#   * option names differ             onFootFlag = AnimFlag.LOOP  vs  EmoteLoop = true
# A line-oriented parser silently returns garbage on half of these, so this one
# brace-matches each entry and splits its body on top-level commas instead.
#
# Beyond the label we keep the objectively descriptive bits: the animation
# dictionary path, the clip / scenario name, any prop model, and the movement
# flag. Those are what let you tell what an emote actually is without knowing
# the name already.

param(
    [string]$Lua = "$PSScriptRoot\..\data\sources\rpemotes-reborn.lua",
    [string]$Out = "$PSScriptRoot\..\data\emotes.json",
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$text = [System.IO.File]::ReadAllText($Lua, [System.Text.Encoding]::UTF8)

$cmdOf = @{}
$cmdOf['Emotes']       = '/e'
$cmdOf['Dances']       = '/e'
$cmdOf['PropEmotes']   = '/e'
$cmdOf['AnimalEmotes'] = '/e'
# Shared emotes take /nearby, not /e. Both work, but they do different things:
# /e handshake plays the animation on you alone, /nearby handshake offers it to
# whoever is standing next to you. All 94 of them name a partner animation, so
# the paired form is the point of them -- a key that makes you shake hands with
# nobody is not what anyone put on a deck. Read off the town's own menu, which
# prints "/nearby (sitwithmepose)" under the highlighted entry, and confirmed in
# game: /e played it solo, /nearby answered that there was no one nearby.
$cmdOf['Shared']       = '/nearby'
$cmdOf['Expressions']  = '/mood'
$cmdOf['Walks']        = '/walk'

# ---- strips one layer of matching quotes; $null when the token is not a string
function Get-LuaString([string]$t) {
    if ($null -eq $t) { return $null }
    $t = $t.Trim()
    if ($t.Length -ge 2) {
        if (($t[0] -eq '"' -and $t[-1] -eq '"') -or ($t[0] -eq "'" -and $t[-1] -eq "'")) {
            return $t.Substring(1, $t.Length - 2)
        }
    }
    return $null
}

# ---- index of the '}' matching the '{' at $open, skipping strings and comments
function Find-Close([string]$s, [int]$open) {
    $depth = 0
    $i = $open
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq '"' -or $c -eq "'") {
            $q = $c; $i++
            while ($i -lt $s.Length) {
                if ($s[$i] -eq '\') { $i += 2; continue }
                if ($s[$i] -eq $q) { break }
                $i++
            }
        }
        elseif ($c -eq '-' -and $i + 1 -lt $s.Length -and $s[$i+1] -eq '-') {
            while ($i -lt $s.Length -and $s[$i] -ne "`n") { $i++ }
            continue
        }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $i } }
        $i++
    }
    return -1
}

# ---- splits a table body on commas that sit at nesting depth 0
function Split-TopLevel([string]$body) {
    $parts = New-Object System.Collections.ArrayList
    $depth = 0; $start = 0; $i = 0
    while ($i -lt $body.Length) {
        $c = $body[$i]
        if ($c -eq '"' -or $c -eq "'") {
            $q = $c; $i++
            while ($i -lt $body.Length) {
                if ($body[$i] -eq '\') { $i += 2; continue }
                if ($body[$i] -eq $q) { break }
                $i++
            }
        }
        elseif ($c -eq '-' -and $i + 1 -lt $body.Length -and $body[$i+1] -eq '-') {
            while ($i -lt $body.Length -and $body[$i] -ne "`n") { $i++ }
            continue
        }
        elseif ($c -eq '{' -or $c -eq '(' -or $c -eq '[') { $depth++ }
        elseif ($c -eq '}' -or $c -eq ')' -or $c -eq ']') { $depth-- }
        elseif ($c -eq ',' -and $depth -eq 0) {
            [void]$parts.Add($body.Substring($start, $i - $start))
            $start = $i + 1
        }
        $i++
    }
    if ($start -lt $body.Length) { [void]$parts.Add($body.Substring($start)) }

    $clean = New-Object System.Collections.ArrayList
    foreach ($p in $parts) {
        $t = ($p -replace '(?m)--.*$', '').Trim()
        if ($t -ne '') { [void]$clean.Add($t) }
    }
    return $clean
}

# ---- where does each section start? (RP.Emotes / DP.Emotes / ...)
$sectionAt = @()
foreach ($m in [regex]::Matches($text, '(?m)^[A-Za-z_]{2,6}\.(\w+)\s*=\s*\{')) {
    $sectionAt += [pscustomobject]@{ Index = $m.Index; Name = $m.Groups[1].Value }
}
$sectionAt = $sectionAt | Sort-Object Index
function Section-For([int]$idx) {
    $cur = $null
    foreach ($s in $sectionAt) { if ($s.Index -lt $idx) { $cur = $s.Name } else { break } }
    return $cur
}

# ---- every entry key, either quote style, any indentation
$result = New-Object System.Collections.ArrayList
$entryRe = [regex]'(?m)^[ \t]+\[\s*(["''])(.+?)\1\s*\]\s*=\s*\{'

foreach ($m in $entryRe.Matches($text)) {
    $section = Section-For $m.Index
    if (-not $section -or -not $cmdOf.ContainsKey($section)) {
        if (-not $section) { continue }
    }
    $key = $m.Groups[2].Value

    $open  = $text.IndexOf('{', $m.Index + $m.Length - 1)
    $close = Find-Close $text $open
    if ($close -lt 0) { continue }
    $body = $text.Substring($open + 1, $close - $open - 1)

    $positional = New-Object System.Collections.ArrayList
    $named = @{}
    foreach ($tok in (Split-TopLevel $body)) {
        if ($tok -match '^(\w+)\s*=\s*(?s)(.+)$') {
            $fname = $matches[1]; $fval = $matches[2].Trim()
            if ($fval.StartsWith('{')) {
                # AnimationOptions = { ... } -- pull its scalars up
                $innerClose = Find-Close $fval 0
                if ($innerClose -gt 0) {
                    foreach ($sub in (Split-TopLevel $fval.Substring(1, $innerClose - 1))) {
                        if ($sub -match '^(\w+)\s*=\s*(?s)(.+)$') {
                            $sn = $matches[1]; $sv = $matches[2].Trim()
                            if (-not $sv.StartsWith('{') -and -not $named.ContainsKey($sn)) { $named[$sn] = $sv }
                        }
                    }
                }
            }
            elseif (-not $named.ContainsKey($fname)) { $named[$fname] = $fval }
        }
        else { [void]$positional.Add($tok) }
    }

    $labelIdx = if ($section -eq 'Walks') { 1 } else { 2 }
    $display = $key
    if ($positional.Count -gt $labelIdx) {
        $s = Get-LuaString $positional[$labelIdx]
        if ($s) { $display = $s }
    }

    $dict = ''
    if ($positional.Count -gt 0) { $x = Get-LuaString $positional[0]; $dict = if ($x) { $x } else { $positional[0] } }

    $anim = ''
    if ($positional.Count -gt 1 -and $section -ne 'Walks' -and $section -ne 'Expressions') {
        $x = Get-LuaString $positional[1]; $anim = if ($x) { $x } else { $positional[1] }
    }

    # Expressions carry one mood animation plus an optional label, but the two
    # resource families lay it out differently:
    #   current  ["Angry"]   = {"mood_angry_1"}
    #   current  ["Grumpy2"] = {"mood_drivefast_1", "Grumpy 2"}
    #   original ["Angry"]   = {"Expression", "mood_angry_1"}   <- literal marker first
    # Skip the marker, take the animation, and the label is whatever follows it.
    # Without this every mood looks like it changed between versions when none did.
    if ($section -eq 'Expressions' -and $positional.Count -gt 0) {
        $idx = 0
        if ((Get-LuaString $positional[0]) -eq 'Expression') { $idx = 1 }
        if ($positional.Count -gt $idx) {
            $a = Get-LuaString $positional[$idx]
            if ($a) { $dict = $a }
        }
        $display = $key
        if ($positional.Count -gt ($idx + 1)) {
            $lbl = Get-LuaString $positional[$idx + 1]
            if ($lbl) { $display = $lbl }
        }
        $anim = ''
    }

    # Scenario markers are the same idea spelled differently across versions:
    #   original  Scenario / MaleScenario / FemaleScenario / ScenarioObject
    #   current   ScenarioType.SCENARIO / .MALE / .FEMALE / .OBJECT
    # Normalise so the same scenario does not read as "changed between versions".
    switch -Regex ($dict) {
        '^ScenarioType\.(\w+)$' { $dict = 'Scenario:' + $matches[1].ToUpperInvariant() }
        '^(Male|Female)Scenario$' { $dict = 'Scenario:' + $matches[1].ToUpperInvariant() }
        '^ScenarioObject$'        { $dict = 'Scenario:OBJECT' }
        '^Scenario$'              { $dict = 'Scenario:SCENARIO' }
    }

    $partner = ''
    if ($positional.Count -gt 3) { $x = Get-LuaString $positional[3]; if ($x) { $partner = $x } }

    function Named([string]$n) {
        if (-not $named.ContainsKey($n)) { return '' }
        $v = Get-LuaString $named[$n]
        if ($v) { return $v }
        return $named[$n]
    }

    # newer resources use onFootFlag = AnimFlag.X; the original dpemotes used booleans
    $flag = (Named 'onFootFlag') -replace '^AnimFlag\.', ''
    if (-not $flag) {
        if ((Named 'EmoteLoop')   -match 'true') { $flag = 'LOOP' }
        elseif ((Named 'EmoteMoving') -match 'true') { $flag = 'MOVING' }
    }

    # Four things the author of the list states outright about an emote. They
    # were being dropped, which mattered most for AdultAnimation: without it
    # there is no way to tell that "showboobs" and the five "wank" entries are
    # what they are, and they sat in the ordinary list like anything else.
    # Presence is the whole fact -- the values are tables or `true`, and none of
    # them says anything further that a person picking buttons needs.
    $adult    = if ($named.ContainsKey('AdultAnimation'))     { 1 } else { 0 }
    $abusable = if ($named.ContainsKey('abusable'))           { 1 } else { 0 }
    $ptfx     = if ($named.ContainsKey('PtfxName'))           { 1 } else { 0 }

    # vehicleRequirement is NOT a yes/no. It takes two opposite values --
    # REQUIRED (16 entries, only works while in a vehicle) and NOT_ALLOWED
    # (29, only works while out of one). Reading it as "has the key" labels
    # two thirds of them backwards.
    $vehicle = 0
    if ($named.ContainsKey('vehicleRequirement')) {
        $vr = "$($named['vehicleRequirement'])"
        # anchored on the dot: the enum's own name is "VehicleRequirement",
        # and a bare 'REQUIRED' match invites confusion with it
        if     ($vr -match '\.NOT_ALLOWED') { $vehicle = 2 }
        elseif ($vr -match '\.REQUIRED')    { $vehicle = 1 }
    }

    [void]$result.Add([pscustomobject]@{
        Section = $section
        Command = $cmdOf[$section]
        Name    = $key
        Display = $display
        Dict    = $dict
        Anim    = $anim
        Prop    = (Named 'Prop')
        # the key is SecondProp; "Prop2" was never a key in either source, so
        # this column had silently been empty for every row
        Prop2   = (Named 'SecondProp')
        Flag    = $flag
        Exit    = (Named 'ExitEmote')
        Partner = $partner
        Adult    = $adult
        Abusable = $abusable
        Vehicle  = $vehicle
        Ptfx     = $ptfx
    })
}

# The source files really do declare the same key twice inside one table --
# andristum's Walks has ["Drunk"] on two consecutive lines. Lua keeps the LAST
# assignment, so do the same instead of counting both.
$dedup = [ordered]@{}
foreach ($e in $result) { $dedup["$($e.Section)|$($e.Name)"] = $e }
$dropped = $result.Count - $dedup.Count
$result = @($dedup.Values)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Out, ($result | ConvertTo-Json -Depth 4), $utf8NoBom)

if (-not $Quiet) {
    "total: $($result.Count)   (重複キー $dropped 件を後勝ちで統合)"
    $result | Group-Object Section | Sort-Object Name | ForEach-Object { "  {0,-18} {1}" -f $_.Name, $_.Count }
    ""
    "with prop   : $(@($result | Where-Object { $_.Prop }).Count)"
    "with prop2  : $(@($result | Where-Object { $_.Prop2 }).Count)"
    "with flag   : $(@($result | Where-Object { $_.Flag }).Count)"
    "with partner: $(@($result | Where-Object { $_.Partner }).Count)"
    "adult       : $(@($result | Where-Object { $_.Adult }).Count)"
    "abusable    : $(@($result | Where-Object { $_.Abusable }).Count)"
    "vehicle req : $(@($result | Where-Object { $_.Vehicle -eq 1 }).Count)"
    "vehicle no  : $(@($result | Where-Object { $_.Vehicle -eq 2 }).Count)"
    "ptfx        : $(@($result | Where-Object { $_.Ptfx }).Count)"
}
