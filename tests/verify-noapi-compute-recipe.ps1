<# Verify the physical-pointer ABI, fixed command/data model, GPU results,
   core/synchronization validation, and rejection of an unavailable contract. #>
param([string]$BuildDir = 'build', [switch]$Validation)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
$executable = (Resolve-Path -LiteralPath (Join-Path $BuildDir 'recipe_compute_noapi.exe')).Path
. (Join-Path $PSScriptRoot 'verify-recipe-binary-layout.ps1')
Assert-RecipeBinaryLayout $executable '.bss$noapi'
$logRoot = Join-Path (Split-Path -Parent $executable) 'noapi_compute_checks'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
if (-not ('VkFasmgTests.DebugOutputCapture' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'capture-debug-output.cs')
}

$imports = (& dumpbin.exe /NOLOGO /IMPORTS $executable | Out-String)
if ($LASTEXITCODE -or $imports -match '(?i)vulkan-1\.dll|gdi32\.dll') {
    throw "NoAPI compute must bootstrap Vulkan and run headless: $imports"
}
$map = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($executable, 'map')) -Raw
$required = @('vkGetBufferDeviceAddress', 'vkCreateComputePipelines', 'vkCreatePipelineLayout',
    'vkCmdPushConstants', 'vkCmdDispatch', 'vkCmdPipelineBarrier2', 'vkQueueSubmit2', 'vkWaitSemaphores')
foreach ($function in $required) {
    if (-not $map.Contains("__imp_$function")) { throw "NoAPI compute lacks $function" }
}
$forbidden = 'vk(?:CreateDescriptor\w*|AllocateDescriptorSets|UpdateDescriptorSets|CmdBindDescriptorSets|' +
    'CreateShaderModule|DestroyShaderModule|CreateFence|WaitForFences|ResetFences|' +
    'FlushMappedMemoryRanges|InvalidateMappedMemoryRanges|CmdCopy\w*|' +
    'Create\w*Surface\w*|CreateSwapchain\w*|QueuePresent\w*|CmdDraw\w*|CmdBeginRender\w*|' +
    'CmdPipelineBarrier|QueueSubmit)'
if ($map -match "__imp_$forbidden\s") { throw 'NoAPI recipe acquired another resource/command protocol' }

$spirvPath = Join-Path $BuildDir 'recipe_compute_noapi.spv'
$disassembly = (& "$env:VULKAN_SDK\Bin\spirv-dis.exe" $spirvPath | Out-String)
if ($LASTEXITCODE) { throw 'Could not disassemble the NoAPI shader' }
[IO.File]::WriteAllText((Join-Path $logRoot 'shader.spvasm'), $disassembly)
foreach ($pattern in @('OpCapability PhysicalStorageBufferAddresses',
    'OpMemoryModel PhysicalStorageBuffer64', 'OpExecutionMode %\w+ LocalSize 64 1 1',
    '%Root_natural = OpTypeStruct %_ptr_PhysicalStorageBuffer_Arguments_natural',
    '%Arguments_natural = OpTypeStruct (?:%_ptr_PhysicalStorageBuffer_uint ){3}%uint %uint',
    'OpMemberDecorate %Root_natural 0 Offset 0')) {
    if ($disassembly -notmatch $pattern) { throw "Shader pointer ABI changed: $pattern" }
}
foreach ($member in @(@(0,0), @(1,8), @(2,16), @(3,24), @(4,28))) {
    if ($disassembly -notmatch "OpMemberDecorate %Arguments_natural $($member[0]) Offset $($member[1])\b") {
        throw "Shader argument offset changed: $member"
    }
}
if ($disassembly -match 'OpDecorate[^\r\n]+(?:DescriptorSet|Binding)\b|OpCapability Int64\b') {
    throw 'Shader gained descriptor bindings or an unchecked Int64 feature requirement'
}
Write-Host '[noapi] shader: physical pointers, 8-byte root, 32-byte arguments, exact host/shader offsets'

