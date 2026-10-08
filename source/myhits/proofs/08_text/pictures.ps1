<# Proof 08's pictures, held to what they should be. The proof's program says
   what it can of itself; what is on the screen is settled here, from the four
   pictures a scripted run leaves and the lists it leaves beside them.

     7   a line's ink is what its outlines enclose, at its size
     10  small text is not lighter than its outlines, and not much heavier
     11  turned, a line lies in its own turned box and weighs what it did
     12  the ink is what GDI+ makes of the same font's outlines, and the
         largest glyph's box is where GDI+ has it
     14  a glyph of colors is the layers its font's own tables give it, in
         the font's colors, and they are on the picture
     15  a line that is kept and said by the device is the line the CPU sets
         down: the same picture; and larger, turned or about its middle it
         weighs what it should, where it should
     16  a number the device sets down from the ten digits is the picture
         the system makes of the same digits; and one that is turning over
         is never outside its cells

   run.ps1 calls this; so can anyone, after `build\myhits_text.exe --self-test`:

     powershell -File source\myhits\proofs\08_text\pictures.ps1

   A failure is thrown, by number. What it returns is what it found, in words.
#>
param([string]$Lines = 'build\myhits_text.lines.txt', [string]$Kept = 'build\myhits_text.kept.txt', [string]$Layers = 'build\myhits_text.layers.txt',
      [string[]]$Pages = @('build\myhits_text.5.bmp', 'build\myhits_text.25.bmp', 'build\myhits_text.45.bmp', 'build\myhits_text.65.bmp'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('Myhits.Ink' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ink.cs') -ReferencedAssemblies System.Drawing }
function Hold($condition, [int]$check, [string]$message) { if (-not $condition) { throw "text check $check failed: $message" } }
function Read-List([string]$path) { return @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $path).Path, [Text.Encoding]::Unicode) | Where-Object { $_ }) }
$culture = [Globalization.CultureInfo]::InvariantCulture

$set = @(Read-List $Lines | ForEach-Object {
    $field = $_ -split ' '
    [pscustomobject]@{ Number = [int]$field[0]; Page = [int]$field[1]; X = [int]$field[2]; Y = [int]$field[3]; Top = [int]$field[4]; Tall = [int]$field[5]; Wide = [int]$field[6]
        Ink = [int]$field[7]; Glyphs = [int]$field[8]; Runs = [int]$field[9]; Backward = [int]$field[10]; Rows = [int]$field[11]; Turn = [int]$field[12] / 10000.0; Size = [int]$field[13]; Layers = [int]$field[14] }
})
Hold ($set.Count -eq 40 -and $Pages.Count -eq 4) 7 "the run left $($set.Count) lines and $($Pages.Count) pictures, not 40 and 4"
$pictures = @($Pages | ForEach-Object { New-Object Myhits.Ink (Resolve-Path -LiteralPath $_).Path })

# What each line has on its picture: the ink in its box, turned as it is turned.
# (A line is laid out from its top left corner, and is turned about it.)
foreach ($line in $set) {
    $picture = $pictures[$line.Page]
    $found = if ($line.Turn -ne 0) { $picture.Turned($line.X, $line.Y, $line.Turn, -12, $line.Top - 3, $line.Wide + 12, $line.Top + $line.Tall + 3) }
             else { $picture.Box($line.X - 12, $line.Y + $line.Top - 3, $line.X + $line.Wide + 12, $line.Y + $line.Top + $line.Tall + 3) }
    $line | Add-Member -NotePropertyName Found -NotePropertyValue $found
    $line | Add-Member -NotePropertyName Apart -NotePropertyValue (100.0 * ($found - $line.Ink) / $line.Ink)
}
# (A line with glyphs of colors in it is layers, one over another: what its
# outlines enclose is not what it covers, and its ink is not all one color.
# It is held to its colors, under 14.)
$inked = @($set | Where-Object { $_.Layers -eq 0 })

# 10: smaller than thirteen pixels to the em, a line is never lighter than its
# outlines, and is heavier by no more than a tenth. (It is heavier: a pixel's
# share of an edge is exact and its share of a corner is not, and small text
# is mostly corners. What would make it lighter is a pixel left out, and small
# text is where one pixel is most of a stem: so this is looked at first.)
$small = @($inked | Where-Object { $_.Turn -eq 0 -and $_.Size -lt 13 })
Hold ($small.Count -ge 5) 10 "only $($small.Count) lines are smaller than thirteen pixels to the em"
foreach ($line in $small) {
    Hold ($line.Apart -ge 0 -and $line.Apart -le 10) 10 ("line {0}, at {1} pixels to the em, has {2:0.0} pixels of ink on its picture and its outlines enclose {3}: {4:0.00}% apart" -f $line.Number, $line.Size, $line.Found, $line.Ink, $line.Apart)
}
$heaviest = ($small | ForEach-Object { $_.Apart } | Measure-Object -Maximum).Maximum

