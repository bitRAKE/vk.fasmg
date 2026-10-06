<#
    Assemble a NEWCOFF object with fasm2. Its batch wrapper can hide fasmg's
    failing exit code, so remove old output and require a fresh object.
#>
param(
    [Parameter(Mandatory = $true)] [string]$Fasm2,
    [Parameter(Mandatory = $true)] [string]$Source,
    [Parameter(Mandatory = $true)] [string]$Output,
    [string]$Includes = ''
)

$ErrorActionPreference = 'Stop'
$assembler = Get-Command $Fasm2 -ErrorAction Stop
if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Assembly source not found: $Source" }
foreach ($path in @($Output, [System.IO.Path]::ChangeExtension($Output, 'vkuse'))) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
$arguments = @()
foreach ($include in $Includes.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $arguments += "-iinclude('$include')"
}
$arguments += @($Source, $Output)
$report = (& $assembler.Source @arguments 2>&1 | Out-String)
if ($LASTEXITCODE -or -not (Test-Path -LiteralPath $Output -PathType Leaf) -or $report -match '(?im)^warning') {
    foreach ($path in @($Output, [System.IO.Path]::ChangeExtension($Output, 'vkuse'))) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    throw "fasm2 rejected ${Source}:`n$report"
}
Write-Host $report.TrimEnd()