function Assert-Results([string]$Report, [int]$ExitCode, [string]$Mode) {
    if ($ExitCode -or -not $Report.Contains('[noapi] verified 3 resident-pointer batches; 1 command recording, 3 submissions')) {
        throw "NoAPI $Mode failed ($ExitCode): $Report"
    }
    foreach ($batch in 1..3) {
        $expected = "[noapi] batch ${batch}: verified $(1048576-$batch) sums + $batch guarded tail elements; bias $($batch*1000)"
        if (-not $Report.Contains($expected)) { throw "NoAPI $Mode omitted result: $expected" }
    }
}
function Get-CallCount([string]$Trace, [string]$Function) {
    return [regex]::Matches($Trace, "(?m)^$Function\(").Count
}
function Write-Settings([string]$Text) {
    [IO.File]::WriteAllText((Join-Path $logRoot 'vk_layer_settings.txt'), $Text)
    $env:VK_LAYER_SETTINGS_PATH = $logRoot
}

$variables = @('VK_INSTANCE_LAYERS','VK_LAYER_VALIDATE_SYNC','VK_DRIVER_FILES','VK_LAYER_SETTINGS_PATH',
    'VK_APIDUMP_DETAILED','VK_APIDUMP_OUTPUT_FORMAT','VK_APIDUMP_LOG_FILENAME',
    'VK_LOADER_LAYERS_DISABLE','VK_LOADER_LAYERS_ALLOW','VK_LOADER_LAYERS_ENABLE')
