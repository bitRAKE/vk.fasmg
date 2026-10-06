<# Check the explorer under each build contract and each route a switch can
   take away.

     - the float-pair shader keeps every add, subtract and multiply as written;
     - an executable holds the Vulkan functions its contract allows and none
       it excludes, imports neither vulkan-1.dll nor GDI;
     - the route and alternate blocks pair up under contracts no source ships:
       each capability required alone, each permitted alone, all and none;
     - real window messages drive zoom, pan, palette, reset, both mouse
       buttons, the wheel, deep zoom, a tour that is stopped and taken up
       again, and three resizes, each exported at full size;
     - every route, contract and tile size exports the same pixels;
     - a whole tour reaches every stop and ends on the first view, with
       float64 and with float pairs;
     - a contract the device cannot meet, a bad option and a missing driver
       end with an explicit error.

   -Validation repeats the runs with Khronos core and synchronization
   validation and rejects any diagnostic.
#>
param([Parameter(Mandatory = $true)] [string]$Fasm2, [string]$BuildDir = 'build', [switch]$Validation)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
foreach ($fixture in @('capture-debug-output.cs','inspect-legacy-images.cs')) {
    $type = if ($fixture -eq 'capture-debug-output.cs') { 'VkFasmgTests.DebugOutputCapture' } else { 'VkFasmgTests.FractalImage' }
    if (-not ($type -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot $fixture) }
}
function Assert-True($condition, [string]$message) {
    if (-not $condition) { throw $message }
}
function Read-State([string]$path) {
    $state = @{}
    foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::Unicode)) {
        if ($line -match '^(\w+)=(.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    return $state
}
# Run a failing start and return what the debugger saw of it.
function Read-Failure([string]$executable, [string]$arguments) {
    try { [void][VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot, $arguments) } catch { return $_.Exception.InnerException.Message }
    throw "Expected a failing start: $executable $arguments"
}

# The error-free transformations are only that while no operation is fused or reordered.
$code = (& (Join-Path $env:VULKAN_SDK 'Bin\spirv-dis.exe') (Join-Path $BuildDir 'legacy_fractal32x2.spv') | Out-String)
Assert-True ($LASTEXITCODE -eq 0) 'Could not inspect the float-pair shader'
$exact = [regex]::Matches($code, 'OpDecorate (%\S+) NoContraction') | ForEach-Object { $_.Groups[1].Value }
$arithmetic = [regex]::Matches($code, '(?m)^\s*(%\S+) = Op(?:FAdd|FSub|FMul|VectorTimesScalar|FNegate)\b') | ForEach-Object { $_.Groups[1].Value }
Assert-True ($arithmetic.Count -ge 30 -and -not ($arithmetic | Where-Object { $_ -notin $exact })) 'The float-pair shader has arithmetic a compiler may contract'
Assert-True ($code -notmatch 'OpCapability Float64') 'The float-pair shader asks for the feature it replaces'
Write-Host "[legacy] float-pair shader: $($arithmetic.Count) operations, all NoContraction, no Float64 capability"

# What each contract assembled, read from the slots its link map names.
$modern = @('vkCmdBeginRendering','vkCmdEndRendering','vkCmdPipelineBarrier2','vkQueueSubmit2','vkCmdCopyImageToBuffer2','vkWaitSemaphores',
    'vkGetSemaphoreCounterValue','vkGetPhysicalDeviceFeatures2','vkGetPhysicalDeviceProperties2','vkGetPhysicalDeviceMemoryProperties2')
$original = @('vkCreateRenderPass','vkDestroyRenderPass','vkCreateFramebuffer','vkDestroyFramebuffer','vkCmdBeginRenderPass','vkCmdEndRenderPass',
    'vkCmdPipelineBarrier','vkQueueSubmit','vkCmdCopyImageToBuffer','vkCreateShaderModule','vkDestroyShaderModule')
$contracts = @(
    @{ Tag='adaptive'; Has=$modern + $original; Lacks=@() },
    @{ Tag='compatibility'; Has=$original; Lacks=$modern },
    @{ Tag='modern'; Has=$modern; Lacks=$original }
)
$rows = foreach ($contract in $contracts) {
    $executable = Join-Path $BuildDir "legacy_$($contract.Tag).exe"
    $imports = (& dumpbin.exe /NOLOGO /IMPORTS $executable | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "Could not inspect imports: $executable"
    Assert-True ($imports -notmatch '(?i)\bvulkan-1\.dll\b') "A hard Vulkan import prevents a clean missing-runtime error: $executable"
    Assert-True ($imports -notmatch '(?i)\bgdi32\.dll\b') "Presentation must be Vulkan's: $executable"
    $slots = @(Get-Content -LiteralPath ([IO.Path]::ChangeExtension($executable, 'map')) | ForEach-Object { if ($_ -match '^\s*\d{4}:[0-9a-f]{8}\s+__imp_(vk\w+)\s') { $Matches[1] } })
    $absent = @($contract.Has | Where-Object { $_ -notin $slots })
    $present = @($contract.Lacks | Where-Object { $_ -in $slots })
    Assert-True (-not $absent) "$($contract.Tag) lacks $($absent -join ', ')"
    Assert-True (-not $present) "$($contract.Tag) assembled what its contract excludes: $($present -join ', ')"
    [pscustomobject]@{ Contract=$contract.Tag; 'Vulkan functions'=$slots.Count; 'Modern'=@($modern | Where-Object { $_ -in $slots }).Count
        'Original'=@($original | Where-Object { $_ -in $slots }).Count; 'Exe bytes'=(Get-Item -LiteralPath $executable).Length }
}
$rows | Format-Table -AutoSize | Out-String -Width 120 | Write-Host

# A block that leans on its counterpart's code or data fails to assemble once the counterpart is gone.
$mixes = @(@(63,1),@(63,2),@(63,4),@(63,8),@(63,16),@(63,32),@(33,0),@(34,0),@(36,0),@(40,0),@(48,0),@(0,0),@(63,63))
foreach ($mix in $mixes) {
    $source = Join-Path $BuildDir "legacy_mix_$($mix[0])_$($mix[1]).asm"
    [IO.File]::WriteAllLines($source, @("CONTRACT_NAME equ 'Mix'", "CONTRACT_TAG equ 'mix'", "CAP_MASK = $($mix[0])", "CAP_REQUIRED = $($mix[1])", 'TILE_CEILING = 16384', "include 'examples\legacy\explorer.inc'"))
    $output = (& (Join-Path $PSScriptRoot '..\tools\assemble.ps1') -Fasm2 $Fasm2 -Source $source -Output ([IO.Path]::ChangeExtension($source, 'obj')) 6>&1 | Out-String)
    Assert-True ($output -match 'passes') "CAP_MASK=$($mix[0]) CAP_REQUIRED=$($mix[1]) did not assemble"
}
Write-Host "[legacy] $($mixes.Count) further contracts assemble: each capability required alone, each permitted alone, all, none"

$previousLayers = $env:VK_INSTANCE_LAYERS
$previousDriver = $env:VK_DRIVER_FILES
$previousFeatures = $env:VK_LAYER_ENABLES
$previousSync = $env:VK_LAYER_VALIDATE_SYNC
$modes = @('default')
if ($Validation) { $modes += 'validation' }
$cases = @(
    @{ Name='adaptive'; Tag='adaptive'; Args=''; Mask=63 },
    @{ Name='compatibility'; Tag='compatibility'; Args=''; Mask=32 },
    @{ Name='modern'; Tag='modern'; Args=''; Mask=63; Required=31 },
    @{ Name='renderpass'; Tag='adaptive'; Args='--no-rendering'; Mask=62 },
    @{ Name='submit1-timeline'; Tag='adaptive'; Args='--no-sync2'; Mask=61 },
    @{ Name='submit2-fence'; Tag='adaptive'; Args='--no-timeline'; Mask=47 },
    @{ Name='copy1-modules'; Tag='adaptive'; Args='--no-copy2 --no-inline'; Mask=51 },
    @{ Name='khr'; Tag='adaptive'; Args='--force-khr'; Mask=63 },
    @{ Name='modern-khr'; Tag='modern'; Args='--force-khr'; Mask=63; Required=31 },
    @{ Name='api12'; Tag='adaptive'; Args='--api-1.2'; Mask=55 },
    @{ Name='api11'; Tag='adaptive'; Args='--api-1.1'; Mask=48 },
    @{ Name='float-pairs'; Tag='adaptive'; Args='--no-float64'; Mask=31 },
    @{ Name='tiles'; Tag='adaptive'; Args='--tile-limit=100'; Mask=63 },
    @{ Name='present-fallback'; Tag='adaptive'; Args='--no-present-fences'; Mask=63 }
)
$shapes = [ordered]@{ base=@(800,560); zoom=@(800,560); pan=@(800,560); palette=@(800,560); reset=@(800,560); in=@(800,560); out=@(800,560)
    wheel=@(800,560); deep=@(800,560); tour=@(800,560); arrival=@(800,560); wide=@(1200,500); short=@(640,320); narrow=@(360,640) }
try {
    foreach ($mode in $modes) {
        $env:VK_INSTANCE_LAYERS = $previousLayers
        $env:VK_LAYER_ENABLES = $previousFeatures
        $env:VK_LAYER_VALIDATE_SYNC = $previousSync
        $env:VK_DRIVER_FILES = $previousDriver
        if ($mode -eq 'validation') {
            $env:VK_INSTANCE_LAYERS = 'VK_LAYER_KHRONOS_validation'
            if ($previousLayers) { $env:VK_INSTANCE_LAYERS += ';' + $previousLayers }
            $env:VK_LAYER_ENABLES = $null
            $env:VK_LAYER_VALIDATE_SYNC = '1'
        }
        $reference = $null
        $doubles = $null
        $frames = $null
        foreach ($case in $cases) {
            $logRoot = Join-Path $BuildDir "legacy_checks\$mode\$($case.Name)"
            New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
            $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir "legacy_$($case.Tag).exe")).Path
            $report = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot, ('--self-test ' + $case.Args))
            [IO.File]::WriteAllText((Join-Path $logRoot 'debugger.log'), $report)
            Assert-True ($report -notmatch 'VUID-|SYNC-HAZARD') "$($case.Name) emitted a validation diagnostic"
            Assert-True ($report.Contains('[legacy] exit: app_io=0 validation=0 debug_io=0')) "$($case.Name): missing successful shutdown"
            if ($mode -eq 'validation') {
                Assert-True ($report.Contains('VK_LAYER_KHRONOS_validation') -and $report.Contains('- Synchronization')) 'Core/sync validation was not enabled'
            }
            $state = Read-State (Join-Path $BuildDir "legacy_$($case.Tag).report.txt")
            Copy-Item -LiteralPath (Join-Path $BuildDir "legacy_$($case.Tag).report.txt") -Destination $logRoot
            $caps = [int]$state.caps
            Assert-True ([int]$state.gpu_error -eq 0 -and [int]$state.failure_stage -eq 0) "$($case.Name): a GPU failure was hidden"
            # Every message that changes the picture presents once; the tour's steps are the same in every case.
            if ($null -eq $frames) { $frames = [int]$state.frames }
            Assert-True ($frames -gt 40 -and [int]$state.frames -eq $frames -and [int]$state.presents -eq $frames) "$($case.Name): $($state.frames) frames and $($state.presents) presentations where $frames were due"
            Assert-True ([int]$state.wheel_iterations -eq 240 -and [int]$state.iterations -eq 192) "$($case.Name): the wheel or reset left the wrong iteration count"
            Assert-True ([int]$state.idle_frames -eq 0) "$($case.Name): the tour went on after Esc"
            Assert-True ([int]$state.tour_at -eq 0 -and [int]$state.tour_next -eq 1 -and [int]$state.tour_state -eq 0) "$($case.Name): the tour did not reach its first stop, or outlived a key that moved the view"
            Assert-True ([int]$state.exports -eq $shapes.Count) "$($case.Name): not every step was exported"
            Assert-True (($caps -band (-bnot $case.Mask)) -eq 0) "$($case.Name): a masked route was selected"
            Assert-True (([int]$state.extensions -band (-bnot $caps)) -eq 0) "$($case.Name): an unselected extension route was enabled"
            $required = if ($case.Required) { $case.Required } else { 0 }
            Assert-True ([int]$state.required -eq $required -and ($caps -band $required) -eq $required) "$($case.Name): the contract was not met"
            Assert-True ([int]$state.deep_precision -eq $(if ($caps -band 32) { 2 } else { 3 }) -and [int]$state.precision -eq 1) "$($case.Name): the wrong arithmetic was chosen"
            if ($case.Name -like '*khr') { Assert-True ([int]$state.extensions -eq ($caps -band 31)) "$($case.Name): a core route was used for a promoted command" }
            if ($case.Name -eq 'api12') { Assert-True ([int]$state.api -eq 4202496) 'The API ceiling was ignored' }
            if ($case.Name -eq 'api11') { Assert-True ([int]$state.api -eq 4198400 -and [int]$state.extensions -eq 16) 'Vulkan 1.1 did not take the timeline extension alone' }
            if ($case.Tag -eq 'compatibility' -or $case.Name -eq 'present-fallback') { Assert-True ([int]$state.present_fences -eq 0) "$($case.Name): the present-fence fallback was ignored" }
            # The last export is the narrow one.
            $tile = [int]$state.tile
            $expected = [Math]::Ceiling(360 / [Math]::Min(360, $tile)) * [Math]::Ceiling(640 / [Math]::Min(640, $tile))
            Assert-True ([int]$state.tiles -eq $expected) "$($case.Name): $($state.tiles) tiles where $expected cover the picture"
            if ($case.Name -eq 'tiles') { Assert-True ($tile -eq 100) 'The tile limit was ignored' }
            if ($case.Tag -eq 'compatibility') { Assert-True ($tile -eq 128) 'The compatibility ceiling was ignored' }

            $images = @{}
            foreach ($shape in $shapes.GetEnumerator()) {
                $path = Join-Path $BuildDir "legacy_$($case.Tag).$($shape.Key).bmp"
                Copy-Item -LiteralPath $path -Destination $logRoot
                $image = New-Object VkFasmgTests.FractalImage $path
                Assert-True ($image.Width -eq $shape.Value[0] -and $image.Height -eq $shape.Value[1]) "$($case.Name)/$($shape.Key): export is not the client area"
                Assert-True ($image.Colors -gt 16) "$($case.Name)/$($shape.Key): the picture is blank or incomplete"
                $images[$shape.Key] = $image
            }
            foreach ($pair in @(@('base','zoom'),@('zoom','pan'),@('pan','palette'),@('base','in'),@('base','deep'),@('base','tour'),@('tour','arrival'))) {
                Assert-True ($images[$pair[0]].DifferentPixels($images[$pair[1]]) -gt 1000) "$($case.Name): no change from $($pair -join ' to ')"
            }
            # A quarter more iterations moves only pixels at the set's edge.
            Assert-True ($images.base.DifferentPixels($images.wheel) -gt 20) "$($case.Name): the wheel did not change the picture"
            Assert-True ($images.base.DifferentPixels($images.reset) -eq 0) "$($case.Name): reset did not restore the first picture"
            Assert-True ($images.base.DifferentPixels($images.out) -eq 0) "$($case.Name): a right click did not undo the left click at the same point"
            # One picture, whatever drew it: routes, contracts and tile sizes agree to the pixel.
            if ($null -eq $reference) { $reference = $images }
            foreach ($key in $shapes.Keys) {
                if ($key -eq 'deep') { continue }
                Assert-True ($reference[$key].DifferentPixels($images[$key]) -eq 0) "$($case.Name)/$key differs from $($cases[0].Name)"
            }
            if ($caps -band 32) {
                if ($null -eq $doubles) { $doubles = $images.deep }
                Assert-True ($doubles.DifferentPixels($images.deep) -eq 0) "$($case.Name): the float64 deep view differs between routes"
                $deep = 'float64'
            } elseif ($null -ne $doubles) {
                # Two floats carry 48 bits to a double's 53; counts may differ where an orbit barely escapes.
                $different = $doubles.DifferentPixels($images.deep)
                Assert-True ($different -lt $images.deep.Width * $images.deep.Height * 0.005) "Float pairs disagree with float64 in $different pixels"
                $deep = "float32 pairs ($different px from float64)"
            } else { $deep = 'float32 pairs' }
            Write-Host "[legacy] $mode/$($case.Name): caps=$caps KHR=$($state.extensions) tiles=$($state.tiles) deep=$deep; controls, resizes and exports agree"
        }

        # The whole tour, once with each arithmetic for its one deep stop.
        $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'legacy_adaptive.exe')).Path
        $tours = @{}
        foreach ($arithmetic in @('float64','pairs')) {
            $logRoot = Join-Path $BuildDir "legacy_checks\$mode\tour-$arithmetic"
            New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
            $report = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot, ('--tour-test' + $(if ($arithmetic -eq 'pairs') { ' --no-float64' })))
            [IO.File]::WriteAllText((Join-Path $logRoot 'debugger.log'), $report)
            Assert-True ($report -notmatch 'VUID-|SYNC-HAZARD') "The $arithmetic tour emitted a validation diagnostic"
            Assert-True ($report.Contains('[legacy] exit: app_io=0 validation=0 debug_io=0')) "The $arithmetic tour did not shut down cleanly"
            $state = Read-State (Join-Path $BuildDir 'legacy_adaptive.report.txt')
            $stops = [int]$state.tour_stops
            Assert-True ($stops -ge 2 -and [int]$state.exports -eq $stops -and [int]$state.tour_at -eq $stops - 1 -and [int]$state.tour_next -eq 0 -and [int]$state.tour_state -eq 0) "The $arithmetic tour did not end at its last stop"
            Assert-True ([int]$state.gpu_error -eq 0 -and [int]$state.presents -eq [int]$state.frames) "The $arithmetic tour hid a GPU failure"
            $tours[$arithmetic] = @(0..($stops - 1) | ForEach-Object {
                $path = Join-Path $BuildDir "legacy_adaptive.stop$_.bmp"
                Copy-Item -LiteralPath $path -Destination $logRoot
                $image = New-Object VkFasmgTests.FractalImage $path
                Assert-True ($image.Colors -gt 16) "Tour stop $_ is blank"
                $image })
            for ($stop = 1; $stop -lt $stops; $stop++) {
                Assert-True ($tours[$arithmetic][$stop - 1].DifferentPixels($tours[$arithmetic][$stop]) -gt 1000) "Tour stops $($stop - 1) and $stop show the same place"
            }
            Assert-True ($tours[$arithmetic][$stops - 1].DifferentPixels($reference.base) -eq 0) "The $arithmetic tour did not end on the first view"
        }
        $deepStops = 0
        for ($stop = 0; $stop -lt $tours.float64.Count; $stop++) {
            $different = $tours.float64[$stop].DifferentPixels($tours.pairs[$stop])
            if ($different) { $deepStops++; Assert-True ($different -lt 800 * 560 * 0.005) "Tour stop $stop differs between float64 and float pairs in $different pixels" }
        }
        Assert-True ($deepStops -le 1) 'More than the one deep stop depends on the arithmetic'
        Write-Host "[legacy] $mode/tour: $($tours.float64.Count) stops reached and the first view regained, with float64 and with float pairs"

        $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'legacy_modern.exe')).Path
        $failure = Read-Failure $executable '--self-test --no-sync2'
        Assert-True ($failure.Contains('Debuggee exited with 1:') -and $failure.Contains('missing=2)') -and $failure.Contains('[legacy] exit: app_io=1 validation=0 debug_io=0')) 'An unmet contract did not end with its explicit error'
        Assert-True ($failure -notmatch 'VUID-|SYNC-HAZARD') 'Unmet-contract cleanup caused a validation error'
        Write-Host "[legacy] $mode/unmet-contract: the modern build names the route it is missing"
        $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'legacy_adaptive.exe')).Path
        foreach ($option in @('--tile-limit=8','--tile-limit=','--tile-limit=1x')) {
            $failure = Read-Failure $executable "--self-test $option"
            Assert-True ($failure.Contains('Debuggee exited with 1:') -and $failure.Contains('invalid option') -and $failure.Contains('[legacy] exit: app_io=1 validation=0 debug_io=0')) "An invalid option was accepted: $option"
        }
        Write-Host "[legacy] $mode/options: malformed and undersized tile limits rejected"
        $env:VK_DRIVER_FILES = Join-Path $repoRoot 'build\intentionally-absent-legacy-driver.json'
        Assert-True (-not (Test-Path -LiteralPath $env:VK_DRIVER_FILES)) 'Missing-driver fixture exists'
        foreach ($tag in @('adaptive','compatibility','modern')) {
            $failure = Read-Failure (Resolve-Path -LiteralPath (Join-Path $BuildDir "legacy_$tag.exe")).Path '--self-test'
            Assert-True ($failure.Contains('Debuggee exited with 1:') -and $failure.Contains('Vulkan initialization or rendering failed') -and $failure.Contains('[legacy] exit: app_io=1 validation=0 debug_io=0')) "$tag did not report a missing driver"
            Assert-True ($failure -notmatch 'VUID-|SYNC-HAZARD') 'Missing-driver cleanup caused a validation error'
        }
        Write-Host "[legacy] $mode/no-driver: explicit Vulkan-unavailable error from every contract"
    }
} finally {
    $env:VK_INSTANCE_LAYERS = $previousLayers
    $env:VK_DRIVER_FILES = $previousDriver
    $env:VK_LAYER_ENABLES = $previousFeatures
    $env:VK_LAYER_VALIDATE_SYNC = $previousSync
}
Write-Host '[legacy] Contracts, routes, controls, resizes, exports and failure reports passed.'
