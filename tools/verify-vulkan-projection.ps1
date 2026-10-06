<#
    Verify the generated fasmg ABI projection against the installed Vulkan SDK
    by asking clang to lay out the same records for the Windows x64 MSVC ABI.
    Bit-fields are compared by absolute bit position.  Numeric constants
    visible through the core, Win32 and video SDK headers are also compiled as
    C static assertions.
#>
[CmdletBinding()]
param(
    [string]$Clang = "$env:ProgramFiles\LLVM\bin\clang.exe",
    [string]$Include = "$env:VULKAN_SDK\Include",
    [string]$LayoutManifest = 'tests\vk\layouts.txt',
    [string]$ConstantManifest = 'tests\vk\constants.txt',
    [string]$BuildDir = 'build\api_validation'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Clang -PathType Leaf)) { throw "LLVM clang not found: $Clang" }
if (-not (Test-Path -LiteralPath (Join-Path $Include 'vulkan\vulkan.h') -PathType Leaf)) { throw "Vulkan SDK headers not found below: $Include" }
if (-not (Test-Path -LiteralPath $LayoutManifest -PathType Leaf)) { throw "Layout manifest not found: $LayoutManifest" }
if (-not (Test-Path -LiteralPath $ConstantManifest -PathType Leaf)) { throw "Constant manifest not found: $ConstantManifest" }
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$videoHeaders = @(Get-ChildItem -LiteralPath (Join-Path $Include 'vk_video') -Filter '*.h' -File | Sort-Object Name)
$headers = @(
    (Join-Path $Include 'vulkan\vulkan_core.h'),
    (Join-Path $Include 'vulkan\vulkan_win32.h')
) + @($videoHeaders | ForEach-Object { $_.FullName })
$prelude = [System.Text.StringBuilder]::new()
[void]$prelude.AppendLine('#define VK_USE_PLATFORM_WIN32_KHR 1')
[void]$prelude.AppendLine('#define VK_ENABLE_BETA_EXTENSIONS 1')
[void]$prelude.AppendLine('#include <windows.h>')
[void]$prelude.AppendLine('#include <vulkan/vulkan.h>')
foreach ($header in $videoHeaders) { [void]$prelude.AppendLine("#include <vk_video/$($header.Name)>") }

$recordNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($header in $headers) {
    foreach ($line in (Get-Content -LiteralPath $header)) {
        if ($line -match '^\}\s+((?:Vk|StdVideo)\w+);') { [void]$recordNames.Add($Matches[1]) }
    }
}

$layoutSource = Join-Path $BuildDir 'layouts.c'
$source = [System.Text.StringBuilder]::new($prelude.ToString())
foreach ($name in @($recordNames | Sort-Object)) { [void]$source.AppendLine("char probe_$name[sizeof($name)];") }
[System.IO.File]::WriteAllText($layoutSource, $source.ToString(), [System.Text.Encoding]::ASCII)

$clangArguments = @(
    '-Xclang', '-fdump-record-layouts',
    '-fsyntax-only',
    '--target=x86_64-pc-windows-msvc',
    '-DVK_USE_PLATFORM_WIN32_KHR',
    '-DVK_ENABLE_BETA_EXTENSIONS',
    '-I', $Include,
    $layoutSource
)
$layoutDump = Join-Path $BuildDir 'clang-layouts.txt'
$clangText = (& $Clang @clangArguments 2>&1 | Out-String)
[System.IO.File]::WriteAllText($layoutDump, $clangText, [System.Text.Encoding]::ASCII)
if ($LASTEXITCODE) { throw "clang could not compile the Vulkan layout probe; see $layoutDump" }

$reference = @{}
$current = $null
foreach ($line in ($clangText -split "\r?\n")) {
    if ($line -match '^\s*0 \| (?:struct|union) ((?:Vk|StdVideo)\w+)\s*$') {
        $current = @{ Name = $Matches[1]; Members = @{}; Bitfields = @{}; Size = -1; Align = -1 }
        $reference[$current.Name] = $current
        continue
    }
    if ($null -eq $current) { continue }
    if ($line -match '\[sizeof=(\d+), align=(\d+)\]') {
        $current.Size = [int]$Matches[1]
        $current.Align = [int]$Matches[2]
        $current = $null
        continue
    }
    if ($line -match '^\s*(\d+) \|   (\S.*)$') {
        $offset = [int]$Matches[1]
        $declaration = $Matches[2]
        $token = ($declaration -split '\s+')[-1]
        if ($token -match '^\w+$') { $current.Members[$token] = $offset }
        continue
    }
    # byte:first-last, the bit range counted from that byte.
    if ($line -match '^\s*(\d+):(\d+)-(\d+) \|   (\S.*)$') {
        $bit = [int]$Matches[1] * 8 + [int]$Matches[2]
        $width = [int]$Matches[3] - [int]$Matches[2] + 1
        $token = ($Matches[4] -split '\s+')[-1]
        if ($token -match '^\w+$') { $current.Bitfields[$token] = "$bit|$width" }
    }
}

