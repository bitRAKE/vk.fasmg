<# Exercise real window commands and full-size exports on every renderer.
   Downgrade switches test routes independently; a missing ICD tests recovery.
   -Validation repeats GPU cases with Khronos and synchronization validation.
#>
param([string]$BuildDir = 'build', [switch]$Validation)
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
function Read-Image([string]$path, [bool]$opaque = $true) {
    $image = New-Object VkFasmgTests.FractalImage $path,$opaque
    if ($opaque) {
        Assert-True ($image.Width -gt 0 -and $image.Height -gt 0) "Wrong export dimensions: $path"
        Assert-True ($image.Colors -gt 16) "Fractal is blank or incomplete: $path"
    }
    return $image
}
function Read-State([string]$path) {
    $state = @{}
    foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::Unicode)) {
        if ($line -match '^(\w+)=(.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    return $state
}
# The missing-driver test exercises loader failure. Check the PE imports too:
# absent vulkan-1.dll must allow the executable to reach its CPU fallback.
foreach ($tag in @('adaptive','compatibility','software')) {
    $executable = Join-Path $BuildDir "legacy_$tag.exe"
    $imports = (& dumpbin.exe /NOLOGO /IMPORTS $executable | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) "Could not inspect imports: $executable"
    Assert-True ($imports -notmatch '(?i)\bvulkan-1\.dll\b') "Hard Vulkan import prevents software startup: $executable"
}
$previousLayers = $env:VK_INSTANCE_LAYERS
$previousDriver = $env:VK_DRIVER_FILES
$previousFeatures = $env:VK_LAYER_ENABLES
$previousSync = $env:VK_LAYER_VALIDATE_SYNC
$modes = @('default')
if ($Validation) { $modes += 'validation' }
$cases = @(
    @{ Name='adaptive'; Tag='adaptive'; Args=''; Mask=63 },
    @{ Name='compatibility'; Tag='compatibility'; Args=''; Mask=32 },
    @{ Name='software'; Tag='software'; Args=''; Mask=0 },
    @{ Name='submit1-timeline'; Tag='adaptive'; Args='--no-sync2'; Mask=61 },
    @{ Name='submit2-fence'; Tag='adaptive'; Args='--no-timeline'; Mask=47 },
    @{ Name='renderpass-modern'; Tag='adaptive'; Args='--no-rendering'; Mask=62 },
    @{ Name='copy1-modules'; Tag='adaptive'; Args='--no-copy2 --no-inline'; Mask=51 },
    @{ Name='khr'; Tag='adaptive'; Args='--force-khr'; Mask=63 },
    @{ Name='api12'; Tag='adaptive'; Args='--api-1.2'; Mask=55 },
    @{ Name='no-float64'; Tag='adaptive'; Args='--no-float64'; Mask=31 },
    @{ Name='no-driver'; Tag='adaptive'; Args=''; Mask=0 }
)
try {
    foreach ($mode in $modes) {
        $env:VK_INSTANCE_LAYERS = $previousLayers
        $env:VK_LAYER_ENABLES = $previousFeatures
        $env:VK_LAYER_VALIDATE_SYNC = $previousSync
        if ($mode -eq 'validation') {
            $env:VK_INSTANCE_LAYERS = 'VK_LAYER_KHRONOS_validation'
            if ($previousLayers) { $env:VK_INSTANCE_LAYERS += ';' + $previousLayers }
            $env:VK_LAYER_ENABLES = $null
            $env:VK_LAYER_VALIDATE_SYNC = '1'
        }
        $reference = $null
        $cpuReference = $null
        $deepCpuReference = $null
        $deepGpuReference = $null
        foreach ($case in $cases) {
            $env:VK_DRIVER_FILES = $previousDriver
            if ($case.Name -eq 'no-driver') {
                $env:VK_DRIVER_FILES = Join-Path $repoRoot 'build\intentionally-absent-legacy-driver.json'
                Assert-True (-not (Test-Path -LiteralPath $env:VK_DRIVER_FILES)) 'Missing-driver fixture exists'
            }
            $logRoot = Join-Path $BuildDir "legacy_checks\$mode\$($case.Name)"
            New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
            $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir "legacy_$($case.Tag).exe")).Path
            $report = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot, ('--self-test ' + $case.Args))
            [IO.File]::WriteAllText((Join-Path $logRoot 'debugger.log'), $report)
            Assert-True ($report -notmatch 'VUID-|SYNC-HAZARD') "$($case.Name) emitted a validation diagnostic"
            Assert-True ($report.Contains('[legacy] exit: app_io=0 validation=0 debug_io=0')) 'Missing successful shutdown'
            $state = Read-State (Join-Path $BuildDir "legacy_$($case.Tag).report.txt")
            Copy-Item -LiteralPath (Join-Path $BuildDir "legacy_$($case.Tag).report.txt") -Destination $logRoot
            Assert-True ([int]$state.frames -eq 15) 'Not all GUI commands and resizes rendered'
            $expectedDeep = if ([int]$state.backend -eq 1 -and ([int]$state.caps -band 32)) { 2 } else { 0 }
            Assert-True ([int]$state.deep_backend -eq $expectedDeep -and [int]$state.cpu_backend -eq 0) 'Native FP64 or manual CPU alternate was not selected'
            Assert-True ([int]$state.gpu_error -eq 0) 'GPU operation failed and hid behind software fallback'
            Assert-True (([int]$state.caps -band (-bnot $case.Mask)) -eq 0) 'A masked capability was enabled'
            Assert-True (([int]$state.extensions -band (-bnot [int]$state.caps)) -eq 0) 'Disabled extension route was requested'
            if ($case.Name -in @('software','no-driver')) {
                Assert-True ([int]$state.backend -eq 0) 'Required software path was not used'
            } elseif ($null -ne $reference) {
                Assert-True ([int]$state.backend -eq 1) 'A working Vulkan path unexpectedly fell back to software'
            }
            if ([int]$state.backend -eq 1) {
                $tiles = [Math]::Ceiling([int]$state.width / [double]$state.tile) * [Math]::Ceiling([int]$state.height / [double]$state.tile)
                Assert-True ([int]$state.tiles -eq $tiles) 'GPU did not render every tile'
                if ($mode -eq 'validation') {
                    Assert-True ($report.Contains('VK_LAYER_KHRONOS_validation')) 'Validation layer did not activate'
                    Assert-True ($report.Contains('- Synchronization')) 'Synchronization validation did not activate'
                }
                if ($case.Name -eq 'khr') { Assert-True ([int]$state.extensions -eq ([int]$state.caps -band 31)) 'KHR switch used a core route for a promoted command' }
                if ($case.Name -eq 'api12') { Assert-True ([int]$state.api -eq 4202496) 'API ceiling was ignored' }
            }
            $images = @{}
            foreach ($suffix in @('','zoom','pan','changed','reset','deep','deep.cpu','deep.gui','cpu','gui')) {
                $tail = if ($suffix) { ".$suffix.bmp" } else { '.bmp' }
                $path = Join-Path $BuildDir "legacy_$($case.Tag)$tail"
                Copy-Item -LiteralPath $path -Destination $logRoot
                $images[$suffix] = Read-Image $path (-not $suffix.EndsWith('gui'))
            }
            Assert-True ($images[''].Width -eq [int]$state.width -and $images[''].Height -eq [int]$state.height) 'Export did not follow the render area'
            foreach ($size in @('','wide','short','narrow')) {
                $prefix = if ($size) { ".$size" } else { '' }
                $basePath = Join-Path $BuildDir "legacy_$($case.Tag)$prefix"
                $layout = Read-State "$basePath.layout.txt"
                Copy-Item -LiteralPath "$basePath.layout.txt" -Destination $logRoot
                $render = Read-Image "$basePath.bmp"
                $gui = Read-Image "$basePath.gui.bmp" $false
                $gui.CheckLayout($render,[int]$layout.canvas_top,[int]$layout.footer_top,[int]$layout.footer_bottom)
                if ($size) {
                    Copy-Item -LiteralPath "$basePath.bmp","$basePath.gui.bmp" -Destination $logRoot
                    Assert-True ($render.Width -ne $images[''].Width -or $render.Height -ne $images[''].Height) 'Resize kept the original image dimensions'
                } else {
                    $images['deep.gui'].CheckLayout($images.deep,[int]$layout.canvas_top,[int]$layout.footer_top,[int]$layout.footer_bottom)
                }
            }
            foreach ($pair in @(@('','zoom'),@('zoom','pan'),@('pan','changed'),@('','deep'))) {
                Assert-True ($images[$pair[0]].DifferentPixels($images[$pair[1]]) -gt 1000) "GUI action did not change the image: $($pair -join ' -> ')"
            }
            Assert-True ($images[''].DifferentPixels($images.reset) -eq 0) 'Reset did not restore the original image'
            if ($null -eq $cpuReference) { $cpuReference = $images.cpu }
            Assert-True ($cpuReference.DifferentPixels($images.cpu) -eq 0) 'CPU alternate changed between profiles'
            if ($null -eq $deepCpuReference) { $deepCpuReference = $images['deep.cpu'] }
            Assert-True ($deepCpuReference.DifferentPixels($images['deep.cpu']) -eq 0) 'CPU deep view changed between profiles'
            Assert-True ($images.deep.DifferentPixels($images['deep.cpu']) -lt $images.deep.Width * $images.deep.Height * 0.02) 'GPU double precision disagrees beyond escape boundary rounding'
            if ($expectedDeep -eq 2) {
                if ($null -eq $deepGpuReference) { $deepGpuReference = $images.deep }
                Assert-True ($deepGpuReference.DifferentPixels($images.deep) -eq 0) 'GPU FP64 output changed between fallback paths'
            }
            if ([int]$state.backend -eq 1) {
                if ($null -eq $reference) { $reference = $images }
                foreach ($suffix in @('','zoom','pan','changed','reset')) {
                    Assert-True ($reference[$suffix].DifferentPixels($images[$suffix]) -eq 0) "GPU fallback changed exported pixels: $($case.Name) / $suffix"
                }
                # Double and shader float arithmetic differ at escape boundaries.
                $different = $images[''].DifferentPixels($images.cpu)
                Assert-True ($different -lt $images[''].Width * $images[''].Height * 0.02) 'CPU and GPU disagree beyond fractal boundary rounding'
            }
            Write-Host "[legacy] $mode/$($case.Name): caps=$($state.caps) KHR=$($state.extensions) tiles=$($state.tiles) deep=$($state.deep_backend); resize/footer/export/precision checks passed"
        }
        if ($null -eq $reference) { Write-Host '[legacy] No usable GPU: application recovery verified; GPU equivalence cases require a Vulkan device.' }
    }
} finally {
    $env:VK_INSTANCE_LAYERS = $previousLayers
    $env:VK_DRIVER_FILES = $previousDriver
    $env:VK_LAYER_ENABLES = $previousFeatures
    $env:VK_LAYER_VALIDATE_SYNC = $previousSync
}
