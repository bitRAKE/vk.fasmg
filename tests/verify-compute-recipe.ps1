<# Check every GPU result, headless imports, core/synchronization validation,
   and an ordinary initialization error with no installed driver available. #>
param([string]$BuildDir = 'build', [switch]$Validation)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
$executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'recipe_compute.exe')).Path
. (Join-Path $PSScriptRoot 'verify-recipe-binary-layout.ps1')
Assert-RecipeBinaryLayout $executable '.bss$compute'
$logRoot = Join-Path $BuildDir 'compute_checks'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
if (-not ('VkFasmgTests.DebugOutputCapture' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'capture-debug-output.cs')
}
$imports = (& dumpbin.exe /NOLOGO /IMPORTS $executable | Out-String)
if ($LASTEXITCODE -or $imports -match '(?i)vulkan-1\.dll|gdi32\.dll') {
    throw "Compute must start without a Vulkan DLL import and have no GDI dependency: $imports"
}
$map = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($executable, 'map')) -Raw
if ($map -match '__imp_vk(?:Create.*Surface|CreateSwapchain|QueuePresent|CmdDraw|CmdBeginRender)') {
    throw 'Headless compute acquired a surface, presentation, or graphics dependency'
}
foreach ($function in @('vkCmdDispatch','vkCmdCopyBuffer','vkCmdPipelineBarrier','vkWaitForFences',
        'vkFlushMappedMemoryRanges','vkInvalidateMappedMemoryRanges')) {
    if (-not $map.Contains("__imp_$function")) { throw "Compute lacks $function" }
}
$previousLayers = $env:VK_INSTANCE_LAYERS
$previousSync = $env:VK_LAYER_VALIDATE_SYNC
$previousDrivers = $env:VK_DRIVER_FILES
try {
    $modes = @('default')
    if ($Validation) { $modes += 'validation' }
    foreach ($mode in $modes) {
        $env:VK_INSTANCE_LAYERS = $previousLayers
        $env:VK_LAYER_VALIDATE_SYNC = $previousSync
        if ($mode -eq 'validation') {
            $env:VK_INSTANCE_LAYERS = 'VK_LAYER_KHRONOS_validation'
            $env:VK_LAYER_VALIDATE_SYNC = '1'
        }
        $report = (& $executable | Out-String)
        $exitCode = $LASTEXITCODE
        [IO.File]::WriteAllText((Join-Path $logRoot "$mode.stdout.log"), $report)
        if ($exitCode -or -not $report.Contains('[compute] verified 1048576 sums: C[i] = A[i] + B[i]')) {
            throw "Compute $mode failed ($exitCode): $report"
        }
        if ($report -notmatch 'GPU upload \+ dispatch \+ readback: \d+ us|queue timestamps unavailable') {
            throw "Compute $mode omitted its timing status: $report"
        }
        $debug = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot)
        [IO.File]::WriteAllText((Join-Path $logRoot "$mode.debugger.log"), $debug)
        if ($debug -match 'VUID-|SYNC-HAZARD') { throw "Compute $mode validation diagnostic: $debug" }
        if ($mode -eq 'validation' -and $debug -notmatch 'VK_LAYER_KHRONOS_validation') {
            throw 'Compute validation run did not confirm layer activation'
        }
        Write-Host "[compute] ${mode}: every sum checked, complete resource cleanup, no validation warnings/errors"
    }
    $env:VK_INSTANCE_LAYERS = $null
    $env:VK_DRIVER_FILES = Join-Path $repoRoot 'build\compute-driver-does-not-exist.json'
    $report = (& $executable | Out-String)
    if ($LASTEXITCODE -ne 1 -or $report -notmatch '\[compute\] failed at step (3|5), result -\d+') {
        throw "Compute did not report an unavailable driver: $report"
    }
    [IO.File]::WriteAllText((Join-Path $logRoot 'no-driver.stdout.log'), $report)
    Write-Host '[compute] without a driver: started, reported initialization failure, exited normally'
} finally {
    $env:VK_INSTANCE_LAYERS = $previousLayers
    $env:VK_LAYER_VALIDATE_SYNC = $previousSync
    $env:VK_DRIVER_FILES = $previousDrivers
}
