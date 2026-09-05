# FiveMエモート太郎 — 同期スクリプト（Windows）
#
# これ1本で「最新にする」「配ったものを更新する」が済みます。
#
#   .\tools\sync.ps1          最新にする（GitHubから取得 → Dropboxの配布用コピーも更新）
#   .\tools\sync.ps1 -Push    自分の変更をGitHubへ送ってから、同じことをする
#
# Dropbox の中は「読むだけの複製」です。あそこで編集しないでください。
# 万一あそこが編集されていたら、このスクリプトは上書きせずに止まります。

[CmdletBinding()]
param(
    [switch]$Push,
    [string]$Message,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

# 配布用コピーの置き場所（無ければ複製処理を飛ばす）
$mirror = 'D:\Dropbox\claude-work\fivem-emote-taro'

function Say($text) { Write-Host $text }

# ---- 1. 自分の変更を送る（-Push のときだけ） ----------------------------

if ($Push) {
    $dirty = git -C $repo status --porcelain
    if ($dirty) {
        if (-not $Message) { $Message = "更新 $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
        Say "変更を記録します: $Message"
        git -C $repo add -A
        git -C $repo commit -m $Message | Out-Null
    }
    Say 'GitHub へ送ります'
    git -C $repo push 2>&1 | Out-Null
}

# ---- 2. GitHub から最新を取る ------------------------------------------

$dirty = git -C $repo status --porcelain
if ($dirty -and -not $Push) {
    Say '※ 保存していない変更があります。先に送るなら -Push を付けてください:'
    $dirty | ForEach-Object { Say "    $_" }
    Say ''
}

Say 'GitHub から取得します'
git -C $repo pull --ff-only 2>&1 | Out-Null
$commit = git -C $repo rev-parse --short HEAD
Say "  いまの版: $commit  $(git -C $repo log -1 --format=%s)"

# ---- 3. 配布用コピー（Dropbox）を更新 ----------------------------------

if (-not (Test-Path $mirror)) {
    Say "配布用コピーが見つからないので飛ばします: $mirror"
    exit 0
}

$stampPath = Join-Path $mirror '.snapshot.json'

# 追跡対象のファイル一覧（.git は含まれない）
$tracked = git -C $repo ls-files

function HashOf($path) { (Get-FileHash $path -Algorithm SHA256).Hash }

# 前回配った内容が書き換えられていないか調べる
if ((Test-Path $stampPath) -and -not $Force) {
    $stamp = Get-Content $stampPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $edited = @()
    foreach ($p in $stamp.files.PSObject.Properties) {
        $f = Join-Path $mirror ($p.Name -replace '/', '\')
        if (-not (Test-Path $f)) { $edited += "$($p.Name)（消えている）"; continue }
        if ((HashOf $f) -ne $p.Value) { $edited += $p.Name }
    }
    if ($edited.Count -gt 0) {
        Say ''
        Say '止めました。Dropbox の複製が編集されています:'
        $edited | ForEach-Object { Say "    $_" }
        Say ''
        Say 'あそこは読むだけの場所です。その変更を残したいなら、中身を作業用フォルダへ'
        Say '持ってきてコミットしてください。捨ててよいなら -Force で上書きします。'
        exit 1
    }
}

Say '配布用コピーを更新します'
$files = @{}
foreach ($rel in $tracked) {
    $src = Join-Path $repo ($rel -replace '/', '\')
    $dst = Join-Path $mirror ($rel -replace '/', '\')
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item $src $dst -Force
    $files[$rel] = HashOf $dst
}

# 前回配ったが今回は無いファイルを片付ける
if ((Test-Path $stampPath) -or $Force) {
    if (Test-Path $stampPath) {
        $old = Get-Content $stampPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $old.files.PSObject.Properties) {
            if (-not $files.ContainsKey($p.Name)) {
                $gone = Join-Path $mirror ($p.Name -replace '/', '\')
                if (Test-Path $gone) { Remove-Item $gone -Force; Say "  削除: $($p.Name)" }
            }
        }
    }
}

$stampObj = [ordered]@{
    commit  = (git -C $repo rev-parse HEAD)
    updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    machine = $env:COMPUTERNAME
    files   = $files
}
$stampObj | ConvertTo-Json -Depth 4 | Set-Content $stampPath -Encoding UTF8

Say "  $($files.Count) ファイル。完了。"
