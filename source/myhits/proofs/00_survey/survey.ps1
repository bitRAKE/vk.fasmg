<# Proof 00, the survey: what this machine offers that the plan leans on.
   Nothing is built; this reads the system. Run it through the build so the
   Visual Studio tools are on PATH:

       build.cmd myhits-survey

   -Clang names a clang built with the SPIR-V target, to repeat the test of
   whether it accepts the pointer style:

       powershell -File source\myhits\proofs\00_survey\survey.ps1 -Clang C:\git\llvm-project\build-native\bin\clang.exe
#>
param([string]$Clang = '')
# Native tools write to stderr freely; that is not failure here.
$ErrorActionPreference = 'Continue'

# 1. Each GPU against the contract and the features the shaders use.
$info = Join-Path $env:VULKAN_SDK 'Bin\vulkaninfoSDK.exe'
if (-not (Test-Path -LiteralPath $info)) { $info = 'vulkaninfo.exe' }
$text = @(& $info 2>&1 | ForEach-Object { "$_" })
$starts = @(for ($i = 0; $i -lt $text.Count; $i++) { if ($text[$i] -match '^GPU\d+:') { $i } }) + $text.Count
$wanted = [ordered]@{
    'dynamicRendering' = 'contract'; 'synchronization2' = 'contract'; 'timelineSemaphore' = 'contract'; 'maintenance5' = 'contract: inline shader code'
    'bufferDeviceAddress' = 'contract: every resource is a pointer'; 'scalarBlockLayout' = 'contract: the layout shared.inc promises'
    'fragmentStoresAndAtomics' = 'the spine counts its pixels'; 'shaderInt64' = 'not needed; masks are 32-bit rows'
    'shaderDrawParameters' = 'not needed with SV_Vulkan* indices'; 'descriptorHeap' = 'not needed: no descriptors'
}
for ($g = 0; $g -lt $starts.Count - 1; $g++) {
    $block = $text[$starts[$g]..($starts[$g + 1] - 1)]
    $name = (($block | Select-String 'deviceName\s+=\s+(.+)$' | Select-Object -First 1).Matches.Groups[1].Value).Trim()
    $api = (($block | Select-String 'apiVersion\s+=\s+(\S+)' | Select-Object -First 1).Matches.Groups[1].Value)
    Write-Host "[survey] $name, Vulkan $api"
    foreach ($feature in $wanted.Keys) {
        $line = $block | Select-String "^\s*$feature\s+=\s+(\w+)" | Select-Object -First 1
        $value = if ($line) { $line.Matches.Groups[1].Value } else { 'absent' }
        Write-Host ("    {0,-26} {1,-7} {2}" -f $feature, $value, $wanted[$feature])
    }
    $push = ($block | Select-String 'maxPushConstantsSize\s+=\s+(\d+)' | Select-Object -First 1).Matches.Groups[1].Value
    Write-Host ("    {0,-26} {1,-7} {2}" -f 'maxPushConstantsSize', $push, 'Root must fit in 128, the guaranteed size')
}

# 2. The system libraries for sound and gamepads.
if (Get-Command dumpbin.exe -ErrorAction SilentlyContinue) {
    foreach ($library in @(@('xaudio2_9.dll', 'XAudio2Create'), @('xinput1_4.dll', 'XInputGetState'), @('xinput1_4.dll', 'XInputSetState'))) {
        $exports = (& dumpbin.exe /NOLOGO /EXPORTS (Join-Path $env:WINDIR "System32\$($library[0])") | Out-String)
        Write-Host ("[survey] {0} exports {1}: {2}" -f $library[0], $library[1], ($exports -match "\b$($library[1])\b"))
    }
} else { Write-Host '[survey] dumpbin is not on PATH: run through build.cmd to check the audio and gamepad libraries' }

# 3. The shader compiler the build uses, and whether another clang could stand in.
$slang = Join-Path $env:VULKAN_SDK 'Bin\slangc.exe'
Write-Host "[survey] slangc: $((& $slang -v 2>&1 | Select-Object -First 1))"
if ($Clang) {
    $scratch = Join-Path $env:TEMP 'myhits-survey'
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $cases = [ordered]@{
        'plain HLSL' = "RWStructuredBuffer<uint> counters : register(u0);`n[numthreads(64, 1, 1)]`nvoid main(uint3 id : SV_DispatchThreadID) { counters[id.x] = id.x * 2; }`n"
        'the pointer style' = "struct Game { uint score; uint damage[16]; };`nstruct Root { Game* game; float time; };`n[[vk::push_constant]] ConstantBuffer<Root> root;`n[numthreads(64, 1, 1)]`nvoid main(uint3 id : SV_DispatchThreadID) { InterlockedAdd(root.game.damage[id.x & 15], 1); }`n"
    }
    foreach ($case in $cases.Keys) {
        $source = Join-Path $scratch 'case.hlsl'; $output = Join-Path $scratch 'case.spv'
        [IO.File]::WriteAllText($source, $cases[$case])
        if (Test-Path -LiteralPath $output) { [IO.File]::Delete($output) }
        $arguments = @('--driver-mode=dxc', '-T', 'cs_6_6', '-E', 'main', '-spirv', '-fspv-target-env=vulkan1.3', "-Fo$output", $source)
        $errors = @(& $Clang @arguments 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match 'error' })
        Write-Host ("[survey] clang, {0}: {1}" -f $case, $(if (Test-Path -LiteralPath $output) { 'compiles to SPIR-V' } else { ($errors | Select-Object -First 1) -replace '^.*error: ', '' }))
    }
    [IO.Directory]::Delete($scratch, $true)
}
