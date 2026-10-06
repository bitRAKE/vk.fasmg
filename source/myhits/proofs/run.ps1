<# Run the myhits proofs and hold each to what it claims. README.md beside this
   file says what every check settles; this script is the checks themselves.

     01 style   the shaders compile to valid SPIR-V in the pointer style, and
                the compiler lays the boundary blocks out as shared.inc says
     02 spine   the CPU-GPU boundary works end to end on the device
     03 pictures  every frame is made, masked and drawn on the device, lit
                from one side however it turns
     04 motion  the easing curves are the textbook's; bodies run the tables'
                programs at a fixed tick; the level's pace is eased too

   -Validation repeats the device runs under Khronos core and synchronization
   validation and rejects any diagnostic.
#>
param([string]$BuildDir = 'build', [switch]$Validation)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Set-Location -LiteralPath $repoRoot
if (-not ('VkFasmgTests.DebugOutputCapture' -as [type])) { Add-Type -Path (Join-Path $repoRoot 'tests\capture-debug-output.cs') }
function Assert-True($condition, [string]$message) { if (-not $condition) { throw $message } }
function Read-State([string]$path) {
    $state = @{}
    foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::Unicode)) {
        if ($line -match '^(\w+)=(.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    return $state
}
$spirvDis = Join-Path $env:VULKAN_SDK 'Bin\spirv-dis.exe'

# Run one proof's program through its script and hold it to its own numbered
# checks, then to what every proof owes: a clean exit, no diagnostics, the
# contract met. Returns its report.
function Run-Proof([string]$mode, [string]$tag, [hashtable]$checks) {
    $logRoot = Join-Path $BuildDir "myhits_checks\$mode\$tag"
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir "myhits_$tag.exe")).Path
    $imports = (& dumpbin.exe /NOLOGO /IMPORTS $executable | Out-String)
    Assert-True ($imports -notmatch '(?i)\bvulkan-1\.dll\b|\bgdi32\.dll\b') "The $tag proof imports Vulkan or GDI directly"
    $report = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot, '--self-test')
    [IO.File]::WriteAllText((Join-Path $logRoot 'debugger.log'), $report)
    Assert-True ($report -notmatch 'VUID-|SYNC-HAZARD') "The $tag proof emitted a validation diagnostic"
    Assert-True ($report.Contains('[myhits] exit: app_io=0 validation=0 debug_io=0')) "The $tag proof did not shut down cleanly"
    if ($mode -eq 'validation') {
        Assert-True ($report.Contains('VK_LAYER_KHRONOS_validation') -and $report.Contains('- Synchronization')) 'Core/sync validation was not enabled'
    }
    $state = Read-State (Join-Path $BuildDir "myhits_$tag.report.txt")
    Copy-Item -LiteralPath (Join-Path $BuildDir "myhits_$tag.report.txt") -Destination $logRoot
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
Assert-True ($modules.Count -ge 25) 'The proofs'' shaders were not built'
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
    $names = @{}
    foreach ($match in [regex]::Matches($code, 'OpMemberName (%\S+) (\d+) "(\w+)"')) { $names["$($match.Groups[1].Value) $($match.Groups[2].Value)"] = $match.Groups[3].Value }
    foreach ($match in [regex]::Matches($code, 'OpMemberDecorate (%(Root|Events|Trigger|Pictures|Picture|Stroke|Census|Tables|Move|Kind)(?:_\w+)?) (\d+) Offset (\d+)')) {
        $member = "$($match.Groups[2].Value).$($names["$($match.Groups[1].Value) $($match.Groups[3].Value)"])"
        Assert-True ($promised.ContainsKey($member)) "$($module.Name) has $member, which shared.inc does not"
        Assert-True ($promised[$member] -eq [int]$match.Groups[4].Value) "$($module.Name) puts $member at $($match.Groups[4].Value), shared.inc at $($promised[$member])"
        $checked++
    }
}
$atomics = [regex]::Matches((& $spirvDis (Join-Path $BuildDir 'myhits_style_collide.spv') | Out-String), 'OpAtomicIAdd').Count
Assert-True ($atomics -ge 4) 'The collision sketch lost its atomics'
Assert-True ($pulling -ge $modules.Count - 2) 'More than the two plot shaders reach no memory'
Write-Host "[myhits] 01 style: $($modules.Count) modules valid, none binds a descriptor, $pulling reach memory through pointers; $checked member offsets match shared.inc; $atomics atomics through pointers in the collision sketch"

$previousLayers = $env:VK_INSTANCE_LAYERS
$previousSync = $env:VK_LAYER_VALIDATE_SYNC
$previousFeatures = $env:VK_LAYER_ENABLES
$modes = @('default')
if ($Validation) { $modes += 'validation' }
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
            11='a press was lost, repeated or invented'; 12='a stall was chased, or time was paid out wrongly' }
        $frames = [int]$state.frames
        Assert-True ($frames -eq 200 -and [int]$state.events -eq $frames -and [int]$state.ticks -eq 2 * $frames) 'The motion proof did not run its script'
        if (-not ('Myhits.Curves' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot '04_motion\curves.cs') }
        $worst = ([Myhits.Curves]::Compare((Resolve-Path -LiteralPath (Join-Path $BuildDir 'myhits_motion.curves.bin')).Path, [int]$state.samples)) -split ' '
        Assert-True ([double]$worst[0] -lt 1e-4) "The device's $($worst[1]) is $($worst[0]) from the textbook's at sample $($worst[2])"
        Write-Host ("[myhits] $mode/04 motion: {0} curves by {1} samples within {2} of a second implementation (worst: {3}); {4} ticks a second, 2 a scripted frame; {5} kinds in {6} moves; the missile's three moves end where they say; {7} fired, {8} missed, {9} flying; the level stood still for 40 frames and came {10}; {11} passes and {12} draws a frame" -f `
            $state.curves, $state.samples, $worst[0], $worst[1], $state.tick_rate, ([int]$state.kinds - 1), $state.moves, $state.fired, $state.escaped, $state.flying, $state.scroll,
            ([int]$state.dispatches / $frames), ([int]$state.draws / $frames))
    }
} finally {
    $env:VK_INSTANCE_LAYERS = $previousLayers
    $env:VK_LAYER_VALIDATE_SYNC = $previousSync
    $env:VK_LAYER_ENABLES = $previousFeatures
}
Write-Host '[myhits] Proofs passed.'
