# Writes the whole catalogue out as a spreadsheet to classify by hand.
#
# Why a sheet at all: there is no genre in the source. The Lua has seven
# sections and nothing else, the animation dictionary is 753 different prefixes
# of which 561 occur exactly once, and guessing from names was measured wrong
# often enough to throw away. Someone has to look. This is the sheet they look at.
#
# Two things make 1,881 rows survivable:
#   * rows are ordered by name STEM, so "sunbathe" 1-4 sit together and one
#     decision fills four rows by dragging down. 341 stems cover 1,244 rows.
#   * every column except the first two is a fact taken from the source, not a
#     guess -- so the sheet answers "what do I already know about this row?"
#     without opening anything else.
#
# Deliberately NOT included: a suggested genre. A pre-filled guess gets accepted
# rather than checked, which is exactly how the discarded hint tags went wrong.
# The 手がかり column carries the raw word found in the dictionary path instead,
# which is evidence rather than a conclusion.
#
# 分類 comes back in on the コマンド column, which is unique and stable.

param(
    [string]$In  = "$PSScriptRoot\..\data\emotes.json",
    [string]$Out = "$PSScriptRoot\..\data\emotes-classify.csv"
)

$ErrorActionPreference = 'Stop'

$catOf = @{
    'Emotes' = 'ふつうの動作'; 'Dances' = 'ダンス'; 'PropEmotes' = '物を持つ'
    'Walks'  = '歩き方';       'Shared' = '2人でやる'; 'Expressions' = '表情'
    'AnimalEmotes' = '動物のとき限定'
}

# Words that appear inside GTA's own dictionary paths and mean what they say.
# Reported as-is; whether the emote "is" that is for the person to decide.
$WORDS = @('dancing','dancers','nightclub','smoking','smoke','drinking','drink',
           'eat','sitting','seat','bench','lean','clipboard','phone','guitar',
           'fishing','golf','yoga','pushup','salute','wave','clap','kiss',
           'fight','melee','aiming','gun','sleep','stretch','cheer')

# PS 5.1 collapses the array into one object when the pipeline is wrapped in @().
# Assigning from the pipeline first unrolls it properly.
$all = Get-Content $In -Raw -Encoding UTF8 | ConvertFrom-Json
$rows = @($all)
if ($rows.Count -eq 0) { throw "no rows in $In" }

function Esc([string]$s) {
    if ($null -eq $s) { return '""' }
    '"' + ($s -replace '"', '""') + '"'
}

$table = foreach ($e in $rows) {
    $stem = ($e.Name.ToLowerInvariant() -replace '[ _-]*\d+$', '')
    $hay  = ("$($e.Dict) $($e.Anim)").ToLowerInvariant()
    $hits = @($WORDS | Where-Object { $hay.Contains($_) })

    $car = switch ([int]$e.Vehicle) { 1 { '車の中だけ' } 2 { '車の外だけ' } default { '' } }

    [pscustomobject]@{
        Stem     = $stem
        Command  = "$($e.Command) $($e.Name)"
        Display  = $e.Display
        Cat      = $(if ($catOf.ContainsKey($e.Section)) { $catOf[$e.Section] } else { $e.Section })
        Std      = $(if ($e.Total -gt 0 -and $e.Seen -ge $e.Total) { '○' } else { '' })
        Loop     = $(if ($e.Flag -match 'LOOP')   { '○' } else { '' })
        Moving   = $(if ($e.Flag -match 'MOVING') { '○' } else { '' })
        Prop     = $e.Prop
        Pair     = $e.Partner
        Car      = $car
        Adult    = $(if ($e.Adult) { '○' } else { '' })
        Ptfx     = $(if ($e.Ptfx)  { '○' } else { '' })
        Hint     = ($hits -join ' ')
        Dict     = $e.Dict
        Anim     = $e.Anim
    }
}

# stem first so variants are adjacent, then the command so the order is stable
$sorted = $table | Sort-Object Stem, Command

$header = @('分類','メモ','コマンド','表示名','いまの区分','高互換','止めるまで続く',
            '歩ける','小道具','相手','車','成人向け','効果','手がかり','Dict','Anim')

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add((($header | ForEach-Object { Esc $_ }) -join ','))
foreach ($t in $sorted) {
    $lines.Add(((@('', '', $t.Command, $t.Display, $t.Cat, $t.Std, $t.Loop, $t.Moving,
                   $t.Prop, $t.Pair, $t.Car, $t.Adult, $t.Ptfx, $t.Hint, $t.Dict, $t.Anim) |
                 ForEach-Object { Esc $_ }) -join ','))
}

# WITH a BOM: Excel reads a BOM-less UTF-8 csv as the local codepage and turns
# every Japanese heading to mojibake. Google Sheets is happy either way.
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllLines($Out, $lines, $utf8Bom)

"wrote  : $Out"
"rows   : $($sorted.Count)"
"stems  : $(($sorted | Group-Object Stem).Count)"
"size   : $([math]::Round((Get-Item $Out).Length/1KB,1)) KB"
"note   : 分類 は空。コマンド列が戻すときの鍵。"
