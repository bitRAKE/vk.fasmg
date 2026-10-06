<# Cut the sprites art.txt names out of the sheets of ideas, and write each as
   source\myhits\art\<name>.png: the panel behind it removed, its edge cleaned
   for alpha blending, trimmed and sized. This is authoring, not building: it
   needs the sheets, which live outside the repository, and its results are
   committed.

       powershell -File source\myhits\tools\cut-art.ps1 -Ideas C:\git\data\myhits_gfx_ideas

   -Only cuts the names that match a pattern. -Sheet also writes every result
   onto one picture, twice its size, over a dark and a light ground, to judge
   the edges by eye.
#>
param([Parameter(Mandatory = $true)] [string]$Ideas, [string]$Only = '', [string]$Sheet = '')
$ErrorActionPreference = 'Stop'
$art = (Resolve-Path (Join-Path $PSScriptRoot '..\art')).Path
Add-Type -AssemblyName System.Drawing
if (-not ('Myhits.Art' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'art.cs') -ReferencedAssemblies System.Drawing }
$sheets = @{}
$made = @()
foreach ($line in [IO.File]::ReadAllLines((Join-Path $art 'art.txt'))) {
    $part = $line.Trim() -split '\s+'
    if ($part[0] -eq 'sheet') { $sheets[$part[1]] = ($line.Trim() -split '\s+', 3)[2]; continue }
    if ($part[0] -ne 'cut') { continue }
    $name = $part[1]
    if ($Only -and $name -notlike $Only) { continue }
    if (-not $sheets.ContainsKey($part[2])) { throw "art.txt cuts $name from a sheet it does not name: $($part[2])" }
    $output = Join-Path $art "$name.png"
    $flags = @($part | Select-Object -Skip 8)
    $result = [Myhits.Art]::Cut((Join-Path $Ideas $sheets[$part[2]]), [int]$part[3], [int]$part[4], [int]$part[5], [int]$part[6], [int]$part[7], ($flags -contains 'flip'), ($flags -contains 'glow'), $output)
    Write-Host ("{0,-14} {1}" -f $name, $result)
    $made += $output
}
if ($Sheet -and $made.Count) {
    $cell = 200
    $columns = [Math]::Min(6, $made.Count); $rows = [Math]::Ceiling($made.Count / $columns)
    $canvas = New-Object System.Drawing.Bitmap ($columns * $cell), ($rows * $cell * 2)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.InterpolationMode = 'NearestNeighbor'; $graphics.PixelOffsetMode = 'Half'
    $graphics.Clear([System.Drawing.Color]::FromArgb(12, 14, 24))
    $graphics.FillRectangle([System.Drawing.Brushes]::Gainsboro, 0, $rows * $cell, $columns * $cell, $rows * $cell)
    for ($i = 0; $i -lt $made.Count; $i++) {
        $image = [System.Drawing.Image]::FromFile($made[$i])
        $x = ($i % $columns) * $cell + [int](($cell - $image.Width * 2) / 2); $y = [Math]::Floor($i / $columns) * $cell + [int](($cell - $image.Height * 2) / 2)
        $graphics.DrawImage($image, $x, $y, $image.Width * 2, $image.Height * 2)
        $graphics.DrawImage($image, $x, $y + $rows * $cell, $image.Width * 2, $image.Height * 2)
        $image.Dispose()
    }
    $graphics.Dispose(); $canvas.Save($Sheet, [System.Drawing.Imaging.ImageFormat]::Png); $canvas.Dispose()
    Write-Host "sheet: $Sheet"
}
