# Works out which emotes are likely to exist on ANY server, not just one.
#
# FiveM itself ships no emotes -- `citizen\resources` contains only "icons".
# /e comes entirely from community resources, so "generally usable" can only
# mean "present in the emote resources that servers actually run".
#
# So: parse several of them and count how many contain each emote name.
#
# Lineage matters when reading the result. rpemotes-reborn, Scullyy/dpemotes and
# AamiRobin/dpemotes are all the same RP.* family, so agreeing with each other
# proves little. andristum/dpemotes is the older, independent DP.* original --
# an emote in BOTH families has been around across the whole ecosystem, which is
# the strongest signal available without querying servers.
#
# This is a likelihood, never a guarantee: servers edit their lists, rename
# resources, and ship escrowed builds. The only proof is pressing the button.

param(
    [string]$SourceDir = "$PSScriptRoot\..\data\sources",
    [string]$Base      = 'rpemotes-reborn',      # whose naming/labels we keep
    [string]$Out       = "$PSScriptRoot\..\data\emotes.json",
    [string]$TempDir   = "$env:TEMP\deckbuilder-parse"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

$sources = Get-ChildItem $SourceDir -Filter *.lua | Sort-Object Name
if (-not $sources) { throw "no .lua sources in $SourceDir" }

$parsed = @{}
foreach ($s in $sources) {
    $id = [System.IO.Path]::GetFileNameWithoutExtension($s.Name)
    $json = Join-Path $TempDir "$id.json"
    & "$PSScriptRoot\parse-emotes.ps1" -Lua $s.FullName -Out $json -Quiet
    # PowerShell 5.1's ConvertFrom-Json emits the whole array as ONE object, so
    # @( ... | ConvertFrom-Json ) yields a 1-element array holding the real array.
    # Assigning from the pipeline first unrolls it properly.
    $rows = [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $rows = @($rows)
    $parsed[$id] = $rows
    "{0,-22} {1,5} entries" -f $id, $rows.Count
}

if (-not $parsed.ContainsKey($Base)) { throw "base source '$Base' not found among: $($parsed.Keys -join ', ')" }

# Having the emote in the table is not enough -- the resource also has to REGISTER
# the chat command. It does not, always:
#
#   /e, /emote   original Client/Emote.lua:63-64   current client/Keybinds.lua:13-14
#                both unconditional -> the safe one
#   /walk        original Client/Emote.lua:71      current client/Walk.lua:128-129
#                current gates it behind Config.WalkingStylesEnabled
#   /mood        NOT IN THE ORIGINAL AT ALL. Only current client/Expressions.lua:15,
#                and gated behind Config.ExpressionsEnabled.
#                The original has the expression data and a menu entry, but no way
#                to type it -- so /mood Angry does nothing on an original-based server.
#   /nearby      the shared emotes. Seen working on a current server (2026-09-01);
#                whether the original registers it has NOT been checked, and the
#                client code for it is not in hand. Left out of the original's
#                list rather than assumed, so shared emotes stop counting as
#                "works anywhere" until someone confirms it. Being wrong in this
#                direction only understates compatibility; the other way round
#                would promise something that does not work.
#
# Counting a mood as "in both resources" because the NAME appears in both tables
# would be wrong: the command that reaches it does not exist on one of them.
$commandsOf = @{}
$commandsOf['rpemotes-reborn']    = @('/e', '/walk', '/mood', '/nearby')
$commandsOf['dpemotes-andristum'] = @('/e', '/walk')

function Has-Command([string]$sourceId, [string]$command) {
    if (-not $commandsOf.ContainsKey($sourceId)) { return $true }   # unknown source: assume yes
    return $commandsOf[$sourceId] -contains $command
}

# command+name -> which sources have it. The COMMAND has to be part of the key:
# "Drunk" exists as both a walk (/walk Drunk) and a mood (/mood Drunk), so
# matching on the name alone silently pairs up two unrelated things.
# Matched case-insensitively because /e, /walk and /mood lowercase the argument.
# plain arrays: an empty ArrayList assigned into a hashtable gets unrolled by
# PowerShell and the later .Add() then fails with "collection was of a fixed size"
$presence = @{}
foreach ($id in $parsed.Keys) {
    foreach ($e in $parsed[$id]) {
        if (-not $e.Command) { continue }            # Exits has no chat command
        if (-not (Has-Command $id $e.Command)) { continue }   # command not registered here
        $k = $e.Command + '|' + $e.Name.ToLowerInvariant()
        if (-not $presence.ContainsKey($k)) { $presence[$k] = @() }
        if ($presence[$k] -notcontains $id) { $presence[$k] += $id }
    }
}

# the DP.* original, if present, is the independent lineage
$original = $parsed.Keys | Where-Object { $_ -match 'andristum' } | Select-Object -First 1

# Being in both resources only means the COMMAND is accepted on both. Some names
# were re-pointed at a different animation between versions -- /e dancesilly8 is
# a different dance in each. Those still work everywhere but do not look the same,
# which matters when you are building a deck you expect to behave predictably.
$originAnim = @{}
if ($original) {
    foreach ($e in $parsed[$original]) {
        if (-not $e.Command) { continue }
        $originAnim[$e.Command + '|' + $e.Name.ToLowerInvariant()] = "$($e.Dict)|$($e.Anim)"
    }
}

# NOTE: $out would collide with the [string]$Out parameter -- PowerShell variable
# names are case-insensitive, and the type constraint would coerce the list to a string.
$rowsOut = New-Object System.Collections.ArrayList
foreach ($e in $parsed[$Base]) {
    if (-not $e.Command) { continue }
    $k = $e.Command + '|' + $e.Name.ToLowerInvariant()
    $inSources = @($presence[$k])
    [void]$rowsOut.Add([pscustomobject]@{
        Section  = $e.Section
        Command  = $e.Command
        Name     = $e.Name
        Display  = $e.Display
        Dict     = $e.Dict
        Anim     = $e.Anim
        Prop     = $e.Prop
        Prop2    = $e.Prop2
        Flag     = $e.Flag
        Exit     = $e.Exit
        Partner  = $e.Partner
        # stated outright by the list's author; carried through unchanged
        Adult    = $e.Adult
        Abusable = $e.Abusable
        Vehicle  = $e.Vehicle
        Ptfx     = $e.Ptfx
        Seen     = $inSources.Count
        Total    = $parsed.Keys.Count
        InOrigin = if ($original -and $inSources -contains $original) { 1 } else { 0 }
        # 1 = in the original but pointing at a DIFFERENT animation there
        Drifted  = if ($originAnim.ContainsKey($k) -and $originAnim[$k] -ne "$($e.Dict)|$($e.Anim)") { 1 } else { 0 }
    })
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Out, ($rowsOut | ConvertTo-Json -Depth 4), $utf8NoBom)

""
"base    : $Base"
"origin  : $(if ($original) { $original } else { '(none -- no independent lineage in the set)' })"
"emotes  : $($rowsOut.Count)"
"wrote   : $Out"
""
"chat commands each resource registers:"
foreach ($id in ($parsed.Keys | Sort-Object)) { "  {0,-22} {1}" -f $id, ($(if ($commandsOf.ContainsKey($id)) { $commandsOf[$id] -join ' + ' } else { '(unknown)' }) -join ', ') }
""
"how many of the $($parsed.Keys.Count) resources contain each emote:"
$rowsOut | Group-Object Seen | Sort-Object { [int]$_.Name } -Descending | ForEach-Object {
    "  {0} / {1} resources : {2,5}" -f $_.Name, $parsed.Keys.Count, $_.Count
}
""
if ($original) {
    $n = @($rowsOut | Where-Object { $_.InOrigin -eq 1 }).Count
    "also in the independent original ($original) : $n"
    "  -> these are the safest bet on an unknown server"
}
""
"same command but a DIFFERENT animation in the original:"
"  $(@($rowsOut | Where-Object { $_.Drifted -eq 1 }).Count)"
""
"emotes only in $Base (newest additions, least portable):"
$onlyBase = @($rowsOut | Where-Object { $_.Seen -eq 1 })
"  $($onlyBase.Count)"
