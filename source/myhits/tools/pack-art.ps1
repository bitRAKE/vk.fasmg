<# Pack the art for the build: the PNGs art.txt names become one block of
   texels, and the table of every frame, cut, made or drawn, is written beside
   it for the assembly and for the shaders.

       build\myhits_art.bin     the cut frames' texels, and normals where asked
       build\myhits_art.inc     the frame table, the strokes, FRAME_ and ART_ constants
       build\myhits_art.slang   the same constants for the shaders
#>
param([string]$BuildDir = 'build')
$ErrorActionPreference = 'Stop'
$art = (Resolve-Path (Join-Path $PSScriptRoot '..\art')).Path
$build = (Resolve-Path -LiteralPath $BuildDir).Path
Add-Type -AssemblyName System.Drawing
if (-not ('Myhits.Art' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'art.cs') -ReferencedAssemblies System.Drawing }
$result = [Myhits.Art]::Pack((Join-Path $art 'art.txt'), $art, (Join-Path $build 'myhits_art.bin'), (Join-Path $build 'myhits_art.inc'), (Join-Path $build 'myhits_art.slang'))
Write-Host "[myhits] art: $result"