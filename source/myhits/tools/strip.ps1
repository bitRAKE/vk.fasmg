<# A run on a page: a picture of it every few seconds, side by side, each
   with how far into the run it is, which squad had come, the score, and the
   lives. To be read; to be laid beside the one from before a change; to be
   looked at by someone who cannot play it.

     powershell -File source\myhits\tools\strip.ps1
         the level as it comes to a ship that does nothing and cannot be
         hurt: two minutes of it, a picture every two seconds

     powershell -File source\myhits\tools\strip.ps1 -Seconds 300 -Every 5 -Fire
         five minutes, a picture every five seconds, the ship firing ahead

     powershell -File source\myhits\tools\strip.ps1 -Run build\myhits_last.run
         a run somebody played and kept with --record

   The run is not shown: only the frames that are pictured are drawn at all,
   and a minute of play costs a second or two. The page is build\myhits_strip.png
   unless -Out says otherwise.

   Without -Run the run is made here: a record of nothing pressed, so many
   seconds long, of a ghost, which nothing hurts (-Mortal: of a ship that can
   be). The game takes a record only of the names it was built with, so the
   tables' file must be the build's: build.cmd build\myhits.exe build\myhits_tables.bin #>
param([string]$Run, [int]$Seconds = 120, [int]$Every = 2, [switch]$Fire, [switch]$Mortal, [string]$Out, [int]$Columns = 6, [string]$BuildDir = 'build', [string]$Program = 'myhits.exe')
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Set-Location -LiteralPath $repoRoot
Add-Type -AssemblyName System.Drawing
if (-not $Out) { $Out = Join-Path $BuildDir 'myhits_strip.png' }
$game = (Resolve-Path -LiteralPath (Join-Path $BuildDir $Program)).Path
if (-not $Run) {
    # A record of nothing pressed: sixty frames a second of two ticks each.
    $Run = Join-Path $BuildDir 'myhits_strip.run'
    $names = [BitConverter]::ToUInt32([IO.File]::ReadAllBytes((Join-Path $BuildDir 'myhits_tables.bin')), 4)
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter $stream
    $writer.Write([Text.Encoding]::ASCII.GetBytes('MRUN')); $writer.Write([uint32]2); $writer.Write([uint32]$names); $writer.Write([uint32]120)
    $flags = if ($Mortal) { 0 } else { 16 }
    $held = if ($Fire) { 1 } else { 0 }
    foreach ($frame in 1..($Seconds * 60)) {
        $writer.Write([uint32]2); $writer.Write([single]0); $writer.Write([single]0); $writer.Write([single]1500); $writer.Write([single]540)
        $writer.Write([uint32]$held); $writer.Write([uint32]0); $writer.Write([uint32]$flags)
    }
    [IO.File]::WriteAllBytes((Join-Path $repoRoot $Run), $stream.ToArray())
}
# What each squad is, for the page: the squad lines of the tables, in order.
$squads = @([regex]::Matches([IO.File]::ReadAllText((Join-Path $repoRoot 'source\myhits\tables.inc')), '(?m)^\s*squad\s+[^,]+,\s*(\w+)\s*,\s*(\d+)') | ForEach-Object { "$($_.Groups[1].Value) x$($_.Groups[2].Value)" })
Get-ChildItem -LiteralPath $BuildDir -Filter 'myhits_game.*.bmp' | ForEach-Object { [IO.File]::Delete($_.FullName) }
$lines = Join-Path $BuildDir 'myhits_game.strip.txt'
if (Test-Path -LiteralPath $lines) { [IO.File]::Delete((Resolve-Path -LiteralPath $lines).Path) }
$process = Start-Process -FilePath $game -ArgumentList "--self-test --replay `"$Run`" --strip $Every" -PassThru -Wait
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $lines)) { throw "The game could not play $Run back (exit $($process.ExitCode)). A record is only of the names the game was built with." }
$pictures = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $lines).Path, [Text.Encoding]::Unicode) | Where-Object { $_ } | ForEach-Object { , ($_ -split ' ') })
if (-not $pictures.Count) { throw 'The run left no pictures.' }
$wide = 480; $high = 270; $label = 22
$rows = [Math]::Ceiling($pictures.Count / $Columns)
$page = New-Object System.Drawing.Bitmap ($Columns * $wide), ($rows * ($high + $label))
$draw = [System.Drawing.Graphics]::FromImage($page)
$draw.Clear([System.Drawing.Color]::FromArgb(12, 14, 22))
$draw.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = New-Object System.Drawing.Font 'Consolas', 10
$ink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(210, 220, 235))
foreach ($picture in $pictures) {
    $index = [int]$picture[0]; $ticks = [int]$picture[1]
    $file = Join-Path $BuildDir "myhits_game.$index.bmp"
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $x = ($index % $Columns) * $wide; $y = [Math]::Floor($index / $Columns) * ($high + $label)
    $bitmap = New-Object System.Drawing.Bitmap (Resolve-Path -LiteralPath $file).Path
    $draw.DrawImage($bitmap, $x, $y + $label, $wide, $high)
    $bitmap.Dispose()
    [IO.File]::Delete((Resolve-Path -LiteralPath $file).Path)
    $begun = [int]$picture[3]
    $squad = if ($begun -gt 0 -and $squads.Count) { "squad $begun $($squads[($begun - 1) % $squads.Count])" } else { 'nothing yet' }
    $minutes = [int][Math]::Floor($ticks / 7200)
    $seconds = [int]([Math]::Floor($ticks / 120) % 60)
    $words = '{0}:{1:00}  {2}  score {3}  lives {4}  alive {5}' -f $minutes, $seconds, $squad, $picture[2], $picture[4], $picture[5]
    $draw.DrawString($words, $font, $ink, [single]($x + 4), [single]($y + 3))
}
$draw.Dispose()
$target = Join-Path $repoRoot $Out
if ([IO.Path]::IsPathRooted($Out)) { $target = $Out }
$page.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
$page.Dispose()
$last = $pictures[$pictures.Count - 1]
Write-Host ("[myhits] strip: {0} pictures of {1} seconds, one every {2}; at the end a score of {3}, {4} squads begun, {5} lives: {6}" -f $pictures.Count, [Math]::Floor([int]$last[1] / 120), $Every, $last[2], $last[3], $last[4], $Out)
