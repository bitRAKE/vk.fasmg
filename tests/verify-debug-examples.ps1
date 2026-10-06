<# Verify lifecycle ordering, severity routing, real debugger events, file
   output, object metadata, and coverage of all eleven debug-utils commands.
   -Validation repeats the checks with VK_LAYER_KHRONOS_validation enabled.
#>
param(
    [string]$BuildDir = 'build',
    [switch]$Validation
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
if (-not ('VkFasmgTests.DebugOutputCapture' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'capture-debug-output.cs')
}
function Assert-Contains([string]$report, [string]$text, [string]$what) {
    if (-not $report.Contains($text)) { throw "$what lacks '$text'" }
}
function Assert-Levels([string]$report, [string]$sink, [string[]]$expected) {
    $actual = @([regex]::Matches($report,
        "\[debug\]\[$sink\]\[levels\]\[(verbose|info|warning|error)\].*?message=demo\.(\w+):") |
        ForEach-Object { $_.Groups[2].Value })
    if (($actual -join ',') -ne ($expected -join ',')) {
        throw "$sink received [$($actual -join ',')], expected [$($expected -join ',')]"
    }
}
$previousLayers = $env:VK_INSTANCE_LAYERS
$modes = @('default')
if ($Validation) { $modes += 'validation' }
try {
    foreach ($mode in $modes) {
        $env:VK_INSTANCE_LAYERS = $previousLayers
        if ($mode -eq 'validation') {
            $env:VK_INSTANCE_LAYERS = 'VK_LAYER_KHRONOS_validation'
            if ($previousLayers) { $env:VK_INSTANCE_LAYERS += ';' + $previousLayers }
        }
        $logRoot = Join-Path $BuildDir "debug_checks\$mode"
        New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
        $reports = @{}
        foreach ($name in @('lifecycle','outputs','objects')) {
            $executable = Join-Path $BuildDir "debug_$name.exe"
            $report = (& $executable 2>&1 | Out-String)
            if ($LASTEXITCODE) { throw "$executable exited at step $LASTEXITCODE`n$report" }
            if ($report -match 'VUID-') { throw "$executable reported a validation diagnostic`n$report" }
            Assert-Contains $report "[debug] $($name):" $name
            [System.IO.File]::WriteAllText((Join-Path $logRoot "$name.stdout.log"), $report)
            $reports[$name] = $report
        }
        $position = 0
        foreach ($event in @('create instance: success','create messenger: success',
            'create device: success','create semaphore: success','destroy semaphore: begin',
            'destroy device: begin','destroy messenger: begin','vkDestroyInstance:',
            'lifecycle: PASS')) {
            $next = $reports.lifecycle.IndexOf($event, $position, [StringComparison]::Ordinal)
            if ($next -lt 0) { throw "Lifecycle event missing or out of order: $event" }
            $position = $next + $event.Length
        }
        if ($mode -eq 'validation') {
            Assert-Contains $reports.lifecycle 'VK_LAYER_KHRONOS_validation' 'Layer activation'
        }
        Assert-Levels $reports.outputs 'console' @('warning','error')
        $fileReport = [System.IO.File]::ReadAllText((Join-Path $BuildDir 'debug_outputs.log'))
        Assert-Levels $fileReport 'file' @('verbose','info','warning','error')
        $unicodeSample = 'caf' + [char]0xE9 + ' ' + [char]0x3BB
        Assert-Contains $fileReport $unicodeSample 'UTF-8 file output'
        [System.IO.File]::WriteAllText((Join-Path $logRoot 'outputs.file.log'), $fileReport)

        $executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'debug_outputs.exe')).Path
        $debugReport = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot)
        Assert-Levels $debugReport 'debugger' @('info','warning','error')
        Assert-Contains $debugReport $unicodeSample 'Unicode debugger output'
        [System.IO.File]::WriteAllText((Join-Path $logRoot 'outputs.debugger.log'), $debugReport)
        Assert-Levels ([System.IO.File]::ReadAllText((Join-Path $BuildDir 'debug_outputs.log'))) `
            'file' @('verbose','info','warning','error')

        foreach ($name in @('debug.device','debug.queue','debug.command_pool',
            'debug.commands','debug.buffer','debug.buffer.renamed')) {
            $pattern = 'handle=0x(?!0{16})[0-9A-F]{16} name=' + [regex]::Escape($name) + '(?:\r?\n|$)'
            if ($reports.objects -notmatch $pattern) { throw "Named live object missing: $name" }
        }
        foreach ($text in @('objects.tagged: buffer carries asset-id:42',
            'queue-label=debug.queue.work','command-label=debug.commands.outer',
            'command-label=debug.commands.inner','objects.cleared: buffer name removed with NULL',
            'object type=0x0000000000000009')) {
            Assert-Contains $reports.objects $text 'Object/label metadata'
        }
        if ($reports.objects -notmatch 'object type=0x0000000000000009 handle=0x[0-9A-F]{16} name=\(none\)') {
            throw 'Cleared buffer name missing from callback metadata'
        }
        Write-Host "[debug] $mode passed: lifecycle, console/file severity masks, real Unicode debugger events, names/tags/labels"
    }
} finally {
    $env:VK_INSTANCE_LAYERS = $previousLayers
}
$maps = (@('lifecycle','outputs','objects') | ForEach-Object {
    [System.IO.File]::ReadAllText((Join-Path $BuildDir "debug_$_.map"))
}) -join [Environment]::NewLine
$commands = @()
foreach ($line in (Get-Content -LiteralPath 'vk\ext\debug_utils.inc')) {
    if ($line -match '^define loader_functions_\w+\s+(.+)$') { $commands += $Matches[1].Split(',') }
}
foreach ($command in $commands) {
    Assert-Contains $maps "__imp_$command" 'Debug-utils command coverage'
}
Write-Host "[debug] all $($commands.Count) VK_EXT_debug_utils commands present in the examples"