$previous = @{}
foreach ($variable in $variables) { $previous[$variable] = [Environment]::GetEnvironmentVariable($variable) }
try {
    $modes = @('default')
    if ($Validation) { $modes += 'validation' }
    foreach ($mode in $modes) {
        $env:VK_INSTANCE_LAYERS = $previous['VK_INSTANCE_LAYERS']
        $env:VK_LAYER_VALIDATE_SYNC = $previous['VK_LAYER_VALIDATE_SYNC']
        if ($mode -eq 'validation') {
            $env:VK_INSTANCE_LAYERS = 'VK_LAYER_KHRONOS_validation'
            $env:VK_LAYER_VALIDATE_SYNC = '1'
        }
        $report = (& $executable | Out-String)
        $exitCode = $LASTEXITCODE
        [IO.File]::WriteAllText((Join-Path $logRoot "$mode.stdout.log"), $report)
        Assert-Results $report $exitCode $mode
        $debug = [VkFasmgTests.DebugOutputCapture]::Run($executable, $repoRoot)
        [IO.File]::WriteAllText((Join-Path $logRoot "$mode.debugger.log"), $debug)
        if ($debug -match 'VUID-|SYNC-HAZARD') { throw "NoAPI $mode diagnostic: $debug" }
        if ($mode -eq 'validation' -and ($debug -notmatch 'VK_LAYER_KHRONOS_validation' -or
            $debug -notmatch 'Current Validation Enabled:[\s\S]{0,300}Synchronization')) {
            throw 'NoAPI validation run did not confirm layer and synchronization activation'
        }
        Write-Host "[noapi] ${mode}: three batches and guarded tails verified, no validation warnings/errors"
    }

    # A real API layer confirms the recurring loop has only submit and wait.
    # Isolate these instrumentation tests from implicit hybrid-GPU layers.
    # SDK 1.4.363.0 API dump can fault in get_dispatch_key/vkDestroyDevice
    # with nvoglv64's Optimus layer on an AMD-selected run. Ordinary and
    # core/synchronization runs above retain the normal layer environment.
    $env:VK_LOADER_LAYERS_DISABLE = '~implicit~'
    $env:VK_LOADER_LAYERS_ALLOW = $null
    $env:VK_LOADER_LAYERS_ENABLE = $null
    $env:VK_INSTANCE_LAYERS = 'VK_LAYER_LUNARG_api_dump'
    $env:VK_APIDUMP_DETAILED = 'false'
    $env:VK_APIDUMP_OUTPUT_FORMAT = 'text'
    $env:VK_APIDUMP_LOG_FILENAME = $null
    Write-Settings "lunarg_api_dump.file = false`nlunarg_api_dump.detailed = false`nlunarg_api_dump.output_format = text`n"
    $trace = (& $executable | Out-String)
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $logRoot 'api-trace.log'), $trace)
    Assert-Results $trace $exitCode 'API trace'
    $expectedCalls = @{
        vkCreateBuffer=1; vkAllocateMemory=1; vkMapMemory=1; vkGetBufferDeviceAddress=1;
        vkCreateComputePipelines=1; vkCreatePipelineLayout=1; vkCreateSemaphore=1;
        vkBeginCommandBuffer=1; vkCmdBindPipeline=1; vkCmdPushConstants=1;
        vkCmdDispatch=1; vkCmdPipelineBarrier2=1; vkEndCommandBuffer=1;
        vkQueueSubmit2=3; vkWaitSemaphores=3;
        vkDestroyBuffer=1; vkFreeMemory=1; vkDestroyPipeline=1; vkDestroyPipelineLayout=1;
        vkDestroySemaphore=1; vkDestroyCommandPool=1; vkDestroyDevice=1; vkDestroyInstance=1
    }
    foreach ($function in $expectedCalls.Keys) {
        $actual = Get-CallCount $trace $function
        if ($actual -ne $expectedCalls[$function]) { throw "Trace has $actual $function calls, expected $($expectedCalls[$function])" }
    }
    if ($trace -match "(?m)^$forbidden\(") { throw 'Trace contains another resource/command protocol' }
    $loop = ($trace -split '\[noapi\] setup:',2)[1] -split '\[noapi\] verified 3 resident-pointer batches',2
    foreach ($call in [regex]::Matches($loop[0], '(?m)^(vk\w+)\(')) {
        if ($call.Groups[1].Value -notin @('vkQueueSubmit2','vkWaitSemaphores')) {
            throw "Unexpected recurring Vulkan call: $($call.Groups[1].Value)"
        }
    }
    Write-Host '[noapi] trace (implicit layers isolated): one setup/recording, three submit/wait pairs, complete resource destruction'

    # Mask BDA on every real device. Reject before device creation or dispatch.
    $env:VK_INSTANCE_LAYERS = 'VK_LAYER_LUNARG_api_dump;VK_LAYER_KHRONOS_profiles'
    $fixtures = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'fixtures\noapi')).Path.Replace('\','/')
    Write-Settings @"
lunarg_api_dump.file = false
lunarg_api_dump.detailed = false
khronos_profiles.profile_emulation = true
khronos_profiles.profile_dirs = $fixtures
khronos_profiles.profile_name = VP_VKFASMG_noapi_rejection
khronos_profiles.simulate_capabilities = SIMULATE_FEATURES_BIT
khronos_profiles.default_feature_values = DEFAULT_FEATURE_VALUES_DEVICE
khronos_profiles.emulate_portability = false
"@
    $rejection = (& $executable | Out-String)
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $logRoot 'missing-bda.log'), $rejection)
    if ($exitCode -ne 1 -or $rejection -notmatch '\[noapi\] failed at step 5, result -8, rejected requirements 0x4\b' -or
        (Get-CallCount $rejection 'vkCreateDevice') -ne 0 -or (Get-CallCount $rejection 'vkCmdDispatch') -ne 0) {
        throw "NoAPI did not reject a missing BDA contract before device creation: $rejection"
    }
    Write-Host '[noapi] missing BDA: rejected before device creation, no alternate protocol'

    $env:VK_INSTANCE_LAYERS = $null
    foreach ($variable in @('VK_LOADER_LAYERS_DISABLE','VK_LOADER_LAYERS_ALLOW','VK_LOADER_LAYERS_ENABLE')) {
        [Environment]::SetEnvironmentVariable($variable,$previous[$variable])
    }
    $env:VK_DRIVER_FILES = Join-Path $logRoot 'driver-does-not-exist.json'
    $report = (& $executable | Out-String)
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $logRoot 'no-driver.stdout.log'), $report)
    if ($exitCode -ne 1 -or $report -notmatch '\[noapi\] failed at step (2|3|4|5), result -\d+') {
        throw "NoAPI did not report an unavailable driver: $report"
    }
    Write-Host '[noapi] without a driver: started, reported initialization failure, exited normally'
} finally {
    foreach ($variable in $variables) { [Environment]::SetEnvironmentVariable($variable, $previous[$variable]) }
}