# 7: at that size and more, a line that is not turned has the ink its
# outlines enclose, within a hundredth and a half. Three lines have less, by
# up to a twenty-fifth: the Arabic, the Devanagari and the line of mixed
# scripts, whose glyphs lie over one another where they join, so that what
# their outlines enclose counts some of the page twice. The last line is the
# shape, whose ink is what two discs cover together.
$joined = 3, 5, 7
$upright = @($inked | Where-Object { $_.Turn -eq 0 -and $_.Size -ge 13 })
Hold ($upright.Count -ge 21) 7 "only $($upright.Count) lines of thirteen pixels and more are not turned"
foreach ($line in $upright) {
    $least = if ($joined -contains $line.Number) { -4.0 } else { -1.5 }
    Hold ($line.Apart -ge $least -and $line.Apart -le 1.5) 7 ("line {0}, at {1} pixels to the em, has {2:0.0} pixels of ink on its picture and its outlines enclose {3}: {4:0.00}% apart" -f $line.Number, $line.Size, $line.Found, $line.Ink, $line.Apart)
}
$widest = ($upright | Where-Object { $joined -notcontains $_.Number } | ForEach-Object { [Math]::Abs($_.Apart) } | Measure-Object -Maximum).Maximum
$overlaid = ($set | Where-Object { $joined -contains $_.Number } | ForEach-Object { $_.Apart } | Measure-Object -Minimum).Minimum

# 11: a line that is turned has its ink in its own box, turned with it, and
# as much of it as its outlines enclose; and the twelve that are one string at
# twelve angles weigh the same.
$turned = @($set | Where-Object { $_.Turn -ne 0 })
$spokes = @($turned | Where-Object { $_.Glyphs -eq $turned[0].Glyphs -and $_.Size -eq $turned[0].Size })
Hold ($turned.Count -eq 13 -and $spokes.Count -eq 12) 11 "there are $($turned.Count) turned lines, $($spokes.Count) of them one string"
foreach ($line in $turned) {
    Hold ([Math]::Abs($line.Apart) -le 1.5) 11 ("line {0}, turned {1:0.00} radians, has {2:0.0} pixels of ink in its box and its outlines enclose {3}: {4:0.00}% apart" -f $line.Number, $line.Turn, $line.Found, $line.Ink, $line.Apart)
}
$weights = $spokes | ForEach-Object { $_.Found } | Measure-Object -Minimum -Maximum
$spread = 100.0 * ($weights.Maximum - $weights.Minimum) / $weights.Minimum
Hold ($spread -le 1.0) 11 ("one string at twelve angles weighs from {0:0.0} to {1:0.0} pixels: {2:0.00}% apart" -f $weights.Minimum, $weights.Maximum, $spread)

