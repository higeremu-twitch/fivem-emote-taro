# Takes one still of the screen, for reading what is on it.
#
# Why this exists: the emote list shipped with the builder is the upstream one,
# so a town's own categories, its Japanese labels and its own emotes are not in
# it. They are on screen in the game's own menu. Reading that menu beats
# transcribing it by hand.
#
# The catch is GDI: BitBlt sees a compositor surface, not what Direct3D drew
# straight to the front buffer. A game in exclusive fullscreen therefore comes
# back black. Borderless windowed works. Rather than guess, this measures the
# average brightness of the result and says so.
#
# Usage:
#   .\grab-screen.ps1                  the whole screen
#   .\grab-screen.ps1 -Window fivem    just that window (matched on title/process)

param(
    [string]$Window,
    [string]$OutDir = "$env:TEMP\shots"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }

$area = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$what = '画面全体'

if ($Window) {
    $p = Get-Process | Where-Object {
        $_.MainWindowHandle -ne 0 -and
        ($_.MainWindowTitle -like "*$Window*" -or $_.ProcessName -like "*$Window*")
    } | Select-Object -First 1
    if (-not $p) { throw "ウィンドウが見つかりません: $Window" }

    # a minimised window has nothing to copy
    if ([W]::IsIconic($p.MainWindowHandle)) { [void][W]::ShowWindow($p.MainWindowHandle, 9) }
    [void][W]::SetForegroundWindow($p.MainWindowHandle)
    Start-Sleep -Milliseconds 400

    $r = New-Object W+RECT
    [void][W]::GetWindowRect($p.MainWindowHandle, [ref]$r)
    $area = New-Object Drawing.Rectangle $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T)
    $what = "『$($p.MainWindowTitle)』 ($($p.ProcessName))"
}

$stamp = (Get-Date).ToString('HHmmss')
$out = Join-Path $OutDir "shot-$stamp.png"

$bmp = New-Object Drawing.Bitmap $area.Width, $area.Height
$gfx = [Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($area.X, $area.Y, 0, 0, $bmp.Size)

# sample a grid rather than every pixel; enough to tell black from a picture
$sum = 0; $n = 0
for ($x = 0; $x -lt $area.Width; $x += 61) {
    for ($y = 0; $y -lt $area.Height; $y += 61) {
        $c = $bmp.GetPixel($x, $y); $sum += $c.R + $c.G + $c.B; $n++
    }
}
$bright = [math]::Round($sum / $n / 3, 1)

$bmp.Save($out, [Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose(); $bmp.Dispose()

"撮影 : $what"
"範囲 : $($area.Width)x$($area.Height)"
"明るさ: $bright / 255"
if ($bright -lt 6) {
    "  ★ ほぼ真っ黒です。排他フルスクリーンだと GDI からは撮れません。"
    "     ゲームの画面設定を『ボーダーレスウィンドウ』に変えてください。"
}
"file : $out"
