<# Proof 08's pictures, held to what they should be. The proof's program says
   what it can of itself; what is on the screen is settled here, from the three
   pictures a scripted run leaves and the list of lines it leaves beside them.

     7   a line's ink is what its outlines enclose, at its size
     10  small text is not lighter than its outlines, and not much heavier
     11  turned, a line lies in its own turned box and weighs what it did
     12  the ink is what GDI+ makes of the same font's outlines, and the
         largest glyph's box is where GDI+ has it

   run.ps1 calls this; so can anyone, after `build\myhits_text.exe --self-test`:

     powershell -File source\myhits\proofs\08_text\pictures.ps1

   A failure is thrown, by number. What it returns is what it found, in words.
#>
param([string]$Lines = 'build\myhits_text.lines.txt',
      [string[]]$Pages = @('build\myhits_text.5.bmp', 'build\myhits_text.25.bmp', 'build\myhits_text.45.bmp'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('Myhits.Ink' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ink.cs') -ReferencedAssemblies System.Drawing }
function Hold($condition, [int]$check, [string]$message) { if (-not $condition) { throw "text check $check failed: $message" } }
$culture = [Globalization.CultureInfo]::InvariantCulture

$set = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Lines).Path, [Text.Encoding]::Unicode) | Where-Object { $_ } | ForEach-Object {
    $field = $_ -split ' '
    [pscustomobject]@{ Number = [int]$field[0]; Page = [int]$field[1]; X = [int]$field[2]; Y = [int]$field[3]; Top = [int]$field[4]; Tall = [int]$field[5]; Wide = [int]$field[6]
        Ink = [int]$field[7]; Glyphs = [int]$field[8]; Runs = [int]$field[9]; Backward = [int]$field[10]; Rows = [int]$field[11]; Turn = [int]$field[12] / 10000.0; Size = [int]$field[13] }
})
Hold ($set.Count -eq 37 -and $Pages.Count -eq 3) 7 "the run left $($set.Count) lines and $($Pages.Count) pictures, not 37 and 3"
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

# 10: smaller than thirteen pixels to the em, a line is never lighter than its
# outlines, and is heavier by no more than a tenth. (It is heavier: a pixel's
# share of an edge is exact and its share of a corner is not, and small text
# is mostly corners. What would make it lighter is a pixel left out, and small
# text is where one pixel is most of a stem: so this is looked at first.)
$small = @($set | Where-Object { $_.Turn -eq 0 -and $_.Size -lt 13 })
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
$upright = @($set | Where-Object { $_.Turn -eq 0 -and $_.Size -ge 13 })
Hold ($upright.Count -ge 19) 7 "only $($upright.Count) lines of thirteen pixels and more are not turned"
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

"{0} lines on three pictures: at 13 pixels to the em and more, {1} that are not turned have their outlines' ink within {2:0.00}%, but for {3} of scripts that join, which have up to {4:0.00}% less, their glyphs lying over one another; {5} smaller ones are heavier, by up to {6:0.0}%, and none lighter; {7} turned ones lie in their own boxes, one string at twelve angles weighing the same within {8:0.00}%; GDI+ counts the pangram's outlines at eleven sizes within {9:0.00}% of text.inc and its ink within {10:0.00}% of the picture's, and has a 700 pixel g's box within {11:0.000} of a pixel of where its ink lies" -f `
    $set.Count, ($upright.Count - $joined.Count), $widest, $joined.Count, (-$overlaid), $small.Count, $heaviest, $turned.Count, $spread, $counted, $second, $edges
