param([string]$BuildDir = 'build', [switch]$Validation)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
if (-not ('VkFasmgTests.DebugOutputCapture' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'capture-debug-output.cs') }
if (-not ('VkFasmgTests.CubeImage' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'inspect-cube-images.cs') }
if ($Validation) {
    if (-not ('VkFasmgTests.RangeAllocator' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'verify-range-allocator.cs') }
    Write-Host ([VkFasmgTests.RangeAllocator]::Check((Join-Path $repoRoot "$BuildDir\vk_ranges_test.dll")))
}
function Assert-True($condition, [string]$message) { if (-not $condition) { throw $message } }
function Read-State([string]$path) {
    $state = @{}
    foreach ($line in [IO.File]::ReadAllLines($path,[Text.Encoding]::Unicode)) {
        if ($line -match '^(\w+)=(.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    return $state
}
# Inspect compiler output as well as rendered images: the native heap route may
# not run on the local adapter, but it must preserve the same root byte layout.
$spirvDis = Join-Path $env:VULKAN_SDK 'Bin\spirv-dis.exe'
function Read-Spirv([string]$module) {
    $code = (& $spirvDis (Join-Path $BuildDir "noAPI_cube_$module.spv") | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "Could not inspect $module shader"
    return $code
}
foreach($module in @('bindings','pointer','heap_vertex')) {
    $code = Read-Spirv $module
    $root = [regex]::Match($code,'OpMemberName (%\S+) 0 "vertices"')
    Assert-True $root.Success "Missing vertex-address root member in $module"
    $rootId = [regex]::Escape($root.Groups[1].Value)
    Assert-True ($code -match "OpMemberName $rootId 1 `"transform`"") "Missing root transform in $module"
    Assert-True ($code -match "OpMemberDecorate $rootId 0 Offset 0\b" -and
                 $code -match "OpMemberDecorate $rootId 1 Offset 8\b") "Root offsets changed in $module"
    Assert-True ([regex]::Matches($code,"OpMemberDecorate $rootId \d+ Offset").Count -eq 2) "Root has extra members in $module"
    $members = [regex]::Match($code,"(?m)^\s*$rootId = OpTypeStruct %\S+ (%\S+)\s*$")
    Assert-True $members.Success "Root must have exactly two fields in $module"
    $transformId = [regex]::Escape($members.Groups[1].Value)
    if($module -eq 'heap_vertex') {
        Assert-True ($code -match "OpMemberDecorate $rootId 1 MatrixStride 16\b") 'Native matrix stride changed'
        $matrix = [regex]::Match($code,"$transformId = OpTypeMatrix (%\S+) 4\b")
        Assert-True $matrix.Success 'Native transform must have four vectors'
        $vectorId = [regex]::Escape($matrix.Groups[1].Value)
        $vector = [regex]::Match($code,"$vectorId = OpTypeVector (%\S+) 4\b")
        Assert-True $vector.Success 'Native transform vectors must have four components'
        $floatId = [regex]::Escape($vector.Groups[1].Value)
    } else {
        Assert-True ($code -match "OpDecorate $transformId ArrayStride 4\b") "Scalar matrix stride changed in $module"
        $array = [regex]::Match($code,"$transformId = OpTypeArray (%\S+) (%\S+)")
        Assert-True $array.Success "Missing scalar transform array in $module"
        $floatId = [regex]::Escape($array.Groups[1].Value)
        $lengthId = [regex]::Escape($array.Groups[2].Value)
        Assert-True ($code -match "$lengthId = OpConstant %\S+ 16\b") "Transform must have sixteen scalars in $module"
    }
    Assert-True ($code -match "$floatId = OpTypeFloat 32\b") "Transform must end at byte 72 in $module"
}
foreach($module in @('fragment','heap_fragment')) {
    $code = Read-Spirv $module
    Assert-True ($code -notmatch '\bPushConstant\b') "Format recovery enlarged the root in $module"
    Assert-True ($code -match 'OpDecorate %\S+ SpecId 0\b' -and
                 [regex]::Matches($code,'\bSpecId\b').Count -eq 1) "Format flags must use one specialization constant in $module"
}
Write-Host '[cube] shaders: original root offsets 0/8, format specialization outside root'
$executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'noAPI_cube.exe')).Path
$imports = (& dumpbin.exe /NOLOGO /IMPORTS $executable | Out-String)
Assert-True ($LASTEXITCODE -eq 0 -and $imports -notmatch '(?i)\bvulkan-1\.dll\b') 'Hard Vulkan import prevents a clean missing-runtime error'
Assert-True ($imports -notmatch '(?i)\bgdi32\.dll\b|StretchDIBits') 'Cube presentation must use Vulkan WSI'
$originalLayers = $env:VK_INSTANCE_LAYERS
$originalDriver = $env:VK_DRIVER_FILES
$originalSync = $env:VK_LAYER_VALIDATE_SYNC
$originalFeatures = $env:VK_LAYER_ENABLES
$modes = @('default')
if ($Validation) { $modes += 'validation' }
$cases = @(
    @{Name='adaptive';Args='';Mask=479},
    @{Name='sets';Args='--no-heap';Mask=351},
    @{Name='bindings';Args='--no-address';Mask=31},
    @{Name='compatibility';Args='--compatibility';Mask=0},
    @{Name='renderpass';Args='--no-rendering';Mask=350},
    @{Name='submit1-timeline';Args='--no-sync2';Mask=221},
    @{Name='copy1-modules';Args='--no-copy2 --no-inline --no-address-commands';Mask=83},
    @{Name='submit2-fence';Args='--no-timeline';Mask=463},
    @{Name='buffer-commands';Args='--no-address-commands';Mask=223},
    @{Name='khr';Args='--force-khr';Mask=479},
    @{Name='api12';Args='--api-1.2';Mask=87},
    @{Name='api11';Args='--api-1.1';Mask=16},
    @{Name='depth16';Args='--depth16';Mask=479},
    @{Name='linear-formats';Args='--linear-formats';Mask=479},
    @{Name='ordinary-pages';Args='--no-large-pages';Mask=479},
    @{Name='page-fallback';Args='--large-pages';Mask=479;Restricted=$true},
    @{Name='heap-config';Args='--cpu-heap-mib=4 --buffer-pool-mib=2 --image-pool-mib=8';Mask=479},
    @{Name='small-pools';Args='--small-pools --noncoherent';Mask=479},
    @{Name='dedicated-memory';Args='--dedicated-memory --noncoherent';Mask=479},
    @{Name='present-fallback';Args='--no-present-fences';Mask=479}
)
$shapes = @(
    @{Tag='';Width=500;Height=500},@{Tag='rotated';Width=500;Height=500},
    @{Tag='paused';Width=500;Height=500},@{Tag='turned';Width=500;Height=500},
    @{Tag='reset';Width=500;Height=500},@{Tag='wide';Width=800;Height=480},
    @{Tag='short';Width=480;Height=320},@{Tag='narrow';Width=320;Height=640}
)
try {
    foreach($mode in $modes) {
        $env:VK_INSTANCE_LAYERS = $originalLayers
        $env:VK_LAYER_VALIDATE_SYNC = $originalSync
        $env:VK_LAYER_ENABLES = $originalFeatures
        if($mode -eq 'validation') {
            $env:VK_INSTANCE_LAYERS = 'VK_LAYER_KHRONOS_validation'
            if($originalLayers) { $env:VK_INSTANCE_LAYERS += ';' + $originalLayers }
            $env:VK_LAYER_VALIDATE_SYNC = '1'
            $env:VK_LAYER_ENABLES = $null
        }
        $reference = $null
        foreach($case in $cases) {
            $env:VK_DRIVER_FILES = $originalDriver
            $logRoot = Join-Path $BuildDir "cube_checks\$mode\$($case.Name)"
            New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
            $report = if($case.Restricted) {
                [VkFasmgTests.DebugOutputCapture]::RunWithoutLargePagesPrivilege($executable,$repoRoot,('--self-test ' + $case.Args))
            } else { [VkFasmgTests.DebugOutputCapture]::Run($executable,$repoRoot,('--self-test ' + $case.Args)) }
            [IO.File]::WriteAllText((Join-Path $logRoot 'debugger.log'),$report)
            Assert-True ($report -notmatch 'VUID-|SYNC-HAZARD') "$($case.Name) emitted a validation diagnostic"
            Assert-True ($report.Contains('[cube] exit: app_io=0 validation=0 debug_io=0')) 'Missing clean cube shutdown'
            $state = Read-State (Join-Path $BuildDir 'noAPI_cube.report.txt')
            Assert-True ([int]$state.frames -eq 17 -and [int]$state.paused -eq 1) 'Timer, pause, turn, reset, or resize did not execute'
            Assert-True ([int]$state.presents -eq [int]$state.frames -and [int]$state.readbacks -eq 8) 'Swapchain presentation or on-demand capture did not execute'
            Assert-True ([int]$state.gpu_error -eq 0 -and [int]$state.failure_stage -eq 0) 'A GPU failure was hidden'
            Assert-True ([int]$state.root_bytes -eq 72 -and [int]$state.material_flags -ge 0 -and [int]$state.material_flags -le 3) 'Root or material bitmask ABI changed'
            Assert-True ([long]$state.retirement -eq [long]$state.retired -and [int]$state.deletes_pending -eq 0 -and [int]$state.swapchains_pending -eq 0) 'Retirement did not reclaim completed resources'
            Assert-True ([int]$state.command_contexts -ge 2 -and [int]$state.command_contexts -le 8) 'Command context pool grew outside its bound'
            if($case.Name -eq 'ordinary-pages') { Assert-True ([int]$state.large_pages_requested -eq 0 -and [int]$state.large_pages -eq 0) 'Ordinary-page configuration was ignored' }
            if($case.Restricted) { Assert-True ([int]$state.large_pages -eq 0 -and [int]$state.large_pages_error -ne 0) 'Missing privilege did not select ordinary pages' }
            if($case.Name -eq 'heap-config') { Assert-True ([long]$state.cpu_arena_bytes -ge 4*1024*1024) 'Startup heap size was ignored' }
            if($case.Name -eq 'present-fallback' -or $case.Name -eq 'compatibility') { Assert-True ([int]$state.present_fences -eq 0) 'Presentation-fence fallback was ignored' }
            if($case.Name -eq 'dedicated-memory') { Assert-True ([int]$state.memory_reuses -eq 0) 'Dedicated-allocation fallback used pooled ranges' }
            else { Assert-True ([int]$state.memory_reuses -ge 1) 'Resize/export did not reuse GPU pool ranges' }
            if([int]$state.present_fences -eq 1) { Assert-True ([int]$state.swapchains_retired -ge 4 -and [int]$state.swapchains_retired -eq [int]$state.swapchains_reclaimed) 'Old swapchains did not retire through presentation fences' }
            Assert-True (([int]$state.caps -band (-bnot $case.Mask)) -eq 0) 'Masked or ineligible feature was enabled'
            Assert-True (([int]$state.extensions -band (-bnot [int]$state.caps)) -eq 0) 'Unselected extension route was enabled'
            if($case.Name -eq 'depth16') { Assert-True ([int]$state.depth -eq 124) 'D16 fallback was not selected' }
            if($case.Name -eq 'linear-formats') { Assert-True ([int]$state.texture -eq 37 -and [int]$state.target -eq 44 -and [int]$state.material_flags -eq 3) 'UNORM bitmask fallback was not selected' }
            if($mode -eq 'validation') {
                Assert-True ($report.Contains('VK_LAYER_KHRONOS_validation') -and $report.Contains('- Synchronization')) 'Core/sync validation was not enabled'
            }
            Copy-Item -LiteralPath (Join-Path $BuildDir 'noAPI_cube.report.txt') -Destination $logRoot
            foreach($shape in $shapes) {
                $suffix = if($shape.Tag) { '.' + $shape.Tag } else { '' }
                $path = Join-Path $BuildDir "noAPI_cube$suffix.bmp"
                [void][VkFasmgTests.CubeImage]::Check($path,$shape.Width,$shape.Height)
                Copy-Item -LiteralPath $path -Destination $logRoot
                if($reference) {
                    # Native heaps can produce small compiler/derivative differences;
                    # color conversion is permitted three 8-bit quantization steps.
                    $tolerance = if($case.Name -eq 'linear-formats') { 3 } else { 1 }
                    $different = [VkFasmgTests.CubeImage]::Compare((Join-Path $reference "noAPI_cube$suffix.bmp"),$path,$tolerance)
                    Assert-True ($different -le $shape.Width*$shape.Height/100) "Fallback changed the cube scene: $($case.Name)/$($shape.Tag), $different pixels"
                }
            }
            if(-not $reference) { $reference = $logRoot }
            Assert-True ([VkFasmgTests.CubeImage]::Compare((Join-Path $logRoot 'noAPI_cube.bmp'),(Join-Path $logRoot 'noAPI_cube.rotated.bmp'),0) -gt 10000) 'Cube did not spin'
            Assert-True ([VkFasmgTests.CubeImage]::Compare((Join-Path $logRoot 'noAPI_cube.rotated.bmp'),(Join-Path $logRoot 'noAPI_cube.paused.bmp'),0) -eq 0) 'Pause changed the image'
            Assert-True ([VkFasmgTests.CubeImage]::Compare((Join-Path $logRoot 'noAPI_cube.paused.bmp'),(Join-Path $logRoot 'noAPI_cube.turned.bmp'),0) -gt 1000) 'Manual turn did not work'
            Assert-True ([VkFasmgTests.CubeImage]::Compare((Join-Path $logRoot 'noAPI_cube.bmp'),(Join-Path $logRoot 'noAPI_cube.reset.bmp'),0) -eq 0) 'Reset did not restore the scene'
            Write-Host "[cube] $mode/$($case.Name): caps=$($state.caps) extensions=$($state.extensions), complete GPU scene"
        }
        foreach($allocatorArgs in @('','--no-sync2 --force-khr','--no-timeline','--noncoherent')) {
            $allocatorReport = [VkFasmgTests.DebugOutputCapture]::Run($executable,$repoRoot,('--allocator-test ' + $allocatorArgs))
            Assert-True ($allocatorReport -notmatch 'VUID-|SYNC-HAZARD' -and $allocatorReport.Contains('recycled=1 payload=ok')) 'GPU allocator lifetime or transfer payload failed'
            $allocatorState = Read-State (Join-Path $BuildDir 'noAPI_cube.report.txt')
            if(([int]$allocatorState.caps -band 16) -ne 0) { Assert-True ($allocatorReport.Contains('quarantine=1')) 'Timeline gating did not protect a pending allocation' }
            Write-Host "[cube] $mode/allocator $allocatorArgs : deferred range reuse and GPU payload passed"
        }
        foreach($presentCase in @(@{Name='adaptive';Args=''},@{Name='compatibility';Args='--compatibility'})) {
            $presentReport = [VkFasmgTests.DebugOutputCapture]::Run($executable,$repoRoot,('--present-test ' + $presentCase.Args))
            $presentRoot = Join-Path $BuildDir "cube_checks\$mode\present-$($presentCase.Name)"
            New-Item -ItemType Directory -Force -Path $presentRoot | Out-Null
            [IO.File]::WriteAllText((Join-Path $presentRoot 'debugger.log'),$presentReport)
            Assert-True ($presentReport -notmatch 'VUID-|SYNC-HAZARD') 'Presentation stress emitted a validation diagnostic'
            $state = Read-State (Join-Path $BuildDir 'noAPI_cube.report.txt')
            Assert-True ([int]$state.frames -ge 385 -and [int]$state.presents -eq [int]$state.frames -and [int]$state.readbacks -eq 0) 'Live presentation performed image readback or missed frames'
            foreach($size in @('width=500 height=500','width=1920 height=1080','width=3840 height=2160')) {
                Assert-True ($presentReport.Contains($size)) "Presentation stress did not render $size"
            }
            Assert-True ([regex]::Matches($presentReport,'\[cube present\].*memory_allocations=0\b').Count -eq 3) 'Steady rendering allocated GPU memory'
            Copy-Item -LiteralPath (Join-Path $BuildDir 'noAPI_cube.report.txt') -Destination $presentRoot
            Write-Host "[cube] $mode/present-$($presentCase.Name): $($state.presents) presentations through 4K, zero readbacks"
        }
        foreach($invalidOption in @('--cpu-heap-mib=1','--image-pool-mib=0','--buffer-pool-mib=1025','--cpu-heap-mib=4294967296','--image-pool-mib=1x','--buffer-pool-mib=','--buffer-pool-mib=-1')) {
            $failure = ''
            try { [void][VkFasmgTests.DebugOutputCapture]::Run($executable,$repoRoot,('--self-test ' + $invalidOption)) } catch { $failure = $_.Exception.InnerException.Message }
            Assert-True ($failure.Contains('Debuggee exited with 1:') -and $failure.Contains('invalid startup heap configuration') -and $failure.Contains('[cube] exit: app_io=1 validation=0 debug_io=0')) "Invalid heap option was accepted: $invalidOption"
            Assert-True ($failure -notmatch 'VUID-|SYNC-HAZARD') 'Invalid-configuration cleanup caused a validation error'
        }
        Write-Host "[cube] $mode/heap-options: invalid, out-of-range and overflowing sizes rejected"
        $env:VK_DRIVER_FILES = Join-Path $repoRoot 'build\intentionally-absent-cube-driver.json'
        Assert-True (-not (Test-Path -LiteralPath $env:VK_DRIVER_FILES)) 'Missing-driver fixture unexpectedly exists'
        $failure = ''
        try { [void][VkFasmgTests.DebugOutputCapture]::Run($executable,$repoRoot,'--self-test') } catch { $failure = $_.Exception.InnerException.Message }
        Assert-True ($failure.Contains('Debuggee exited with 1:') -and $failure.Contains('GPU initialization/rendering failed') -and $failure.Contains('[cube] exit: app_io=1 validation=0 debug_io=0')) 'Missing driver did not produce a clean GPU-only failure'
        Assert-True ($failure -notmatch 'VUID-|SYNC-HAZARD') 'Missing-driver cleanup caused a validation error'
        Write-Host "[cube] $mode/no-driver: explicit GPU unavailable error"
    }
} finally {
    $env:VK_INSTANCE_LAYERS = $originalLayers
    $env:VK_DRIVER_FILES = $originalDriver
    $env:VK_LAYER_VALIDATE_SYNC = $originalSync
    $env:VK_LAYER_ENABLES = $originalFeatures
}
Write-Host '[cube] Image fidelity, animation, controls, resizing, GPU routes, and unavailable-driver checks passed.'
