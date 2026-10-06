<#
    Exercise the generated vk\ include tree and its loaders:

      - no function is listed by two files;
      - the whole projection assembles as one unit with its layout asserts and
        the assembler's alignment check on, without a warning: no definition
        is emitted twice, no struct lacks its file, no member is misaligned;
      - the lazy trampoline delivers every argument register and asks the
        right resolver, against a stand-in for Vulkan;
      - the loader examples, one program built under each loader, run and
        are bound the way their loader says: by the import table, by the
        linker's delay-load thunks, by lazy slots, by both, and in two objects
        through a loader object or through COMDAT, where the slots must lie
        side by side as one table;
      - the delay-load example, linked against a library that does not exist,
        starts and fails at its first Vulkan call instead of not starting.

    tools/assemble.ps1 requires fresh output even when fasm2.cmd masks an
    assembler failure, and rejects warnings.
#>
param(
    [Parameter(Mandatory = $true)] [string]$Fasm2,
    [Parameter(Mandatory = $true)] [string]$LoaderExamples,
    [string]$BuildDir = 'build'
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

function Invoke-Assembler([string]$source, [string]$name) {
    $object = Join-Path $BuildDir "$name.obj"
    & "$PSScriptRoot\..\tools\assemble.ps1" -Fasm2 $Fasm2 -Source $source -Output $object
    return $object
}
function Invoke-Linker([string]$name, [string[]]$inputs) {
    $executable = Join-Path $BuildDir "$name.exe"
    $text = (& link.exe /NOLOGO /SUBSYSTEM:CONSOLE /ENTRY:mainCRTStartup /NODEFAULTLIB /OPT:REF /OPT:ICF "/OUT:$executable" @inputs kernel32.lib 2>&1 | Out-String)
    if ($LASTEXITCODE -or $text.Trim()) { throw "link complained about ${executable}:`n$text" }
    return $executable
}
# The Vulkan functions an executable asks Windows to bind before it starts.
function Get-VulkanImports([string]$executable) {
    $names = @()
    foreach ($line in (& dumpbin.exe /NOLOGO /IMPORTS:vulkan-1.dll $executable)) {
        if ($line -match '^\s+[0-9A-Fa-f]+\s+(vk\w+)\s*$') { $names += $Matches[1] }
    }
    return ,$names
}
# The Vulkan functions the linker gave delay-load slots and thunks.
function Get-DelayedImports([string]$executable) {
    $names = @()
    foreach ($line in (& dumpbin.exe /NOLOGO /IMPORTS $executable)) {
        if ($line -match '^\s+[0-9A-Fa-f]{16}\s+[0-9A-Fa-f]+\s+(vk\w+)\s*$') { $names += $Matches[1] }
    }
    return ,$names
}
# The slots an executable defines itself, by name, with their offsets.
function Get-Slots([string]$executable) {
    $slots = @{}
    foreach ($line in (Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($executable, 'map')))) {
        if ($line -match '^\s*\d{4}:([0-9a-f]{8})\s+__imp_(vk\w+)\s+[0-9a-f]{16}\s+\S+\.obj\s*$') { $slots[$Matches[2]] = [Convert]::ToInt32($Matches[1], 16) }
    }
    return $slots
}
function Assert-DenseTable($slots, [string]$what) {
    if (-not $slots.Count) { throw "$what defines no slot" }
    $extent = ($slots.Values | Measure-Object -Maximum).Maximum - ($slots.Values | Measure-Object -Minimum).Minimum + 8
    if ($extent -ne 8 * $slots.Count) { throw "$what spreads $($slots.Count) slots over $extent bytes" }
}

$owners = @{}
$files = @(Get-Item -LiteralPath 'vk\core.inc') + @(Get-ChildItem -LiteralPath 'vk' -Directory | Where-Object { $_.Name -ne 'loader' } | Get-ChildItem -Filter '*.inc' -File)
foreach ($file in $files) {
    foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
        if ($line -notmatch '^define loader_functions_\w+\t(.+)$') { continue }
        foreach ($function in ($Matches[1] -split ',')) {
            if ($owners.ContainsKey($function)) { throw "$function is listed by $($owners[$function]) and $($file.Name)" }
            $owners[$function] = $file.Name
        }
    }
}
Write-Host "[vk] $($owners.Count) functions, each listed by one of $($files.Count) files"

[void](Invoke-Assembler 'tests\vk\everything.asm' 'vk_everything')
$asserts = @(Get-Content -LiteralPath 'tests\vk\layout_asserts.inc' | Where-Object { $_ -like 'assert *' }).Count
Write-Host "[vk] every file and $asserts layout asserts assembled as one unit, alignment check on and silent"

