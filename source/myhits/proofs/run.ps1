<# Run the myhits proofs and hold each to what it claims. README.md beside this
   file says what every check settles; this script is the checks themselves.

     01 style   the shaders compile to valid SPIR-V in the pointer style, and
                the compiler lays the boundary blocks out as shared.inc says
     02 spine   the CPU-GPU boundary works end to end on the device

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

# 01: what the header promises is what the compiler did. Every member line of
# the generated header carries its offset; every module that uses a boundary
# block must decorate the same member with the same offset.
$promised = @{}
$block = $null
foreach ($line in [IO.File]::ReadAllLines((Join-Path $BuildDir 'myhits_shared.slang'))) {
    if ($line -match '^struct (\w+)') { $block = $Matches[1] }
    elseif ($line -match '^\s+\S+\s+(\w+)(?:\[\d+\])?;\s+// (\d+)$') { $promised["$block.$($Matches[1])"] = [int]$Matches[2] }
}
Assert-True ($promised['Root.world'] -eq 0 -and $promised.ContainsKey('Events.sound')) 'The generated header lists no boundary members'
$modules = @(Get-ChildItem -LiteralPath $BuildDir -Filter 'myhits_*.spv')
Assert-True ($modules.Count -ge 8) 'The proofs'' shaders were not built'
$checked = 0
foreach ($module in $modules) {
    $code = (& $spirvDis $module.FullName | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "Could not read $($module.Name)"
    # SV_VertexID and SV_InstanceID would bring this in, and a feature with it.
    Assert-True ($code -notmatch 'OpCapability DrawParameters') "$($module.Name) needs shaderDrawParameters"
    Assert-True ($code -match 'OpCapability PhysicalStorageBufferAddresses') "$($module.Name) does not reach memory through pointers"
    Assert-True ($code -notmatch 'OpTypeImage|OpTypeSampler|DescriptorSet') "$($module.Name) binds a descriptor"
    $names = @{}
    foreach ($match in [regex]::Matches($code, 'OpMemberName (%\S+) (\d+) "(\w+)"')) { $names["$($match.Groups[1].Value) $($match.Groups[2].Value)"] = $match.Groups[3].Value }
    foreach ($match in [regex]::Matches($code, 'OpMemberDecorate (%(Root|Events|Trigger)\w*) (\d+) Offset (\d+)')) {
        $member = "$($match.Groups[2].Value).$($names["$($match.Groups[1].Value) $($match.Groups[3].Value)"])"
        Assert-True ($promised.ContainsKey($member)) "$($module.Name) has $member, which shared.inc does not"
        Assert-True ($promised[$member] -eq [int]$match.Groups[4].Value) "$($module.Name) puts $member at $($match.Groups[4].Value), shared.inc at $($promised[$member])"
        $checked++
    }
}
$atomics = [regex]::Matches((& $spirvDis (Join-Path $BuildDir 'myhits_style_collide.spv') | Out-String), 'OpAtomicIAdd').Count
Assert-True ($atomics -ge 4) 'The collision sketch lost its atomics'
Write-Host "[myhits] 01 style: $($modules.Count) modules valid, pointer-only, no descriptors; $checked member offsets match shared.inc; $atomics atomics through pointers in the collision sketch"

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
        $logRoot = Join-Path $BuildDir "myhits_checks\$mode\spine"
        New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
        $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'myhits_spine.exe')).Path
        $imports = (& dumpbin.exe /NOLOGO /IMPORTS $executable | Out-String)
        Assert-True ($imports -notmatch '(?i)\bvulkan-1\.dll\b|\bgdi32\.dll\b') 'The spine imports Vulkan or GDI directly'
        $report = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot, '--self-test')
        [IO.File]::WriteAllText((Join-Path $logRoot 'debugger.log'), $report)
        Assert-True ($report -notmatch 'VUID-|SYNC-HAZARD') 'The spine emitted a validation diagnostic'
        Assert-True ($report.Contains('[myhits] exit: app_io=0 validation=0 debug_io=0')) 'The spine did not shut down cleanly'
        if ($mode -eq 'validation') {
            Assert-True ($report.Contains('VK_LAYER_KHRONOS_validation') -and $report.Contains('- Synchronization')) 'Core/sync validation was not enabled'
        }
        $state = Read-State (Join-Path $BuildDir 'myhits_spine.report.txt')
        Copy-Item -LiteralPath (Join-Path $BuildDir 'myhits_spine.report.txt') -Destination $logRoot
        $checks = @{ 1='events out of order'; 2='an atomic add to host-visible memory was lost'; 3='an atomic add to device-local memory was lost'
            4='the controls did not move the player in their own frame'; 5='the pulled draw shaded the wrong number of pixels'
            6='events were not in hand when the next frame began'; 7='a sound trigger''s pan is out of range'; 8='not every frame''s events were read'
            9='more or less than Root went down'; 10='more or less than Events came back'; 11='the frame is not two dispatches and one draw'
            12='a window of another shape did not keep the playfield''s' }
        $failure = [int]$state.failure
        Assert-True ($failure -eq 0) "Spine check $failure failed at frame $($state.failure_frame): $($checks[$failure])"
        $frames = [int]$state.frames
        Assert-True ($frames -eq 121 -and [int]$state.events -eq $frames) 'The spine did not run its script'
        Assert-True ([int]$state.view_width -eq 888 -and [int]$state.view_height -eq 500) 'The playfield did not keep 16:9 in a 1200 x 500 window'
        Assert-True ([int]$state.gpu_error -eq 0 -and [int]$state.failure_stage -eq 0) 'A device failure was hidden'
        Assert-True (([int]$state.caps -band [int]$state.required) -eq [int]$state.required) 'The contract was not met'
        Assert-True ([int]$state.root_bytes -le 128 -and [int]$state.events_bytes -eq 512) 'A boundary block outgrew its budget'
        Assert-True ([long]$state.bytes_down -eq $frames * [int]$state.root_bytes -and [long]$state.bytes_up -eq $frames * 512) 'The CPU traffic is not what the plan allows'
        Write-Host ("[myhits] $mode/02 spine: {0} frames; {1} bytes down and {2} up a frame; {3} dispatches and {4} draw a frame; atomics exact on {5} motes; controls land in their own frame; events {6} frame later; {7} pixels pulled; playfield {8} x {9} in a 1200 x 500 window" -f `
            $frames, $state.root_bytes, $state.events_bytes, ([int]$state.dispatches / $frames), ([int]$state.draws / $frames), $state.motes, $state.worst_latency, $state.shaded, $state.view_width, $state.view_height)
    }
} finally {
    $env:VK_INSTANCE_LAYERS = $previousLayers
    $env:VK_LAYER_VALIDATE_SYNC = $previousSync
    $env:VK_LAYER_ENABLES = $previousFeatures
}
Write-Host '[myhits] Proofs passed.'