$projected = @{}
foreach ($line in (Get-Content -LiteralPath $LayoutManifest)) {
    $parts = $line -split '\|'
    if ($parts[0] -in @('struct','union')) {
        $projected[$parts[1]] = @{ Size = [int]$parts[2]; Align = [int]$parts[3]; Members = @{}; Bitfields = @{}; Union = ($parts[0] -eq 'union') }
    } elseif ($parts[0] -eq 'member' -and $projected.ContainsKey($parts[1])) {
        $projected[$parts[1]].Members[$parts[2]] = [int]$parts[3]
    } elseif ($parts[0] -eq 'bitfield' -and $projected.ContainsKey($parts[1])) {
        $projected[$parts[1]].Bitfields[$parts[2]] = "$($parts[3])|$($parts[4])"
    }
}

$layoutMismatches = [System.Collections.Generic.List[string]]::new()
$matchedLayouts = 0
$matchedBitfields = 0
$withoutClangRecord = 0
foreach ($name in @($projected.Keys | Sort-Object)) {
    if (-not $reference.ContainsKey($name)) { $withoutClangRecord++; continue }
    $expected = $reference[$name]
    $actual = $projected[$name]
    $differences = [System.Collections.Generic.List[string]]::new()
    if ($actual.Size -ne $expected.Size) { $differences.Add("sizeof $($actual.Size), SDK $($expected.Size)") }
    if ($actual.Align -ne $expected.Align) { $differences.Add("align $($actual.Align), SDK $($expected.Align)") }
    if (-not $actual.Union) {
        foreach ($member in $expected.Members.Keys) {
            if (-not $actual.Members.ContainsKey($member)) { $differences.Add("missing member $member"); continue }
            if ($actual.Members[$member] -ne $expected.Members[$member]) {
                $differences.Add("$member at $($actual.Members[$member]), SDK $($expected.Members[$member])")
            }
        }
        foreach ($field in $expected.Bitfields.Keys) {
            if (-not $actual.Bitfields.ContainsKey($field)) { $differences.Add("missing bit-field $field"); continue }
            if ($actual.Bitfields[$field] -ne $expected.Bitfields[$field]) {
                $differences.Add("$field bit|width $($actual.Bitfields[$field]), SDK $($expected.Bitfields[$field])")
            } else { $matchedBitfields++ }
        }
    }
    if ($differences.Count) { $layoutMismatches.Add($name + ': ' + ($differences -join '; ')) }
    else { $matchedLayouts++ }
}

# The registry manifest records fasmg's shift operator; spell it as C.
$headerConstantNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($header in $headers) {
    $headerText = [System.IO.File]::ReadAllText($header)
    foreach ($match in [regex]::Matches($headerText, '\b(?:VK|STD_VIDEO)_[A-Z0-9_]+\b')) { [void]$headerConstantNames.Add($match.Value) }
}
$verifiableConstants = [ordered]@{}
foreach ($line in (Get-Content -LiteralPath $ConstantManifest)) {
    $parts = $line -split '\|',4
    if ($parts.Count -ne 4 -or $parts[0] -ne 'constant' -or -not $headerConstantNames.Contains($parts[2])) { continue }
    $verifiableConstants[$parts[2]] = $parts[3]
}
$constantSource = Join-Path $BuildDir 'constants.c'
$source = [System.Text.StringBuilder]::new($prelude.ToString())
foreach ($entry in $verifiableConstants.GetEnumerator()) {
    $expression = $entry.Value -replace '(\d+)\s+shl\s+(\d+)', '($1ULL << $2)'
    if ($expression -match '\.') {
        [void]$source.AppendLine(('_Static_assert(({0}) == ({1}), "{2}");' -f $entry.Key,$expression,$entry.Key))
    } else {
        [void]$source.AppendLine(('_Static_assert(((long long)({0})) == ((long long)({1})), "{2}");' -f $entry.Key,$expression,$entry.Key))
    }
}
[System.IO.File]::WriteAllText($constantSource, $source.ToString(), [System.Text.Encoding]::ASCII)
$constantLog = Join-Path $BuildDir 'clang-constants.txt'
$constantText = (& $Clang -fsyntax-only --target=x86_64-pc-windows-msvc -DVK_USE_PLATFORM_WIN32_KHR -DVK_ENABLE_BETA_EXTENSIONS -I $Include $constantSource 2>&1 | Out-String)
[System.IO.File]::WriteAllText($constantLog, $constantText, [System.Text.Encoding]::ASCII)
if ($LASTEXITCODE) { throw "clang rejected generated constants; see $constantLog" }

Write-Host "[vk] LLVM/SDK ABI verification"
Write-Host "[vk]   clang: $Clang"
Write-Host "[vk]   SDK:   $Include"
Write-Host "[vk]   layouts matched: $matchedLayouts ($matchedBitfields bit-fields); mismatched: $($layoutMismatches.Count); platform-gated/unprobed: $withoutClangRecord"
Write-Host "[vk]   core/Win32/video constants compiled: $($verifiableConstants.Count)"
if ($layoutMismatches.Count) {
    foreach ($difference in @($layoutMismatches | Select-Object -First 30)) { Write-Host "[vk]   diff: $difference" }
    if ($layoutMismatches.Count -gt 30) { Write-Host "[vk]   ... and $($layoutMismatches.Count - 30) more" }
    throw "LLVM/SDK layout verification failed for $($layoutMismatches.Count) records"
}
