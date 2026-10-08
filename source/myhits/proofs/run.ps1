<# Run the myhits proofs and hold each to what it claims. README.md beside this
   file says what every check settles; this script is the checks themselves.

     01 style   the shaders compile to valid SPIR-V in the pointer style, and
                the compiler lays the boundary blocks out as shared.inc says
     02 spine   the CPU-GPU boundary works end to end on the device
     03 pictures  every frame is made, masked and drawn on the device, lit
                from one side however it turns
     04 motion  the easing curves are the textbook's; bodies run the tables'
                programs at a fixed tick; the level's pace is eased too
     05 hits    what is drawn is what is hit, by its mask, at any speed; a
                hit throws off exactly the particles and sounds it should
     06 sound   the bank the device renders is the recipes'; a sound asked
                for in one frame is on a voice as the next begins
     07 game    the game itself, through two scripted runs: waves by the
                table, chains, hostile fire, rank, lives, the level's pace;
                and its tables taken again from a file while it runs
     08 text    strings the system shaped, drawn from their outlines on the
                device: the bands lose nothing, the ink is the outlines' at
                any size and angle, and is what GDI+ makes of the same fonts;
                glyphs of colors are their font's layers; lines are kept, and
                said and numbered by the device

   -Validation repeats the device runs under Khronos core and synchronization
   validation and rejects any diagnostic.
#>
param([string]$BuildDir = 'build', [switch]$Validation)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Set-Location -LiteralPath $repoRoot
if (-not ('VkFasmgTests.DebugOutputCapture' -as [type])) { Add-Type -Path (Join-Path $repoRoot 'tests\capture-debug-output.cs') }
function Assert-True($condition, [string]$message) { if (-not $condition) { throw $message } }
# What a measuring run left: each line a name and its numbers.
function Read-Measure([string]$path) {
    $measured = @{}
    foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::Unicode)) {
        if ($line -match '^(\w+)=(.*)$') { $measured[$Matches[1]] = $Matches[2] -split ' ' }
    }
    return $measured
}
function Read-State([string]$path) {
    $state = @{}
    foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::Unicode)) {
        if ($line -match '^(\w+)=(.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    return $state
}
$spirvDis = Join-Path $env:VULKAN_SDK 'Bin\spirv-dis.exe'
# The second implementations the device is held to: the curves, and the sounds made of them.
if (-not ('Myhits.Bank' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot '04_motion\curves.cs'), (Join-Path $PSScriptRoot '06_sound\bank.cs') }
# And the tool that plays a run back into a file from what it asked of the voices.
if (-not ('Myhits.Mix' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot '..\tools\mix.cs') }

# Run one proof's program through its script and hold it to its own numbered
# checks, then to what every proof owes: a clean exit, no diagnostics, the
# contract met. Returns its report.
function Run-Proof([string]$mode, [string]$tag, [hashtable]$checks, [string]$program = "myhits_$tag.exe") {
    $logRoot = Join-Path $BuildDir "myhits_checks\$mode\$tag"
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir $program)).Path
    $imports = (& dumpbin.exe /NOLOGO /IMPORTS $executable | Out-String)
    Assert-True ($imports -notmatch '(?i)\bvulkan-1\.dll\b|\bgdi32\.dll\b') "The $tag proof imports Vulkan or GDI directly"
    # The layer is its own: a program is one object, and the linker's map names no other.
    $objects = @([regex]::Matches([IO.File]::ReadAllText(($executable -replace '\.exe$', '.map')), '(?i)\b[\w.]+\.obj\b') | ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique)
    Assert-True ($objects.Count -eq 1 -and $objects[0] -match '^myhits') "The $tag proof is linked from more than its own object: $($objects -join ', ')"
    $report = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot, '--self-test')
    [IO.File]::WriteAllText((Join-Path $logRoot 'debugger.log'), $report)
    Assert-True ($report -notmatch 'VUID-|SYNC-HAZARD') "The $tag proof emitted a validation diagnostic"
    Assert-True ($report.Contains('[myhits] exit: app_io=0 validation=0 debug_io=0')) "The $tag proof did not shut down cleanly"
    if ($mode -eq 'validation') {
        Assert-True ($report.Contains('VK_LAYER_KHRONOS_validation') -and $report.Contains('- Synchronization')) 'Core/sync validation was not enabled'
    }
    $state = Read-State (Join-Path $BuildDir "myhits_$tag.report.txt")
    Copy-Item -LiteralPath (Join-Path $BuildDir "myhits_$tag.report.txt") -Destination $logRoot
    # Pictures the run left of itself: as PNGs beside its log.
    Add-Type -AssemblyName System.Drawing
    foreach ($picture in @(Get-ChildItem -LiteralPath $BuildDir -Filter "myhits_$tag.*.bmp")) {
        $bitmap = New-Object System.Drawing.Bitmap $picture.FullName
        $bitmap.Save((Join-Path (Resolve-Path -LiteralPath $logRoot).Path ("frame_{0:000}.png" -f [int]($picture.BaseName -replace '^.*\.', ''))), [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        [IO.File]::Delete($picture.FullName)
    }
    $failure = [int]$state.failure
    Assert-True ($failure -eq 0) "$tag check $failure failed at frame $($state.failure_frame): $($checks[$failure])"
    Assert-True ([int]$state.gpu_error -eq 0 -and [int]$state.failure_stage -eq 0) "A device failure was hidden in the $tag proof"
    Assert-True (([int]$state.caps -band [int]$state.required) -eq [int]$state.required) 'The contract was not met'
    return $state
}

# 01: what the header promises is what the compiler did. Every member line of
# the generated header carries its offset; every module that uses a boundary
# block must decorate the same member with the same offset.
$promised = @{}
$block = $null
foreach ($line in [IO.File]::ReadAllLines((Join-Path $BuildDir 'myhits_shared.slang'))) {
    if ($line -match '^struct (\w+)') { $block = $Matches[1] }
    elseif ($line -match '^\s+\S+\s+(\w+)(?:\[\d+\])?;\s+// (\d+)$') { $promised["$block.$($Matches[1])"] = [int]$Matches[2] }
}
Assert-True ($promised['Root.world'] -eq 0 -and $promised.ContainsKey('Events.sound') -and $promised.ContainsKey('Picture.checksum')) 'The generated header lists no boundary members'
$modules = @(Get-ChildItem -LiteralPath $BuildDir -Filter 'myhits_*.spv')
Assert-True ($modules.Count -ge 60) 'The proofs'' shaders were not built'
$checked = 0
$pulling = 0
foreach ($module in $modules) {
    $code = (& $spirvDis $module.FullName | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "Could not read $($module.Name)"
    # SV_VertexID and SV_InstanceID would bring this in, and a feature with it.
    Assert-True ($code -notmatch 'OpCapability DrawParameters') "$($module.Name) needs shaderDrawParameters"
    # Nothing is bound: whatever memory a module reaches, it reaches through a
    # pointer. (One that only computes, like a plot of a curve, reaches none.)
    Assert-True ($code -notmatch 'OpTypeImage|OpTypeSampler|DescriptorSet|OpVariable %\S+ (Uniform|StorageBuffer|UniformConstant)\b') "$($module.Name) binds a descriptor"
    if ($code -match 'OpCapability PhysicalStorageBufferAddresses') { $pulling++ }
    else { Assert-True ($module.Name -match '_plot_|_particle_fragment|_veil_fragment|_backdrop_fragment') "$($module.Name) reaches no memory, and is not one of the shaders known to need none" }
    $names = @{}
    foreach ($match in [regex]::Matches($code, 'OpMemberName (%\S+) (\d+) "(\w+)"')) { $names["$($match.Groups[1].Value) $($match.Groups[2].Value)"] = $match.Groups[3].Value }
    foreach ($match in [regex]::Matches($code, 'OpMemberDecorate (%(Root|Events|Trigger|Pictures|Picture|Stroke|Census|Tables|Move|Kind|Style|Recipe|Wave|Stem|Curve|Glyph|Band|Placed|TextCensus|Examined|Laid|Line|Text)(?:_\w+)?) (\d+) Offset (\d+)')) {
        $member = "$($match.Groups[2].Value).$($names["$($match.Groups[1].Value) $($match.Groups[3].Value)"])"
        Assert-True ($promised.ContainsKey($member)) "$($module.Name) has $member, which shared.inc does not"
        Assert-True ($promised[$member] -eq [int]$match.Groups[4].Value) "$($module.Name) puts $member at $($match.Groups[4].Value), shared.inc at $($promised[$member])"
        $checked++
    }
}
$atomics = [regex]::Matches((& $spirvDis (Join-Path $BuildDir 'myhits_style_collide.spv') | Out-String), 'OpAtomicIAdd').Count
Assert-True ($atomics -ge 4) 'The collision sketch lost its atomics'
# And the layer stands on the projection alone: no source here includes one of the examples'.
$borrowed = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'source') -Recurse -Include *.inc, *.asm, *.slang | Select-String -Pattern '^\s*#?(include|import)\b.*examples')
Assert-True ($borrowed.Count -eq 0) "A source includes something of the examples': $($borrowed | ForEach-Object { "$($_.Filename):$($_.LineNumber)" })"