# 12: a second hand. The pangram is Segoe UI at eleven sizes, and GDI+ is asked
# what its outline encloses at each: text.inc's own count of it is within a
# quarter of a hundredth at every size, and the picture is held to GDI+'s as it
# was to text.inc's. And the largest glyph there is, a bold g seven hundred
# pixels to the em: its ink is GDI+'s within a hundredth, and the box of its
# ink is GDI+'s box of its outline within a quarter of a pixel, each edge of
# it, from the corner it was set at.
$pangram = 'Sphinx of black quartz, judge my vow.'
$sized = @($set | Where-Object { $_.Glyphs -eq 31 -and $_.Turn -eq 0 })
Hold ($sized.Count -eq 11) 12 "the pangram is on the pages $($sized.Count) times, not eleven"
$counted = 0.0
$second = 0.0
foreach ($line in $sized) {
    $other = [double]::Parse(([Myhits.Ink]::Second('Segoe UI', $false, $line.Size, $pangram) -split ' ')[0], $culture)
    $ours = 100.0 * ($line.Ink - $other) / $other
    # (The list has a line's ink to the pixel: at seven pixels to the em that is most of what a quarter of a hundredth is.)
    Hold ([Math]::Abs($line.Ink - $other) -le 0.0025 * $other + 1) 12 ("at {0} pixels to the em text.inc counts {1} pixels inside the pangram's outlines and GDI+ {2:0.0}" -f $line.Size, $line.Ink, $other)
    $apart = 100.0 * ($line.Found - $other) / $other
    if ($line.Size -ge 13) { Hold ([Math]::Abs($apart) -le 1.5) 12 ("at {0} pixels to the em the pangram has {1:0.0} pixels of ink on its picture and GDI+ has {2:0.0}: {3:0.00}% apart" -f $line.Size, $line.Found, $other, $apart); $second = [Math]::Max($second, [Math]::Abs($apart)) }
    else { Hold ($apart -ge 0 -and $apart -le 10) 12 ("at {0} pixels to the em the pangram has {1:0.0} pixels of ink on its picture and GDI+ has {2:0.0}: {3:0.00}% apart" -f $line.Size, $line.Found, $other, $apart) }
    $counted = [Math]::Max($counted, [Math]::Abs($ours))
}
$huge = @($set | Where-Object { $_.Size -ge 500 })
Hold ($huge.Count -eq 1 -and $huge[0].Glyphs -eq 1) 12 'the largest glyph is not on the pages'
$huge = $huge[0]
$other = @([Myhits.Ink]::Second('Segoe UI', $true, $huge.Size, 'g') -split ' ' | ForEach-Object { [double]::Parse($_, $culture) })
$box = @($pictures[$huge.Page].Bounds($huge.X - 12, $huge.Y + $huge.Top - 3, $huge.X + $huge.Wide + 12, $huge.Y + $huge.Top + $huge.Tall + 3) -split ' ' | ForEach-Object { [double]::Parse($_, $culture) })
Hold ([Math]::Abs($huge.Found - $other[0]) -le 0.01 * $other[0]) 12 ("the largest glyph has {0:0.0} pixels of ink on its picture and GDI+ has {1:0.0}" -f $huge.Found, $other[0])
$edges = 0.0
foreach ($edge in 0..3) { $edges = [Math]::Max($edges, [Math]::Abs($box[$edge] - @($huge.X, $huge.Y, $huge.X, $huge.Y)[$edge] - $other[1 + $edge])) }
Hold ($edges -le 0.25) 12 ("the largest glyph's ink lies {0:0.00} {1:0.00} {2:0.00} {3:0.00} from where it was set, and GDI+ has its outline at {4:0.00} {5:0.00} {6:0.00} {7:0.00}" -f `
    ($box[0] - $huge.X), ($box[1] - $huge.Y), ($box[2] - $huge.X), ($box[3] - $huge.Y), $other[1], $other[2], $other[3], $other[4])

# The last page. Where things are on it is as kept_corner in page.slang has
# them; how large the kept lines are is in the list the run left of them:
# glyphs, then in thousandths of an em how wide, the step, the ink's box,
# the baseline's depth and the row's height.
$last = $pictures[3]
$rows = @(Read-List $Kept | ForEach-Object { $field = $_ -split ' '; [pscustomobject]@{ Glyphs = [int]$field[1]; Wide = [int]$field[2] / 1000.0; Step = [int]$field[3] / 1000.0; Top = [int]$field[5] / 1000.0; Bottom = [int]$field[7] / 1000.0; Rise = [int]$field[8] / 1000.0 } })
Hold ($rows.Count -eq 4) 15 "the run kept $($rows.Count) lines, not four"

# 15: a line that is kept. The CPU set the string down at the left; the device
# said the kept line 960 to the right: the two are one picture, within a
# two-hundredth of its ink. Said at twice the size it has four times the ink;
# turned, as much, in its own turned box; and about its middle, as much, about
# that middle, with nothing either side.
$single = $set[37]
$ink = $single.Found
Hold ($single.Page -eq 3 -and $single.Glyphs -eq $rows[0].Glyphs -and $ink -gt 1000) 15 'the line the kept one is held to is not on the last page'
$unlike = $last.Unlike(40, 60, 960, 150, 960)
Hold ($unlike -le 0.005 * $ink) 15 ("the kept line said and the line set down are {0:0.0} pixels unlike, of {1:0.0}" -f $unlike, $ink)
$twice = $last.Box(40, 170, 1000, 310)
Hold ([Math]::Abs($twice - 4 * $ink) -le 0.015 * 4 * $ink) 15 ("said at twice the size the line has {0:0.0} pixels of ink, and four times its own is {1:0.0}" -f $twice, (4 * $ink))
$wide = $rows[0].Wide * 40
$round = $last.Turned(1200, 380, -0.25, -12, -50, $wide + 12, 20)
Hold ([Math]::Abs($round - $ink) -le 0.015 * $ink) 15 ("said turned the line has {0:0.0} pixels of ink in its turned box, of {1:0.0}" -f $round, $ink)
$middle = $last.Box([int](960 - $wide / 2 - 12), 420, [int](960 + $wide / 2 + 12), 490)
$beside = $last.Box(300, 420, [int](960 - $wide / 2 - 12), 490) + $last.Box([int](960 + $wide / 2 + 12), 420, 1700, 490)
Hold ([Math]::Abs($middle - $ink) -le 0.015 * $ink -and $beside -lt 1) 15 ("said about its middle the line has {0:0.0} pixels of ink about it, of {1:0.0}, and {2:0.0} beside" -f $middle, $ink, $beside)

# 16: a number. The device set eight digits down from the ten that are kept,
# each in its cell; the CPU set the same digits down as a string 960 to the
# right, in a font whose digits are all one width: one picture, within a
# two-hundredth. And the number that is turning over, three of its wheels half
# way round: there is ink in its cells, and none above them or below.
$figures = $last.Box(40, 630, 960, 730)
$unlike = $last.Unlike(40, 630, 960, 730, 960)
Hold ($figures -gt 2000 -and $unlike -le 0.005 * $figures) 16 ("the number the device set down and the one the system laid out are {0:0.0} pixels unlike, of {1:0.0}" -f $unlike, $figures)
$base = 780 + $rows[2].Rise * 64
$top = [Math]::Floor($base + $rows[2].Top * 64 - 4)
$bottom = [Math]::Ceiling($base + $rows[2].Bottom * 64 + 4)
$within = $last.Box(40, $top, 400, $bottom)
$outside = $last.Box(40, $top - 40, 400, $top - 1) + $last.Box(40, $bottom + 1, 400, $bottom + 40)
Hold ($within -gt 1500 -and $outside -lt 0.5) 16 ("the number turning over has {0:0.0} pixels of ink in its cells and {1:0.0} above and below them" -f $within, $outside)

# 14: a glyph of colors. (After the kept lines, since the picture of it is
# of one.) The program asked the system what a grinning face
# is made of, and wrote the layers down; ink.cs reads the same from the font's
# own file, and they are the same layers in the same colors. Then the picture:
# the line that is said in gold has the face in it, and of the face's colors
# at least three are there, each over thirty pixels and more; and its letters,
# which have no color of their own, are gold.
$made = @(Read-List $Layers)
$face = $made[0] -split ' '
$fonts = [Environment]::GetFolderPath('Fonts')
$own = @(([Myhits.Ink]::Layers((Join-Path $fonts 'seguiemj.ttf'), [int]$face[0]) -split "`n") | Where-Object { $_ })
Hold ([int]$face[1] -ge 2 -and $own.Count -eq [int]$face[1]) 14 "the system made $($face[1]) layers of glyph $($face[0]) and the font's own table has $($own.Count)"
foreach ($layer in 0..([Math]::Min($own.Count, $made.Count - 1) - 1)) { Hold ($own[$layer] -eq $made[1 + $layer]) 14 "layer $layer of glyph $($face[0]) was made '$($made[1 + $layer])' and the font has '$($own[$layer])'" }
$hues = @($own | ForEach-Object { ($_ -split ' ')[1] } | Sort-Object -Unique)
$there = 0
foreach ($hue in $hues) {
    $texel = [Convert]::ToUInt32($hue, 16)
    if ($last.Count(40, 490, 700, 590, [int]($texel -band 255), [int](($texel -shr 8) -band 255), [int](($texel -shr 16) -band 255), 2) -ge 30) { ++$there }
}
Hold ($hues.Count -ge 3 -and $there -ge 3) 14 "of the $($hues.Count) colors its font gives the face, $there are on the picture"
$gold = $last.Count(40, 490, 700, 590, 255, 200, 64, 2)
Hold ($gold -ge 500) 14 "the letters said in gold beside the face have $gold gold pixels"

"{0} lines on four pictures: at 13 pixels to the em and more, {1} that are not turned have their outlines' ink within {2:0.00}%, but for {3} of scripts that join, which have up to {4:0.00}% less, their glyphs lying over one another; {5} smaller ones are heavier, by up to {6:0.0}%, and none lighter; {7} turned ones lie in their own boxes, one string at twelve angles weighing the same within {8:0.00}%; GDI+ counts the pangram's outlines at eleven sizes within {9:0.00}% of text.inc and its ink within {10:0.00}% of the picture's, and has a 700 pixel g's box within {11:0.000} of a pixel of where its ink lies; a face is the {12} layers its font's own tables give it, {13} of its {14} colors on the picture; a kept line said by the device is the line set down within {15:0.00}% of its ink, and at twice the size, turned and about its middle weighs what it should; a number set down by the device is the system's within {16:0.00}%, and one turning over has {17:0} pixels of ink in its cells and none outside" -f `
    $set.Count, ($upright.Count - $joined.Count), $widest, $joined.Count, (-$overlaid), $small.Count, $heaviest, $turned.Count, $spread, $counted, $second, $edges,
    $own.Count, $there, $hues.Count, (100.0 * $last.Unlike(40, 60, 960, 150, 960) / $ink), (100.0 * $unlike / $figures), $within