$probe = Invoke-Assembler 'tests\vk\lazy_probe.asm' 'vk_lazy_probe'
$fake = Invoke-Assembler 'tests\vk\lazy_fake.asm' 'vk_lazy_fake'
& (Invoke-Linker 'vk_lazy_probe' @($probe, $fake))
if ($LASTEXITCODE) { throw "the lazy trampoline probe failed at check $LASTEXITCODE" }
Write-Host "[vk] lazy trampoline: arguments intact, resolvers and handles as expected, one resolution per slot"

$extension = 'vkCreateDebugUtilsMessengerEXT'
foreach ($executable in $LoaderExamples.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($executable) -replace '^loader_',''
    $report = (& $executable | Out-String)
    if ($LASTEXITCODE) { throw "$executable failed at step $LASTEXITCODE`n$report" }
    $imports = Get-VulkanImports $executable
    $slots = Get-Slots $executable
    switch ($name) {
        'iat' {
            if ($slots.Count -or $imports -notcontains 'vkDestroySurfaceKHR' -or $imports -contains $extension) { throw "iat: $($slots.Count) slots, imports $($imports -join ', ')" }
            Write-Host "[vk] loader example iat ran: $($imports.Count) imports, an exported extension's among them, no slot of its own"
        }
        'delay' {
            $delayed = Get-DelayedImports $executable
            if ($imports.Count -or $slots.Count -or $delayed -notcontains $extension) { throw "delay: imports $($imports -join ', '); $($slots.Count) slots; delayed $($delayed -join ', ')" }
            Write-Host "[vk] loader example delay ran: no import, $($delayed.Count) delay-loaded functions, an unexported extension's among them"

            # The same objects against an import library for a file that is not there.
            $definition = Join-Path $BuildDir 'vulkan-absent.def'
            $library = Join-Path $BuildDir 'vulkan-absent.lib'
            [System.IO.File]::WriteAllLines($definition, @((Get-Content -LiteralPath 'vk\vulkan-1.def') -replace '^LIBRARY .*$', 'LIBRARY vulkan-absent.dll'))
            $text = (& lib.exe /NOLOGO "/DEF:$definition" /MACHINE:X64 "/OUT:$library" 2>&1 | Out-String)
            if ($LASTEXITCODE) { throw "lib rejected ${definition}:`n$text" }
            $absent = Join-Path $BuildDir 'vk_delay_absent.exe'
            $text = (& link.exe /NOLOGO /SUBSYSTEM:CONSOLE /ENTRY:mainCRTStartup /NODEFAULTLIB /OPT:REF /OPT:ICF "/OUT:$absent" (Join-Path $BuildDir 'loader_delay.obj') (Join-Path $BuildDir 'vk_delay.obj') (Join-Path $BuildDir 'loader_console.obj') $library kernel32.lib /DELAYLOAD:vulkan-absent.dll 2>&1 | Out-String)
            if ($LASTEXITCODE -or $text.Trim()) { throw "link complained about ${absent}:`n$text" }
            [void](& $absent | Out-String)
            if ($LASTEXITCODE -ne 1) { throw "without its library the delay-load example exited with $LASTEXITCODE, not with step 1" }
            Write-Host "[vk] loader example delay without its library: started, and vkCreateInstance failed the ordinary way"
        }
        'mixed' {
            if ($imports -notcontains 'vkCreateDevice' -or $imports -contains $extension -or -not $slots.ContainsKey($extension) -or $slots.ContainsKey('vkCreateDevice')) {
                throw "mixed: slots $($slots.Keys -join ', '); imports $($imports -join ', ')"
            }
            Assert-DenseTable $slots $name
            Write-Host "[vk] loader example mixed ran: $($imports.Count) imports for core and surface, $($slots.Count) lazy slots for debug_utils"
        }
        default {
            if (($imports -join ',') -ne 'vkGetInstanceProcAddr') { throw "${name}: imports $($imports -join ', ')" }
            if (-not $slots.ContainsKey($extension) -or -not $slots.ContainsKey('vkDeviceWaitIdle')) { throw "${name}: slots $($slots.Keys -join ', ')" }
            Assert-DenseTable $slots $name
            Write-Host "[vk] loader example $name ran: vkGetInstanceProcAddr the only import, $($slots.Count) slots in $(8 * $slots.Count) bytes"
        }
    }
}
