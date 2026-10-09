<#
    Run the loader examples and set what each executable is made of side by
    side.  Everything is read from the executables and the link maps beside
    them:

      Objects   Vulkan program and loader objects (shared stdout helper omitted)
      Imports   Vulkan functions Windows must bind before the program starts
      Delayed   Vulkan functions in slots the linker built for delay-loading
      Slots     function slots the program defines for itself, eight bytes each
                (the explicit bootstrap's resolver pointer is separate)
      Thunks    named Vulkan import jump thunks, six bytes each on x64
      Bootstrap explicit runtime loading code, strings, and state bytes
      Dense     whether those slots lie side by side as one table
      Support   bytes that serve the slots: resolvers, names, first-call stubs
                and thunks, as the linker laid them out (padding to the next
                group included)
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Executables
)

$ErrorActionPreference = 'Stop'

$rows = foreach ($executable in $Executables.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $objects = [System.Collections.Generic.HashSet[string]]::new()
    $slots = [System.Collections.Generic.List[int]]::new()
    $thunks = [System.Collections.Generic.List[int]]::new()
    $support = 0
    $bootstrap = 0
    $namedThunks = 0
    foreach ($line in (Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($executable, 'map')))) {
        # $vk groups are the loaders'; .didat is the linker's delay-load data, slots apart
        if ($line -match '^\s*\d{4}:[0-9a-f]{8}\s+([0-9a-f]+)H\s+(\.\w+\$vk\w*|\.didat\$\d)\s') {
            if ($Matches[2] -like '*$vkrt') { $bootstrap += [Convert]::ToInt32($Matches[1], 16) }
            elseif ($Matches[2] -notin '.data$vk','.didat$5') { $support += [Convert]::ToInt32($Matches[1], 16) }
        } elseif ($line -match '^\s*\d{4}:[0-9a-f]{8}\s+vk\w+\s+[0-9a-f]{16}\s+f\s+vulkan-1:vulkan-1\.dll\s*$') {
            $namedThunks++
        } elseif ($line -match '^\s*\d{4}:([0-9a-f]{8})\s+(__tailMerge_\w+|__imp_load_vk\w+)\s') {
            $thunks.Add([Convert]::ToInt32($Matches[1], 16))
        } elseif ($line -match '^\s*\d{4}:([0-9a-f]{8})\s+(\S+)\s+[0-9a-f]{16}\s+(?:f\s+)?((?:loader|vk)_\w+\.obj)\s*$') {
            if ($Matches[3] -ne 'loader_console.obj') { [void]$objects.Add($Matches[3]) }
            if ($Matches[2] -like '__imp_vk*' -and $Matches[2] -ne '__imp_vkGetInstanceProcAddr') { $slots.Add([Convert]::ToInt32($Matches[1], 16)) }
        }
    }
    # The linker's delay-load thunks: one that sets the registers aside, then twelve bytes a function.
    if ($thunks.Count) { $support += ($thunks | Measure-Object -Maximum).Maximum + 12 - ($thunks | Measure-Object -Minimum).Minimum }
    $support += 6 * $namedThunks
    $dense = if (-not $slots.Count) { '-' }
             elseif ((($slots | Measure-Object -Maximum).Maximum - ($slots | Measure-Object -Minimum).Minimum + 8) -eq 8 * $slots.Count) { 'yes' }
             else { 'no' }
    $imported = & dumpbin.exe /NOLOGO /IMPORTS:vulkan-1.dll $executable
    if ($LASTEXITCODE) { throw "dumpbin could not inspect $executable" }
    $imports = @($imported | Where-Object { $_ -match '^\s+[0-9A-Fa-f]+\s+vk\w+\s*$' }).Count
    $delayed = @($imported | Where-Object { $_ -match '^\s+[0-9A-Fa-f]{16}\s+[0-9A-Fa-f]+\s+vk\w+\s*$' }).Count

    $report = (& $executable | Out-String).Trim()
    if ($LASTEXITCODE) { throw "$executable failed at step $LASTEXITCODE`n$report" }
    Write-Host $report
    Write-Host ''

    [pscustomobject]@{
        Example = [System.IO.Path]::GetFileNameWithoutExtension($executable) -replace '^loader_',''
        Objects = $objects.Count
        'Exe bytes' = (Get-Item -LiteralPath $executable).Length
        Imports = $imports
        Delayed = $delayed
        Slots = $slots.Count
        Dense = $dense
        Thunks = $namedThunks
        'Support bytes' = $support
        'Bootstrap bytes' = $bootstrap
    }
}
$rows | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
