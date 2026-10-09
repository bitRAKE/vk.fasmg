param(
    [Parameter(Mandatory = $true)] [string]$Fasm2,
    [string]$BuildDir = 'build'
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$object = Join-Path $BuildDir 'stack_probe.obj'
$executable = Join-Path $BuildDir 'stack_probe.exe'
& .\tools\assemble.ps1 -Fasm2 $Fasm2 -Source tests\stack-probe.asm -Output $object
& link.exe /NOLOGO /SUBSYSTEM:CONSOLE /ENTRY:mainCRTStartup /NODEFAULTLIB /OPT:REF /STACK:2097152,4096 "/OUT:$executable" $object kernel32.lib
if ($LASTEXITCODE) { throw 'Stack probe test link failed' }
# A one-page initial commitment forces both large frames to grow the stack.
& (Resolve-Path -LiteralPath $executable).Path
if ($LASTEXITCODE) { throw "Stack growth or local initialization failed: $LASTEXITCODE" }
$disassembly = (& dumpbin.exe /NOLOGO /DISASM $object | Out-String)
if ($LASTEXITCODE) { throw 'Stack probe disassembly failed' }
Set-Content -LiteralPath (Join-Path $BuildDir 'stack_probe.disasm.txt') -Value $disassembly
$bytes = [IO.File]::ReadAllBytes($object)
# NEWCOFF BigObj section names resolve through its COFF string table.
$sectionCount = [BitConverter]::ToUInt32($bytes,44)
$strings = [BitConverter]::ToUInt32($bytes,48) + 20*[BitConverter]::ToUInt32($bytes,52)
$sections = @{}
for ($i=0; $i -lt $sectionCount; $i++) {
    $offset = 56 + 40*$i
    $name = [Text.Encoding]::ASCII.GetString($bytes,$offset,8).Trim([char]0)
    if ($name.StartsWith('/')) {
        $start = $strings + [int]$name.Substring(1)
        $end = $start
        while ($bytes[$end]) { $end++ }
        $name = [Text.Encoding]::ASCII.GetString($bytes,$start,$end-$start)
    }
    $size = [BitConverter]::ToUInt32($bytes,$offset+16)
    $raw = [BitConverter]::ToUInt32($bytes,$offset+20)
    $sections[$name] = [BitConverter]::ToString($bytes,$raw,$size)
}
# The full 24-byte sequence checks the TEB load, page step/touch and loop.
$probe = '65-67-48-A1-10-00-00-00-EB-09-48-2D-00-10-00-00-80-38-00-48-39-C4-72-F2'
foreach ($test in @(@('.text$stack_small',0),@('.text$stack_large',1),@('.text$stack_explicit',1))) {
    $name = $test[0]
    if (-not $sections.ContainsKey($name)) { throw "Missing code section $name" }
    $probes = [regex]::Matches($sections[$name],[regex]::Escape($probe)).Count
    if ($probes -ne $test[1]) { throw "${name}: expected $($test[1]) probe, found $probes" }
}
Write-Host 'Stack probe: committed limit lowered for both 128 KiB automatic and 192 KiB explicit growth; argument registers and initialized locals intact; small frame has no probe.'
