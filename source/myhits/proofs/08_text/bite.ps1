<# Proof 08's checks, shown to bite. One thing at a time is broken in the
   sources, the proof is built and run, and what failed is said: the program's
   own check by its number, or the pictures'. Every source is put back as it
   was, whatever happens, and the proof built again and run as it should be.

     powershell -File source\myhits\proofs\08_text\bite.ps1
     powershell -File source\myhits\proofs\08_text\bite.ps1 -Names even-odd,margin

   Each line that comes back should name the check its mutation begins with.

   What may be put in the list. A mutation here changes arithmetic, an order,
   or the curves and places the CPU hands over. None may leave a shader
   reading what was never written or reading outside what it was given: a
   count that is wrong, a list that is not built, a buffer that is too small.
   That kind was tried once on the game, took the display driver down, and
   is reasoned about now, not run. A run that leaves no report says so: the
   last one is deleted first, so that it is never read in its place.
#>
param([string[]]$Names = @(), [string]$Fasm2 = 'C:\git\fasm2\fasm2.cmd')
$ErrorActionPreference = 'Continue'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
Set-Location -LiteralPath $repoRoot
$inc = Join-Path $repoRoot 'source\common\text.inc'
$slang = Join-Path $repoRoot 'source\common\text.slang'
$page = Join-Path $PSScriptRoot 'page.slang'
$mutations = @(
  @{ name = '2 a cubic taken for a quadratic'; file = $inc
     old = "	ucomiss xmm1,xmm2`n	ja .earnest`n"
     new = "	ucomiss xmm1,xmm2`n" }
  @{ name = '3 the pen never moves on'; file = $inc
     old = ".forward:`n	movaps xmm4,xmm3`n	addss xmm4,xmm0`n	movss [text_pen],xmm4`n"
     new = ".forward:`n	movaps xmm4,xmm3`n	addss xmm4,xmm0`n" }
  @{ name = '4 every run taken to go forward'; file = $inc
     old = "	cmp [text_run_backward],0`n	je .forward`n"
     new = "	cmp [text_run_backward],0`n	jmp .forward`n" }
  @{ name = '5 a band sorted the other way'; file = $slang
     old = 'while (at > 0 && reaches[at - 1] < reach)'
     new = 'while (at > 0 && reaches[at - 1] > reach)' }
  @{ name = '5 a band without its edge'; file = $slang
     old = 'return max(max(p1.y, p2.y), p3.y) >= from - TEXT_BAND_OVERLAP &&'
     new = 'return max(max(p1.y, p2.y), p3.y) >= from + thick * 0.5 &&' }
  @{ name = '6 the area miscounted'; file = $inc
     old = 'text_sixth dd 0.16666667'
     new = 'text_sixth dd 0.2' }
  @{ name = '6 filled even-odd'; file = $slang
     old = '    return saturate(text_wound(across, down, across_weight, down_weight));'
     new = '    return saturate(1.0 - abs(1.0 - text_wound(across, down, across_weight, down_weight)));' }
  @{ name = '6 a root counted wrongly'; file = $slang
     old = 'return (0x2E74u >> shift) & 0x0101u;'
     new = 'return (0x2E64u >> shift) & 0x0101u;' }
  @{ name = '9 taken again though nothing is new'; file = $inc
     old = "	inc [text_takes]`n	mov [text_dirty],0`n"
     new = "	inc [text_takes]`n" }
  @{ name = '7 ink a fortieth thinner'; file = $page
     old = 'float alpha = text_ink(*root.world.text, input) * input.color.a;'
     new = 'float alpha = text_ink(*root.world.text, input) * input.color.a * 0.975;' }
  @{ name = '10 no margin round a box'; file = $slang
     old = 'float margin = 0.75 / max(pixels, 1e-3);'
     new = 'float margin = 0.0 / max(pixels, 1e-3);' }
  @{ name = '11 glyphs not turned with their line'; file = $inc
     old = 'iterate <member,add_x,add_y>, at,text_pen,text_base, across,text_nothing,text_nothing'
     new = 'iterate <member,add_x,add_y>, at,text_pen,text_base' }
  @{ name = '12 a cubic''s point for a quadratic''s'; file = $inc
     old = "	movaps xmm1,xmm4`n	addps xmm1,xmm5`n	mulps xmm1,xword [text_halves]`n	movaps xmm2,xmm3`n"
     new = "	movq xmm1,qword [rsi]`n	movaps xmm2,xmm3`n" }
  @{ name = '14 every layer in the text''s color'; file = $inc
     old = "	cmp word [rdi+LAYER_PALETTE],0FFFFh`n	je .hued`n"
     new = "	cmp word [rdi+LAYER_PALETTE],0FFFFh`n	jmp .hued`n" }
  @{ name = '14 a font''s blue for its red'; file = $inc
     old = 'iterate <channel,place>, 0,0, 4,8, 8,16, 12,24'
     new = 'iterate <channel,place>, 0,16, 4,8, 8,0, 12,24' }
  @{ name = '15 kept from its top, not its baseline'; file = $inc
     old = "	divss xmm3,xmm5`n	subss xmm4,[text_baseline]`n"
     new = "	divss xmm3,xmm5`n" }
  @{ name = '15 said from its end, wherever asked'; file = $slang
     old = 'float2 from = laid.at - float2(line.wide * said.align, 0.0);'
     new = 'float2 from = laid.at - float2(line.wide * 0.0, 0.0);' }
  @{ name = '16 every cell the first digit'; file = $slang
     old = "    Line line = text_line(text, from);`n    uint which = line.first + index;"
     new = "    Line line = text_line(text, from);`n    uint which = line.first;" }
  @{ name = '16 nothing cut off at a cell''s edge'; file = $slang
     old = 'float kept = inside.x * inside.y;'
     new = 'float kept = 1.0;' }
  @{ name = '17 drawn from where the CPU wrote it'; file = $inc
     old = 'iterate <member,buffer>, curves,text_curve_home, glyphs,text_glyph_home,'
     new = 'iterate <member,buffer>, curves,text_curve_buffer, glyphs,text_glyph_home,' }
)
$utf8 = New-Object Text.UTF8Encoding($false)
$reportPath = Join-Path $repoRoot 'build\myhits_text.report.txt'
function Run-Once {
    foreach ($left in $reportPath, (Join-Path $repoRoot 'build\myhits_text.lines.txt'), (Join-Path $repoRoot 'build\myhits_text.layers.txt')) { if (Test-Path -LiteralPath $left) { [IO.File]::Delete($left) } }
    $process = Start-Process -FilePath (Join-Path $repoRoot 'build\myhits_text.exe') -ArgumentList '--self-test' -PassThru
    if (-not $process.WaitForExit(30000)) { $process.Kill(); return 'none: stopped after thirty seconds' }
    if (-not (Test-Path -LiteralPath $reportPath)) { return "none: no report, exit $('{0:X8}' -f $process.ExitCode)" }
    $failure = ([regex]::Match([IO.File]::ReadAllText($reportPath, [Text.Encoding]::Unicode), 'failure=(\d+)')).Groups[1].Value
    if ($failure -ne '0') { return "the program's check $failure" }
    $said = (powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'pictures.ps1') 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $said -match 'text check \d+ failed') { return 'the pictures: ' + (([regex]::Match(($said -replace '\s+', ' '), 'text check \d+ failed: .{0,150}')).Value) }
    return 'NOTHING FAILED'
}
function Build-It { $null = cmd /c ".\build.cmd `"FASM2=$Fasm2`" build\myhits_text.exe 2>&1"; return $LASTEXITCODE }
foreach ($mutation in $mutations) {
    if ($Names.Count -and -not ($Names | Where-Object { $mutation.name -like "*$_*" })) { continue }
    $original = [IO.File]::ReadAllText($mutation.file)
    $old = $mutation.old
    if (-not $original.Contains($old)) { $old = $old.Replace("`n", "`r`n") }
    if (-not $original.Contains($old)) { '{0,-40} THE MUTATION DID NOT APPLY' -f $mutation.name; continue }
    try {
        [IO.File]::WriteAllText($mutation.file, $original.Replace($old, $mutation.new.Replace("`n", $(if ($old.Contains("`r`n")) { "`r`n" } else { "`n" }))), $utf8)
        if ((Build-It) -ne 0) { '{0,-40} did not build' -f $mutation.name; continue }
        '{0,-40} {1}' -f $mutation.name, (Run-Once)
    } finally {
        [IO.File]::WriteAllText($mutation.file, $original, $utf8)
    }
}
"put back; built again, exit $(Build-It)"
"as it should be: $(Run-Once)"
