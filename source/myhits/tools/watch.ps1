<# Keep build\myhits_tables.bin as source\myhits\tables.inc has it, for as long
   as this runs: whenever the tables are saved, the file is assembled again,
   which takes about a second. A game started with --watch takes the file
   whenever it changes, so:

     powershell -File source\myhits\tools\watch.ps1 -Play

   and then edit tables.inc. A squad's count, a sound's pitch, a diver's
   patience: each is on the screen, or in the speakers, a second or two after
   the save. The game says TABLES TAKEN along the top when it has them, lets
   go of whatever was running by the old ones, and brings the squad that was
   on the screen again from its first.

   What cannot be taken this way is a change to the names: a new kind, sound,
   style, stem or thing said, or one removed or moved. The shaders know those
   by number. The game says TABLES REFUSED and goes on with what it had; build
   it (build.cmd build\myhits.exe) and start it again.

   A mistake in tables.inc is shown here, and the file is left as it was: the
   game goes on with the last tables that assembled.

   -Play starts the game watching, in a window, and stops when it is closed.
   -Fasm2 names the assembler if it is not where the makefile looks for it. #>
param([string]$Fasm2, [string]$BuildDir = 'build', [switch]$Play)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Set-Location -LiteralPath $repoRoot
# Where the makefile looks; and, from a worktree, where its main checkout would.
if (-not $Fasm2) { $Fasm2 = @($env:FASM2, '..\fasm2\fasm2.cmd', '..\..\..\..\fasm2\fasm2.cmd') | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1 }
if (-not $Fasm2 -or -not (Get-Command $Fasm2 -ErrorAction SilentlyContinue)) { throw 'fasm2 was not found; say where it is with -Fasm2' }
$Fasm2 = (Resolve-Path -LiteralPath $Fasm2).Path
$sources = 'source\myhits\tables.inc', 'source\myhits\tables_image.inc', 'source\common\tables.inc', 'source\common\shared.inc'
$file = Join-Path $BuildDir 'myhits_tables.bin'
$fresh = Join-Path $BuildDir 'myhits_tables.new'
function Stamp { ($sources | ForEach-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc.Ticks }) -join ' ' }
# Assembled beside the file and then put in its place whole, so that the game never reads half of one.
function Assemble {
    try {
        & (Join-Path $repoRoot 'tools\assemble.ps1') -Fasm2 $Fasm2 -Source 'source\myhits\tables_file.asm' -Output $fresh | Out-Null
        Move-Item -LiteralPath $fresh -Destination $file -Force
        Write-Host ("{0:HH:mm:ss}  tables assembled: {1} bytes" -f (Get-Date), (Get-Item -LiteralPath $file).Length)
    } catch {
        Write-Host ("{0:HH:mm:ss}  tables not assembled; the game keeps what it has" -f (Get-Date)) -ForegroundColor Yellow
        Write-Host $_.Exception.Message
    }
}
$seen = Stamp
Assemble
$game = $null
if ($Play) {
    $game = Start-Process -FilePath (Join-Path $BuildDir 'myhits.exe') -ArgumentList '--watch', '--windowed' -PassThru
    Write-Host 'The game is watching. Save tables.inc to change it; close the game to stop.'
} else {
    Write-Host 'Watching tables.inc. Start the game with --watch; Ctrl+C stops this.'
}
while (-not $game -or -not $game.HasExited) {
    Start-Sleep -Milliseconds 250
    $now = Stamp
    if ($now -ne $seen) {
        # An editor may write a file in more than one go: wait until it has been still a moment.
        Start-Sleep -Milliseconds 150
        $seen = Stamp
        Assemble
    }
}