Write-Host "[myhits] 01 style: $($modules.Count) modules valid, none binds a descriptor, $pulling reach memory through pointers; $checked member offsets match shared.inc; $atomics atomics through pointers in the collision sketch"

$previousLayers = $env:VK_INSTANCE_LAYERS
$previousSync = $env:VK_LAYER_VALIDATE_SYNC
$previousFeatures = $env:VK_LAYER_ENABLES
$modes = @('default')
if ($Validation) { $modes += 'validation' }
$gameSums = $null
try {
    foreach ($mode in $modes) {
        $env:VK_INSTANCE_LAYERS = $previousLayers
        $env:VK_LAYER_VALIDATE_SYNC = $previousSync
        $env:VK_LAYER_ENABLES = $previousFeatures
        if ($mode -eq 'validation') {
            $env:VK_INSTANCE_LAYERS = 'VK_LAYER_KHRONOS_validation'
            if ($previousLayers) { $env:VK_INSTANCE_LAYERS += ';' + $previousLayers }
            $env:VK_LAYER_VALIDATE_SYNC = '1'
            $env:VK_LAYER_ENABLES = $null
        }
        # 02: the spine. The program checks every frame itself and reports the first failure by number.
        $state = Run-Proof $mode 'spine' @{ 1='events out of order'; 2='an atomic add to host-visible memory was lost'; 3='an atomic add to device-local memory was lost'
            4='the controls did not move the player in their own frame'; 5='the pulled draw shaded the wrong number of pixels'
            6='events were not in hand when the next frame began'; 7='a sound trigger''s pan is out of range'; 8='not every frame''s events were read'
            9='more or less than Root went down'; 10='more or less than Events came back'; 11='the frame is not two dispatches and one draw'
            12='a window of another shape did not keep the playfield''s' }
        $frames = [int]$state.frames
        Assert-True ($frames -eq 121 -and [int]$state.events -eq $frames) 'The spine did not run its script'
        Assert-True ([int]$state.view_width -eq 888 -and [int]$state.view_height -eq 500) 'The playfield did not keep 16:9 in a 1200 x 500 window'
        Assert-True ([int]$state.root_bytes -le 128 -and [int]$state.events_bytes -eq 512) 'A boundary block outgrew its budget'
        Assert-True ([long]$state.bytes_down -eq $frames * [int]$state.root_bytes -and [long]$state.bytes_up -eq $frames * 512) 'The CPU traffic is not what the plan allows'
        Write-Host ("[myhits] $mode/02 spine: {0} frames; {1} bytes down and {2} up a frame; {3} dispatches and {4} draw a frame; atomics exact on {5} motes; controls land in their own frame; events {6} frame later; {7} pixels pulled; playfield {8} x {9} in a 1200 x 500 window" -f `
            $frames, $state.root_bytes, $state.events_bytes, ([int]$state.dispatches / $frames), ([int]$state.draws / $frames), $state.motes, $state.worst_latency, $state.shaded, $state.view_width, $state.view_height)

        # 03: pictures. The packer's counts are the reference; the device's must be the same.
        $state = Run-Proof $mode 'pictures' @{ 1='events out of order, or late'; 2='a packed frame did not reach the device as the packer left it'
            3='a made frame is empty, or a drawn one does not cover what its strokes do'; 4='a symmetric frame''s mask is not'
            5='the masks are not what is drawn'; 6='the controls did not move the ship in their own frame'; 7='the pass did not set down every sprite the draw pulls'
            8='the light turned with the pictures, or fell on the wrong side'; 9='more than Root went down or Events came back'
            10='the pictures were not made in three passes, or a frame is not one pass and one draw'; 11='the pad''s mapping is wrong' }
        $frames = [int]$state.frames
        Assert-True ($frames -eq 120 -and [int]$state.events -eq $frames) 'The pictures proof did not run its script'
        $table = [IO.File]::ReadAllText((Join-Path $BuildDir 'myhits_art.inc'))
        $packed = if ($table -match 'ART_BAKED_SOLID := (\d+)') { [int]$Matches[1] } else { -1 }
        Assert-True ([int]$state.baked_solid -eq $packed) "The device counts $($state.baked_solid) solid texels in the packed frames; the packer counted $packed"
        Assert-True ([long]$state.bytes_down -eq $frames * 72 -and [long]$state.bytes_up -eq $frames * 512) 'The CPU traffic is not what the plan allows'
        $lit = 100.0 * [int]$state.toward / ([int]$state.toward + [int]$state.away)
        $fixed = 100.0 * [int]$state.fixed_toward / ([int]$state.fixed_toward + [int]$state.fixed_away)
        Write-Host ("[myhits] $mode/03 pictures: {0} frames ({1} packed, {2} KB up once), {3} texels and {4} mask words made in {5} passes; {6} solid texels, as packed; masks cover {7} pixels and pictures {8}; {9:0}% of the light on the lit side ({10:0}% had it turned with the pictures); {11} sprites in {12} pass and {13} draw a frame" -f `
            $state.art_frames, $state.baked_frames, [int]([int]$state.packed_bytes / 1024), $state.texels, $state.mask_words, $state.startup_dispatches, $state.baked_solid,
            $state.mask_pixels, $state.picture_pixels, $lit, $fixed, $state.sprites, ([int]$state.dispatches / $frames), ([int]$state.draws / $frames))

        # 04: motion. The program checks its own claims; the curves it read back from the device are held here to a second implementation.
        $state = Run-Proof $mode 'motion' @{ 1='events out of order, or late'; 2='the device found a fault in its own curves'; 3='a scripted frame did not run two ticks'
            4='the controls did not move the ship in their own frame'; 5='the missile''s offset did not end where it says'; 6='the missile did not come to face the crosshair'
            7='the missile did not reach its speed on the line to the crosshair'; 8='what rides the level did not ride it exactly, or the level did not stand still'
            9='shots fired, missed and flying do not add up, or the level came the wrong distance'; 10='the traffic or the passes of a frame are not what the plan allows'
            11='a press was lost, repeated or invented'; 12='a stall was chased, or time was paid out wrongly'
            13='a body told to go twice as quick did not do its move in half the ticks, or did not end where the move says' }
        $frames = [int]$state.frames
        Assert-True ($frames -eq 200 -and [int]$state.events -eq $frames -and [int]$state.ticks -eq 2 * $frames) 'The motion proof did not run its script'

        $worst = ([Myhits.Curves]::Compare((Resolve-Path -LiteralPath (Join-Path $BuildDir 'myhits_motion.curves.bin')).Path, [int]$state.samples)) -split ' '
        Assert-True ([double]$worst[0] -lt 1e-4) "The device's $($worst[1]) is $($worst[0]) from the textbook's at sample $($worst[2])"
        Write-Host ("[myhits] $mode/04 motion: {0} curves by {1} samples within {2} of a second implementation (worst: {3}); {4} ticks a second, 2 a scripted frame; {5} kinds in {6} moves; the missile's three moves end where they say; {7} fired, {8} missed, {9} flying; the level stood still for 40 frames and came {10}; {11} passes and {12} draws a frame" -f `
            $state.curves, $state.samples, $worst[0], $worst[1], $state.tick_rate, ([int]$state.kinds - 1), $state.moves, $state.fired, $state.escaped, $state.flying, $state.scroll,
            ([int]$state.dispatches / $frames), ([int]$state.draws / $frames))

        # 05: hits. The packer's count of solid texels is the reference from outside the device.
        $state = Run-Proof $mode 'hits' @{ 1='events out of order, or late'; 2='a texel is not hit where it is drawn, or the solid texels are not the packer''s'
            3='a shot is unaccounted for'; 4='a shot did not strike the ring where the ring begins'; 5='a lance passed through a wall'
            6='a shot struck the empty corner of a picture'; 7='the drone did not die of its third hit, for its worth'
            8='a near miss hurt the ship, or a touch did not, or hurt it twice, or was not felt'; 9='the particles are not six a hit and 48 a death, or a style let in more than its cap, or some never died'
            10='the sounds asked for are not the things that happened'; 11='the traffic or the passes of a frame are not what the plan allows'
            12='something crossing a wall one texel thick slipped between two of its texels' }
        $frames = [int]$state.frames
        Assert-True ($frames -eq 280 -and [int]$state.events -eq $frames) 'The hits proof did not run its script'
        Assert-True ([int]$state.solid -eq $packed) "The hits proof was built against $($state.solid) solid texels; the packer counted $packed"
        Assert-True ([int]$state.fired -eq [int]$state.struck + [int]$state.escaped + [int]$state.flying) 'A shot is unaccounted for at the end'
        Write-Host ("[myhits] $mode/05 hits: {0} solid texels hit exactly where drawn, through four poses; {1} fired = {2} struck + {3} missed; a lance at 50 units a tick still struck a wall 12 thick; {4} killed for {5}; hurt {6} time by a touch and not by a near miss; {7} particles asked for, {8} left; sounds for {9} shots, {10} hits, {11} death, {12} hurt; {13} passes and {14} draws a frame" -f `
            $state.solid, $state.fired, $state.struck, $state.escaped, $state.kills, $state.score, $state.hurts, $state.particles_asked, $state.particles_live,
            $state.heard_shots, $state.heard_hits, $state.heard_bursts, $state.heard_hurts, ([int]$state.dispatches / $frames), ([int]$state.draws / $frames))

        # 06: sound. The bank the device rendered is held to a second synthesis of the same recipes, and written out to be listened to.
        $state = Run-Proof $mode 'sound' @{ 1='events out of order, or late'; 2='the device found a fault in its own bank'
            3='a frame did not ask for what its script says, or what it asked for did not go to one voice'; 4='five in a frame were not one voice at their mean, twice as loud'
            5='the sounds did not all go to voices, or a voice refused one'; 6='the engine did not play out what it was given'
            7='the traffic or the passes of a frame are not what the plan allows' }
        $frames = [int]$state.frames
        Assert-True ($frames -eq 100 -and [int]$state.events -eq $frames) 'The sound proof did not run its script'
        $dump = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'myhits_sound.bank.bin')).Path
        $heard = ([Myhits.Bank]::Compare($dump, (Join-Path $repoRoot 'source\myhits\tables.inc'))) -split ' '
        Assert-True ([int]$heard[1] -eq [int]$state.bank_samples -and [int]$heard[4] -eq [int]$state.sounds) 'The bank is not the size the recipes make'
        Assert-True ([int]$heard[0] * 1000 -le [int]$heard[1]) "$($heard[0]) of the bank's $($heard[1]) samples are not the second implementation's; the worst sound is $($heard[2])"
        [Myhits.Bank]::WriteWav($dump, (Join-Path (Split-Path $dump) 'myhits_sound.bank.wav'))
        $device = if ([int]$state.device) { "{0} sounds went to {1} voices and were played out, silently; the engine adds {2:0} ms" -f $state.plays, $state.voices, (1000.0 * [int]$state.engine_latency_samples / [int]$state.rate) }
                  else { 'there is no audio device here, so no voice was exercised' }
        Write-Host ("[myhits] $mode/06 sound: {0} sounds in {1} samples ({2:0.00} s) rendered on the device; all but {3} within 0.002 of a second implementation (rms {4}); {5}; a sound asked for in one frame is on its voice as the next begins; bank written to {6}\myhits_sound.bank.wav" -f `
            $state.sounds, $state.bank_samples, ([int]$state.bank_samples / [double]$state.rate), $heard[0], $heard[3], $device, $BuildDir)

        # 07: the game, through its own scripted run of four games.
        $state = Run-Proof $mode 'game' @{ 1='events out of order, or late'; 2='what came was not what the table says, when it says'; 3='a shot is unaccounted for'
            4='rank did not read the shooting, or a hurt, as it should'; 5='a chain did not follow its head exactly'; 6='a FIRE did not become a body in the next tick'
            7='a hurt did not cost one life, or two came within the grace, or the run did not end with the last, or begin again on Enter'
            8='the level did not stop for what was anchored to it, or did not move on'; 9='the chain did not die with its head'
            10='a rise or fall of rank, or the death of the head, was never seen'; 11='the sounds asked for did not each go to a voice, or a hurt was not heard'
            12='the traffic or the passes of a frame are not what the plan allows'; 13='the score the HUD shows passed the real one, or never caught it'
            14='a hurt did not stop the world for four ticks, or the pad was told wrongly'; 15='a bonus set down before the ship was not taken, or was taken twice'
            16='the shield did not take the next hurt, or a life went with it'; 17='RAPID did not double the shots, or SPREAD did not treble them'
            18='the nova did not strike everything, or DOUBLE did not double exactly'
            19='the companion did not come with the worm''s death, or was not where the ship had been, or did not guard, fire or take aim as its stage should'
            20='the level did not wait for the dragon, or did not move on when it died'
            22='a stem of the music is too loud or silent, or the stems are not wanted as they should be, or are not playing'
            23='the window did not pause, or was not a handle when paused, or did not take or give back its monitor exactly'
            24='charge was not earned or spent as it should be, or a dash did not go its distance or did not slip a shot'
            25='the hail-mary missed a beat: the fix, the lock, the shot to the lock, the recoil, the fade, the burst, or what each cost'
            26='the window was not remembered: its place, or whether it had the whole monitor'
            27='something alive was written over, or what there was no room for was not refused and counted, or segments followed a stranger'
            30='with the level very far on, a layer of the backdrop that repeats would not be what it was, or one that does not would stand in steps'
            32='tables offered from a file were not taken, refused or left alone as they should be; or the device did not hold what was taken, or the bank or the music was not made again from it; or what was running was not let go, or the squad did not come again as the new tables have it' } 'myhits.exe'
        $frames = [int]$state.frames
        Assert-True ($frames -eq 1330 -and [int]$state.events -eq $frames) 'The game did not run its script'
        # 28: two runs are the same run. The sum over everything simulated, at the end of each of the
        # four games, is what it was the last time the script ran, whatever order the threads ran in:
        # a second run here and now, and every mode against the first.
        if (-not $gameSums) {
            $gameSums = $state.sums
            $again = [VkFasmgTests.DebugOutputCapture]::Run((Resolve-Path -LiteralPath (Join-Path $BuildDir 'myhits.exe')).Path, $repoRoot, '--self-test')
            $second = (Read-State (Join-Path $BuildDir 'myhits_game.report.txt')).sums
            Get-ChildItem -LiteralPath $BuildDir -Filter 'myhits_game.*.bmp' | ForEach-Object { [IO.File]::Delete($_.FullName) }
            Assert-True ($second -eq $gameSums) "game check 28 failed: one run of the script summed to $gameSums and the next to $second"
        }
        Assert-True ($state.sums -eq $gameSums -and $gameSums -notmatch '00000000') "game check 28 failed: this run of the script summed to $($state.sums) and the first to $gameSums"
        # 29: what a tick costs the device is within its budget. The game stamps the device's clock
        # after each pass; the means over the run, in nanoseconds, are held to budgets several times
        # what they were when the budgets were written, so that only a real regression fails.
        $measured = Read-Measure (Join-Path $BuildDir 'myhits_game.measure.txt')
        Copy-Item -LiteralPath (Join-Path $BuildDir 'myhits_game.measure.txt') -Destination (Join-Path $BuildDir "myhits_checks\$mode\game")
        $budget = [ordered]@{ director = 1, 100000; bodies = 2, 60000; shots = 3, 200000; struck = 4, 40000; particles = 5, 40000 }
        $tick = 0
        foreach ($pass in $budget.Keys) {
            $mean = [int]$measured["stamp_$($budget[$pass][0])"][0]
            Assert-True ($mean -gt 0) "game check 29 failed: the $pass pass was never timed"
            if ($mode -eq 'default') { Assert-True ($mean -le $budget[$pass][1]) "game check 29 failed: the $pass pass takes $mean ns a tick; its budget is $($budget[$pass][1])" }
            $tick += $mean
        }
        $picture = 0; foreach ($stamp in 7, 8, 9, 10, 15) { $picture += [int]$measured["stamp_$stamp"][0] }
        $costs = "a tick costs the device {0:0} microseconds, its director {1:0}; a picture {2:0}" -f ($tick / 1000), ([int]$measured['stamp_1'][0] / 1000), ($picture / 1000)
        $voices = if ([int]$state.device) { "$($state.plays) sounds to voices" } else { 'no audio device here' }
        # The music the device rendered is the notes of tables.inc, by a second synthesis; and it is written out to be listened to.
        $stems = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'myhits_game.music.bin')).Path
        $played = ([Myhits.Bank]::CompareMusic($stems, (Join-Path $repoRoot 'source\myhits\tables.inc'))) -split ' '
        Assert-True ([int]$played[0] * 1000 -le [int]$played[1]) "$($played[0]) of the music's $($played[1]) samples are not the second implementation's"
        [Myhits.Bank]::WriteMix($stems, (Join-Path (Split-Path $stems) 'myhits_music.wav'), [int]$played[2])
        # 33: the run can be listened to, and nothing in it is out of line. What every frame asked of
        # the voices is played back into a file, as audio.inc would play it, from the bank the device
        # rendered: every sound the run asked for is in what was kept; the mix is neither silent nor
        # crushed; hardly a sample of it is louder than a speaker goes; and no sound stands more than
        # twelve decibels from the middle of them.
        $logRoot = (Resolve-Path -LiteralPath (Join-Path $BuildDir "myhits_checks\$mode\game")).Path
        $mix = @{}
        foreach ($word in ([Myhits.Mix]::Run((Join-Path (Split-Path $stems) 'myhits_game.heard.bin'), (Join-Path (Split-Path $stems) 'myhits_game.sounds.bin'), $stems,
                (Join-Path $repoRoot 'source\myhits\tables.inc'), (Join-Path (Split-Path $stems) 'myhits_run.wav'), (Join-Path $logRoot 'run.md'), 1250) -split ' ')) {
            $name, $value = $word -split '=', 2
            $mix[$name] = $value
        }
        $culture = [Globalization.CultureInfo]::InvariantCulture
        Assert-True ([int]$mix.asked_all -eq [int]$state.sounds_asked) "game check 33 failed: the run asked for $($state.sounds_asked) sounds and $($mix.asked_all) were kept for the mix"
        Assert-True ([double]::Parse($mix.level, $culture) -gt -40 -and [double]::Parse($mix.level, $culture) -lt -6) "game check 33 failed: the mix's level is $($mix.level) dB"
        Assert-True ([int]$mix.clipped * 10000 -lt [int]$mix.samples -and [double]::Parse($mix.peak, $culture) -lt 3) "game check 33 failed: $($mix.clipped) of the mix's $($mix.samples) samples are louder than a speaker goes, and its peak is $($mix.peak) dB"
        Assert-True ([Math]::Abs([double]::Parse($mix.apart, $culture)) -le 12) "game check 33 failed: $($mix.furthest) stands $($mix.apart) dB from the middle of the sounds"
        # The backdrop is the level's, and this is held on the pictures themselves. Along the top rail,
        # frames 300 and 320 are the same to the pixel: the level stood still between them. Frames 235
        # and 300 are not: it moved.
        $rail = @{}
        foreach ($frame in 235, 300, 320) {
            $picture = New-Object System.Drawing.Bitmap (Join-Path $BuildDir "myhits_checks\$mode\game\frame_$frame.png")
            $rail[$frame] = -join (0..($picture.Width - 1) | ForEach-Object { '{0:x8}' -f $picture.GetPixel($_, 8).ToArgb() })
            $picture.Dispose()
        }
        Assert-True ($rail[300] -eq $rail[320]) 'The backdrop moved while the level stood still'
        Assert-True ($rail[235] -ne $rail[300]) 'The backdrop stood still while the level moved'
        # 31: a pause is in words. Where the line that says what the keys do is drawn, the paused
        # frame has letters, pale on the dimmed picture, and a frame that is not paused has none.
        $pale = @{}
        foreach ($frame in 900, 950) {
            $picture = New-Object System.Drawing.Bitmap (Join-Path $BuildDir "myhits_checks\$mode\game\frame_$frame.png")
            $count = 0
            foreach ($y in 714..746) { foreach ($x in 400..1520) { $pixel = $picture.GetPixel($x, $y); if ($pixel.R -gt 170 -and $pixel.G -gt 170 -and $pixel.B -gt 170) { ++$count } } }
            $picture.Dispose()
            $pale[$frame] = $count
        }
        Assert-True ($pale[950] -gt 1500 -and $pale[900] -lt 100) "game check 31 failed: the paused frame has $($pale[950]) pale pixels where its words should be, and a frame that is not paused has $($pale[900])"
        # 32, in part: tables taken are said to be, along the top, in the frames after; and at no other time.
        $said = @{}
        foreach ($frame in 900, 1290) {
            $picture = New-Object System.Drawing.Bitmap (Join-Path $BuildDir "myhits_checks\$mode\game\frame_$frame.png")
            $count = 0
            foreach ($y in 52..88) { foreach ($x in 760..1160) { $pixel = $picture.GetPixel($x, $y); if ($pixel.R -gt 200 -and $pixel.G -gt 170 -and $pixel.B -gt 90 -and $pixel.R -gt $pixel.B + 30) { ++$count } } }
            $picture.Dispose()
            $said[$frame] = $count
        }
        Assert-True ($said[1290] -gt 1000 -and $said[900] -lt 100) "game check 32 failed: the frame after the tables were taken has $($said[1290]) pixels of words along its top, and a frame long before has $($said[900])"
        Assert-True ([int]$state.reloads -eq 5 -and [int]$state.reloads_refused -eq 1) 'game check 32 failed: the tables were not taken five times and refused once'
        # 34: a run that was recorded is the same run played back. The scripted run keeps every
        # frame's controls, the tables it took on the way, and what each frame came to, in a file
        # as it goes. The game is then run from that file and not from its script, with no frame
        # of it shown: every frame comes to what the record says it came to, and all of them,
        # folded into one number, to what the scripted run's did.
        $kept = ''
        if ($mode -eq 'default') {
            $game = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'myhits.exe')).Path
            $replayed = [VkFasmgTests.DebugOutputCapture]::Run($game, $repoRoot, '--self-test --replay')
            [IO.File]::WriteAllText((Join-Path $logRoot 'replay.log'), $replayed)
            $back = Read-State (Join-Path $BuildDir 'myhits_game.report.txt')
            Assert-True ($replayed.Contains('[myhits] exit: app_io=0 validation=0 debug_io=0') -and $back.proof -eq 'game_replay' -and [int]$back.failure -eq 0) 'game check 34 failed: the run could not be played back from its record'
            Assert-True ([int]$back.replay_left -eq 0 -and [int]$back.replay_held -eq $frames) "game check 34 failed: played back, the run left its record at frame $([int]$back.replay_left - 1); $($back.replay_held) of its $frames frames were held to it"
            Assert-True ([int]$back.frames -eq $frames -and $back.frames_sum -eq $state.frames_sum -and $state.frames_sum -notmatch '^0+$') "game check 34 failed: the run's $frames frames came to $($state.frames_sum), and played back from its record, $($back.frames) frames came to $($back.frames_sum)"
            $kept = " a run played back from its record of $((Get-Item -LiteralPath (Join-Path $BuildDir 'myhits_game.run')).Length) bytes, unseen, is the same run, frame for frame ($($back.frames_sum));"
            # And a run somebody played, whose frames are of no ticks, one, two and three as a clock
            # had it: 07_game\played.run. It was kept before records said what their frames came to,
            # so it is played back once and kept again as it goes, and that record is played back
            # and held to itself.
            $played = Join-Path $PSScriptRoot '07_game\played.run'
            $names = [BitConverter]::ToUInt32([IO.File]::ReadAllBytes((Join-Path $BuildDir 'myhits_tables.bin')), 4)
            if ([BitConverter]::ToUInt32([IO.File]::ReadAllBytes($played), 8) -eq $names) {
                $again = Join-Path $BuildDir 'myhits_played.run'
                $turns = @()
                foreach ($arguments in "--self-test --replay source\myhits\proofs\07_game\played.run --record $again", "--self-test --replay $again") {
                    $said = [VkFasmgTests.DebugOutputCapture]::Run($game, $repoRoot, $arguments)
                    Assert-True ($said.Contains('[myhits] exit: app_io=0 validation=0 debug_io=0')) 'game check 34 failed: the played run could not be played back'
                    $turns += Read-State (Join-Path $BuildDir 'myhits_game.report.txt')
                }
                Assert-True ([int]$turns[0].frames -gt 1000 -and $turns[1].frames -eq $turns[0].frames -and $turns[1].frames_sum -eq $turns[0].frames_sum) "game check 34 failed: the played run's $($turns[0].frames) frames came to $($turns[0].frames_sum), and kept and played back again, $($turns[1].frames) came to $($turns[1].frames_sum)"
                Assert-True ([int]$turns[1].replay_left -eq 0 -and $turns[1].replay_held -eq $turns[1].frames) "game check 34 failed: the played run, kept again and played back, left its record at frame $([int]$turns[1].replay_left - 1)"
                $kept += " and so is a run somebody played, $($turns[1].frames) frames and $($turns[1].ticks) ticks of it, to a score of $($turns[1].score);"
            } else {
                $kept += ' the played run that is kept is of other names than the game now has, and was not played back;'
            }
        }
        # 35: a run can be read on a page, and a level looked at without being survived. The strip
        # tool plays the scripted run's record back unseen but for a picture every ten seconds, and
        # lays the pictures side by side: there are nine, at the times asked; they are pictures, and
        # not one picture nine times; and the run comes to what it did, pictured or not. Then two
        # runs the tool makes itself, of a ship that does nothing for forty seconds: a ghost, which
        # nothing hurts, still has its three lives; a ship that can be hurt has lost some.
        $read = ''
        if ($mode -eq 'default') {
            $tool = Join-Path $PSScriptRoot '..\tools\strip.ps1'
            $page = Join-Path $logRoot 'strip.png'
            $lines = Join-Path $BuildDir 'myhits_game.strip.txt'
            & $tool -Run (Join-Path $BuildDir 'myhits_game.run') -Every 10 -Out $page -BuildDir $BuildDir 6>$null
            $pictures = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $lines).Path, [Text.Encoding]::Unicode) | Where-Object { $_ })
            $pictured = Read-State (Join-Path $BuildDir 'myhits_game.report.txt')
            Assert-True ($pictures.Count -eq 9) "game check 35 failed: a picture every ten seconds of the run is nine pictures, and there are $($pictures.Count)"
            foreach ($index in 1..8) { Assert-True ([int]($pictures[$index] -split ' ')[1] -eq 1200 * $index) "game check 35 failed: picture $index is of tick $(($pictures[$index] -split ' ')[1]), not $(1200 * $index)" }
            Assert-True ($pictured.frames_sum -eq $state.frames_sum) "game check 35 failed: pictured, the run came to $($pictured.frames_sum) and not $($state.frames_sum)"
            $bitmap = New-Object System.Drawing.Bitmap $page
            Assert-True ($bitmap.Width -eq 2880 -and $bitmap.Height -eq 584) "game check 35 failed: the page is $($bitmap.Width) by $($bitmap.Height)"
            # The second picture and the fifth, at the same places in each: a page of one picture would have them alike.
            $unlike = 0
            foreach ($y in 60, 120, 180, 240) { foreach ($x in 40, 120, 200, 280, 360, 440) { if ($bitmap.GetPixel(480 + $x, 22 + $y).ToArgb() -ne $bitmap.GetPixel(4 * 480 + $x, 22 + $y).ToArgb()) { ++$unlike } } }
            $bitmap.Dispose()
            Assert-True ($unlike -ge 6) "game check 35 failed: two pictures of the page ten and forty seconds into the run differ in only $unlike of 24 places"
            $lives = @{}
            foreach ($sort in 'ghost', 'mortal') {
                & $tool -Seconds 40 -Every 20 -Mortal:($sort -eq 'mortal') -Out (Join-Path $logRoot "$sort.png") -BuildDir $BuildDir 6>$null
                $last = @([IO.File]::ReadAllLines((Resolve-Path -LiteralPath $lines).Path, [Text.Encoding]::Unicode) | Where-Object { $_ })[-1] -split ' '
                $lives[$sort] = [int]$last[4]
            }
            Assert-True ($lives.ghost -eq 3 -and $lives.mortal -lt 3) "game check 35 failed: after forty seconds of doing nothing a ghost has $($lives.ghost) lives and a ship that can be hurt has $($lives.mortal)"
            $read = " a run is read on a page of nine pictures, and comes to the same pictured; a ghost keeps its three lives where a ship keeps $($lives.mortal);"
        }
        Write-Host ("[myhits] $mode/07 game: {0} frames of {1} ticks through four games; {2} kinds in {3} moves, {4} squads; a world of {5} KB on the device; waves by the table; a chain a spacing behind its head and dead with it (frame {6}); a FIRE a body one tick on; rank up for hits, down for misses and {7} hurts; the level stopped and moved on, and its backdrop with it, to the pixel; {8}; the music is its notes, written to $BuildDir\myhits_music.wav; the run as it sounded is $BuildDir\myhits_run.wav, $($mix.seconds) seconds at $($mix.level) dB, its peak $($mix.peak) dB with $($mix.clipped) samples cut off, and $($mix.furthest) the sound furthest from the rest, by $($mix.apart) dB; charge is earned and spent, and a dash slips a shot; a hail-mary fixes, locks and bursts where it locked, is dodged by moving and not stopped by killing; the window pauses, moves, takes its monitor and is remembered; nothing alive is written over, and what there is no room for is refused; its tables are taken again from a file as it runs ($($state.reload_bytes) bytes in five takings), and refused when their names are not its own; two runs sum to the same ($gameSums);$kept$read $costs; {9} passes and {10} draws a frame" -f `
            $frames, $state.ticks_a_frame, ([int]$state.kinds - 1), $state.moves, $state.squads, [int]([int]$state.world_bytes / 1024), $state.head_died_frame, $state.hurts_heard, $voices,
            ([int]$state.dispatches / $frames), ([int]$state.draws / $frames))

        # 08: text. The program checks what it can of itself; what is on the screen is held, in
        # 08_text\pictures.ps1, to the outlines' own areas and to what GDI+ makes of the same fonts.
        $state = Run-Proof $mode 'text' @{ 1='events out of order, or late'; 2='a cubic the system gave was cut, or too few were put back, or the shape''s eight were not cut, or a cubic''s pieces do not lie on it'
            3='a run was not set down where the system sets it'
            4='the system did not shape it: a kerned pair, a ligature, letters joined and right to left, a conjunct, a font found for a script, or a line as wide as its advances'
            5='a glyph''s bands did not give what all its curves give, or a band was crowded or went without room'
            6='how often a glyph''s places are enclosed did not come to what its curves enclose, or what is drawn of it is not that, less what is enclosed twice; or two discs were not found to be two discs'
            8='more than Root went down or Events came back'; 9='the text was not made ready in builds of four passes, takings of one and one examining of two, or a frame is not one pass and one draw'
            14='a letter came in layers, or a face of colors did not, or its layers are all one color'
            15='a line that was kept has not the glyphs the same string has set down, or the ten digits are not ten, or a line with a face in it has no glyphs of their font''s colors, or none of none'
            17='what is drawn from is not all in memory of the device''s own, or the device has not taken all there is' }
        $frames = [int]$state.frames
        Assert-True ($frames -eq 80 -and [int]$state.events -eq $frames) 'The text proof did not run its script'
        Assert-True ([long]$state.bytes_down -eq $frames * 72 -and [long]$state.bytes_up -eq $frames * 512) 'The CPU traffic is not what the plan allows'
        $logRoot = (Resolve-Path -LiteralPath (Join-Path $BuildDir "myhits_checks\$mode\text")).Path
        foreach ($kept in 'lines', 'glyphs', 'measure', 'kept', 'layers') { Copy-Item -LiteralPath (Join-Path $BuildDir "myhits_text.$kept.txt") -Destination $logRoot }
        # 7, 10, 11, 12, 14, 15, 16: the pictures.
        $seen = & (Join-Path $PSScriptRoot '08_text\pictures.ps1') -Lines (Join-Path $BuildDir 'myhits_text.lines.txt') -Kept (Join-Path $BuildDir 'myhits_text.kept.txt') `
            -Layers (Join-Path $BuildDir 'myhits_text.layers.txt') -Pages (5, 25, 45, 65 | ForEach-Object { Join-Path $logRoot ('frame_{0:000}.png' -f $_) })
        # 13: what a page costs the device to draw is within its budget: a millisecond, which is
        # many times what it was when this was written, so that only a real regression fails.
        $measured = Read-Measure (Join-Path $BuildDir 'myhits_text.measure.txt')
        $costs = @()
        foreach ($page in 0..3) {
            $mean = [int]$measured["stamp_$(2 + $page)"][0]
            Assert-True ($mean -gt 0) "text check 13 failed: the draw of page $page was never timed"
            if ($mode -eq 'default') { Assert-True ($mean -le 1000000) "text check 13 failed: page $page takes $mean ns to draw; its budget is 1000000" }
            $costs += '{0:0}' -f ($mean / 1000)
        }
        Write-Host ("[myhits] $mode/08 text: {0} glyphs of {1} fonts in {2} curves, shaped by the system: {3} cubics put back as the quadratics they were and {4} of the program's own cut in eight; {5} runs set down where the system sets them; {6} bands made on the device in {7} builds of four passes, from curves it took into memory of its own, the longest of {8} curves; $($state.layers_made) layers made of glyphs whose fonts have colors; {9} glyphs examined at {10} places, their bands giving what all their curves give at every one; how often the rays find a glyph enclosed comes to what its curves enclose within {11:0.0}%, and {12} glyphs whose contours lie over one another are drawn as the one shape they make; two discs enclose {13:0.0000} of a square em and cover {14:0.0000}, which should be 0.5655 and 0.4549; $seen; the four pages cost the device {15} microseconds to draw; {16} pass and {17} draw a frame" -f `
            $state.glyphs, $state.faces, $state.curves, $state.raised, $state.shape_cut, $state.runs_held, $state.bands, $state.builds, $state.longest, $state.examined, $state.samples,
            ([int]$state.worst_area_thousandths / 10.0), $state.overlapped, ([int]$state.shape_wound_millionths / 1e6), ([int]$state.shape_covered_millionths / 1e6), ($costs -join ', '),
            ([int]$state.dispatches / $frames), ([int]$state.draws / $frames))
    }
} finally {
    $env:VK_INSTANCE_LAYERS = $previousLayers
    $env:VK_LAYER_VALIDATE_SYNC = $previousSync
    $env:VK_LAYER_ENABLES = $previousFeatures
}
Write-Host '[myhits] Proofs passed.'
