<#
    Project the Vulkan registry into fasmg includes for the Windows x64 ABI.

        <Output>\core.inc              constants, types and functions through -TargetApi
        <Output>\<author>\<name>.inc   one file per extension     VK_EXT_debug_utils -> ext\debug_utils.inc
        <Output>\video\<name>.inc      one file per video header  vulkan_video_codec_h264std -> codec_h264std.inc
        <Output>\vulkan-1.def          every function, for a delay-load import library
        <TestOutput>\               layout asserts, an include-everything list, SDK manifests, report

    The includes carry no guards, nested includes or conditional definitions.
    Every constant, type and function is emitted by exactly one file, and the
    including source selects its API surface by what it includes, in order.
    Functions are not instructions: each file appends its function names to
    loader_functions_instance or loader_functions_device, by the resolver that
    serves them, and an <Output>\loader\ include turns the gathered names into
    callable interfaces.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Registry,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [Parameter(Mandatory = $true)]
    [string]$TestOutput,

    [string]$VideoRegistry,

    [string]$TargetApi = '1.4'
)

$ErrorActionPreference = 'Stop'

function New-NameSet {
    return ,[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
}
function New-Lines {
    return ,[System.Collections.Generic.List[string]]::new()
}
# Generated text must be reproducible, so its order must not depend on culture.
function Sort-Names($names) {
    $sorted = [string[]]@($names)
    [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    return ,$sorted
}
function Convert-ApiVersion([string]$value) {
    if ($value -notmatch '^(\d+)\.(\d+)') { return 0 }
    return [int]$Matches[1] * 1000 + [int]$Matches[2]
}
function Test-VulkanApi($attribute) {
    if (-not $attribute) { return $true }
    return (([string]$attribute -split ',') -contains 'vulkan')
}

if (-not (Test-Path -LiteralPath $Registry -PathType Leaf)) {
    throw "Vulkan registry not found: $Registry"
}
$target = Convert-ApiVersion $TargetApi
if (-not $target) { throw "Invalid target API: $TargetApi" }

[xml]$vk = Get-Content -Raw -LiteralPath $Registry
if (-not $VideoRegistry) { $VideoRegistry = Join-Path (Split-Path -Parent $Registry) 'video.xml' }
$video = $null
if (Test-Path -LiteralPath $VideoRegistry -PathType Leaf) {
    $video = [xml](Get-Content -Raw -LiteralPath $VideoRegistry)
} else {
    Write-Host "[vk] video registry not found; records using its types stay unresolved: $VideoRegistry"
}

# PowerShell's XML adapter prefers XmlElement.Name over a child <name>.  Vulkan
# funcpointer declarations use the child form, so always inspect the XML shape
# explicitly instead of trusting the adapter.
function Get-TypeName($node) {
    $attributeName = $node.GetAttribute('name')
    if ($attributeName) { return $attributeName }
    foreach ($child in $node.ChildNodes) {
        if ($child.LocalName -eq 'name') { return $child.InnerText }
        if ($child.LocalName -eq 'proto') {
            foreach ($part in $child.ChildNodes) {
                if ($part.LocalName -eq 'name') { return $part.InnerText }
            }
        }
    }
    return ''
}

$typeNodes = [System.Collections.Generic.List[object]]::new()
foreach ($type in @($vk.registry.types.type)) {
    if (Test-VulkanApi $type.api) { $typeNodes.Add($type) }
}
if ($video) {
    foreach ($type in @($video.registry.types.type)) { $typeNodes.Add($type) }
}

# ---------------------------------------------------------------------------
# Constants

# Registry constant expressions use C spelling.  Normalize the subset that is
# meaningful as a fasmg numeric expression, preserving decimal floats rather
# than obscuring them as bit patterns.
function Convert-ConstantValue([string]$value) {
    if (-not $value) { return $null }
    $value = $value.Trim()
    if ($value -match '^VK_MAKE_API_VERSION\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$') {
        return [string](([uint64]$Matches[1] -shl 29) -bor ([uint64]$Matches[2] -shl 22) -bor ([uint64]$Matches[3] -shl 12) -bor [uint64]$Matches[4])
    }
    if ($value -match '^VK_MAKE_VERSION\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$') {
        return [string](([uint64]$Matches[1] -shl 22) -bor ([uint64]$Matches[2] -shl 12) -bor [uint64]$Matches[3])
    }
    if ($value -match '^\(~0U?LL\)$') { return '0xFFFFFFFFFFFFFFFF' }
    if ($value -match '^\(~0U\)$' -or $value -match '^\(~0\)$') { return '0xFFFFFFFF' }
    if ($value -match '^\(~0U-(\d+)\)$') { return "0xFFFFFFFF-$($Matches[1])" }
    if ($value -match '^\(~0ULL-(\d+)\)$') { return "0xFFFFFFFFFFFFFFFF-$($Matches[1])" }
    if ($value -match '^(-?\d+)(?:U|UL|ULL|L|LL)?$') { return $Matches[1] }
    if ($value -match '^(0[xX][0-9a-fA-F]+)(?:U|UL|ULL|L|LL)?$') { return $Matches[1] }
    if ($value -match '^(-?(?:\d+\.\d*|\d*\.\d+))(?:F|f)?$') { return $Matches[1] }
    return $null
}

# The video headers version themselves with object-like macros that the
# registry records as types; their values are constants like any other.
$defineValues = @{}
foreach ($type in $typeNodes) {
    if ([string]$type.category -ne 'define') { continue }
    if ([string]$type.InnerText -match 'VK_MAKE_VIDEO_STD_VERSION\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)') {
        $defineValues[(Get-TypeName $type)] = [string](([uint64]$Matches[1] -shl 22) -bor ([uint64]$Matches[2] -shl 12) -bor [uint64]$Matches[3])
    }
}

$enumValues = @{}
$stringConstants = @{}
foreach ($name in $defineValues.Keys) { $enumValues[$name] = $defineValues[$name] }
function Add-EnumValues($requireBlocks, [int]$defaultExtensionNumber) {
    foreach ($require in @($requireBlocks)) {
        foreach ($enum in @($require.enum)) {
            $name = [string]$enum.name
            if (-not $name -or $enumValues.ContainsKey($name) -or $stringConstants.ContainsKey($name)) { continue }
            if ($enum.offset) {
                $number = if ($enum.extnumber) { [int]$enum.extnumber } else { $defaultExtensionNumber }
                $numeric = 1000000000 + ($number - 1) * 1000 + [int]$enum.offset
                if ([string]$enum.dir -eq '-') { $numeric = -$numeric }
                $enumValues[$name] = [string]$numeric
            } elseif ($enum.bitpos) {
                $enumValues[$name] = "1 shl $([string]$enum.bitpos)"
            } elseif ($enum.value) {
                $raw = [string]$enum.value
                if ($raw -match '^"(.*)"$') { $stringConstants[$name] = $Matches[1] }
                else {
                    $converted = Convert-ConstantValue $raw
                    if ($null -eq $converted -and $defineValues.ContainsKey($raw)) { $converted = $defineValues[$raw] }
                    if ($null -ne $converted) { $enumValues[$name] = $converted }
                }
            }
        }
    }
}
foreach ($enumBlock in @($vk.registry.enums)) { Add-EnumValues @($enumBlock) 0 }
foreach ($extension in @($vk.registry.extensions.extension)) {
    if (Test-VulkanApi $extension.supported) { Add-EnumValues @($extension.SelectNodes('./require')) ([int]$extension.number) }
}
foreach ($feature in @($vk.registry.feature)) {
    if (Test-VulkanApi $feature.api) { Add-EnumValues @($feature.SelectNodes('./require')) 0 }
}
if ($video) {
    foreach ($enumBlock in @($video.registry.enums)) { Add-EnumValues @($enumBlock) 0 }
    foreach ($extension in @($video.registry.extensions.extension)) { Add-EnumValues @($extension.SelectNodes('./require')) 0 }
}
foreach ($pass in 1..4) {
    foreach ($enum in @($vk.SelectNodes('//enum[@alias]'))) {
        $name = [string]$enum.name
        $alias = [string]$enum.alias
        if (-not $enumValues.ContainsKey($name) -and $enumValues.ContainsKey($alias)) { $enumValues[$name] = $enumValues[$alias] }
        if (-not $stringConstants.ContainsKey($name) -and $stringConstants.ContainsKey($alias)) { $stringConstants[$name] = $stringConstants[$alias] }
    }
}
function Test-Constant([string]$name) {
    return ($enumValues.ContainsKey($name) -or $stringConstants.ContainsKey($name))
}
function Get-ArrayLength([string]$name) {
    if (-not $enumValues.ContainsKey($name)) { return 0 }
    $value = $enumValues[$name]
    if ($value -match '^\d+$') { return [int64]$value }
    if ($value -match '^0[xX]([0-9a-fA-F]+)$') { return [Convert]::ToInt64($Matches[1], 16) }
    return 0
}

# ---------------------------------------------------------------------------
# ABI projection

# A member named like a fasmg directive must be escaped at its declaration.
# The leading ? is not part of the public field name: `?format dd ?` remains
# addressable as VkImageViewCreateInfo.format.
$reservedMemberNames = New-NameSet
foreach ($word in @(
    'format','section','public','extrn','include','use','if','else','end','while',
    'repeat','match','struct','ends','label','org','virtual','namespace','element',
    'define','restore','purge','display','err','load','store','data','size','align',
    'db','dw','dd','dq','dt','du','rb','rw','rd','rq','rt','file','times','iterate',
    'irp','irpv','indx','postpone','calminstruction','macro','esc','assert','break')) {
    [void]$reservedMemberNames.Add($word)
}
function Get-SafeMemberName([string]$member) {
    if ($reservedMemberNames.Contains($member)) { return "?$member" }
    return $member
}

$typeSize = @{}
$typeAlign = @{}
$typeCategory = @{}
function Set-TypeAbi([string]$name, [int]$size, [int]$alignment, [string]$category = '') {
    $typeSize[$name] = $size
    $typeAlign[$name] = $alignment
    if ($category) { $typeCategory[$name] = $category }
}
foreach ($primitive in @(
    @('char',1),@('int8_t',1),@('uint8_t',1),@('int16_t',2),@('uint16_t',2),
    @('int32_t',4),@('uint32_t',4),@('int',4),@('float',4),
    @('int64_t',8),@('uint64_t',8),@('double',8),@('size_t',8))) {
    Set-TypeAbi $primitive[0] $primitive[1] $primitive[1] 'primitive'
}

# Only model external types whose Windows x64 ABI is known. Other window-system
# types belong to headers unavailable in this target environment; records using
# them are reported as unresolved instead of being guessed.
$externalTypeAbi = @{
    'DWORD' = @(4,4)
    'HANDLE' = @(8,8)
    'HINSTANCE' = @(8,8)
    'HMONITOR' = @(8,8)
    'HWND' = @(8,8)
    'LPCWSTR' = @(8,8)
    'SECURITY_ATTRIBUTES' = @(24,8)
}
foreach ($type in $typeNodes) {
    if ($type.category) { continue }
    $name = Get-TypeName $type
    if (-not $name -or -not $type.requires -or $typeSize.ContainsKey($name)) { continue }
    if (-not $externalTypeAbi.ContainsKey($name)) { continue }
    Set-TypeAbi $name $externalTypeAbi[$name][0] $externalTypeAbi[$name][1] 'platform'
}

$structNodes = @{}
$unionNodes = @{}
foreach ($type in $typeNodes) {
    $category = [string]$type.category
    $name = Get-TypeName $type
    if (-not $name) { continue }
    $typeCategory[$name] = $category
    switch ($category) {
        'basetype' {
            $text = [string]$type.InnerText
            if ($text -match 'uint64_t|int64_t') { Set-TypeAbi $name 8 8 $category }
            elseif ($text -match 'uint32_t|int32_t') { Set-TypeAbi $name 4 4 $category }
            elseif ($text -match '\*') { Set-TypeAbi $name 8 8 $category }
        }
        'bitmask' { if ([string]$type.InnerText -match 'VkFlags64') { Set-TypeAbi $name 8 8 $category } else { Set-TypeAbi $name 4 4 $category } }
        'enum' { Set-TypeAbi $name 4 4 $category }
        'handle' { Set-TypeAbi $name 8 8 $category }
        'funcpointer' { Set-TypeAbi $name 8 8 $category }
        'struct' { if (-not $type.alias) { $structNodes[$name] = $type } }
        'union' { if (-not $type.alias) { $unionNodes[$name] = $type } }
    }
}
foreach ($type in $typeNodes) {
    if (-not $type.alias) { continue }
    $name = [string]$type.name
    $alias = [string]$type.alias
    $typeCategory[$name] = $typeCategory[$alias]
    if ($structNodes.ContainsKey($alias)) { $structNodes[$name] = $structNodes[$alias] }
    elseif ($unionNodes.ContainsKey($alias)) { $unionNodes[$name] = $unionNodes[$alias] }
    elseif ($typeSize.ContainsKey($alias)) { Set-TypeAbi $name $typeSize[$alias] $typeAlign[$alias] $typeCategory[$alias] }
}

function Get-RecordMembers($node) {
    $members = [System.Collections.Generic.List[object]]::new()
    foreach ($member in @($node.member)) {
        if (-not (Test-VulkanApi $member.api)) { continue }
        $xmlText = $member.OuterXml
        $memberType = if ($member.type -is [string]) { [string]$member.type } else { [string]$member.type.InnerText }
        $memberName = if ($member.name -is [string]) { [string]$member.name } else { [string]$member.name.InnerText }
        if (-not $memberType -or -not $memberName) { return $null }
        $pointer = $false
        if ($xmlText -match '</type>([^<]*)<name[ >]') { $pointer = ($Matches[1] -match '\*') }
        $count = 1
        $bits = 0
        $tail = ''
        # Declarators immediately follow </name>.  Stop before a trailing
        # <comment>; comments such as "memoryTypes[]" are prose, not another
        # array dimension.
        if ($xmlText -match '</name>(.*?)(?:<comment>|</member>)') { $tail = $Matches[1] }
        if ($tail -match '^\s*:\s*(\d+)\s*$') { $bits = [int]$Matches[1] }
        # The registry does not mark every named dimension up as an <enum>.
        foreach ($dimension in [regex]::Matches($tail, '\[\s*(?:(?:<enum>)?([A-Za-z_]\w*)(?:</enum>)?|(\d+))\s*\]')) {
            if ($dimension.Groups[1].Success) {
                $length = Get-ArrayLength $dimension.Groups[1].Value
                if (-not $length) { return $null }
                $count *= $length
            } else {
                $count *= [int]$dimension.Groups[2].Value
            }
        }
        if ($tail -match '\[' -and $count -eq 1) { return $null }
        $members.Add([pscustomobject]@{
            Type = $memberType
            Name = $memberName
            SafeName = Get-SafeMemberName $memberName
            Pointer = $pointer
            Count = $count
            Bits = $bits
        })
    }
    return $members
}

function Get-DataDirective([int]$size) {
    switch ($size) { 1 { return 'db' } 2 { return 'dw' } 4 { return 'dd' } 8 { return 'dq' } }
    return $null
}

# C bit-fields share storage units.  The Microsoft ABI opens a new unit when
# the declared type changes size or the field does not fit; a unit has the
# size and alignment of that type.  fasmg has no bit-field members, so a unit
# is projected as one field (bits0, bits1, ...) annotated with what it packs.
function Close-BitUnit($state, $lines) {
    if ($null -eq $state.Unit) { return }
    $lines.Add("`tbits$($state.Index) $(Get-DataDirective $state.Unit.Size) ?`t; $($state.Unit.Fields -join ' ')")
    $state.Index++
    $state.Unit = $null
}

$recordLayouts = @{}
$recordDependencies = @{}
$failedRecords = @{}
function Resolve-TypeAbi([string]$name) {
    if ($typeSize.ContainsKey($name)) { return $true }
    if ($failedRecords.ContainsKey($name)) { return $false }
    if ($unionNodes.ContainsKey($name)) { return (Resolve-UnionAbi $name) }
    if ($structNodes.ContainsKey($name)) { return (Resolve-StructAbi $name) }
    $failedRecords[$name] = $true
    return $false
}
function Resolve-UnionAbi([string]$name) {
    $failedRecords[$name] = $true
    $members = Get-RecordMembers $unionNodes[$name]
    if ($null -eq $members) { return $false }
    $size = 0
    $alignment = 1
    foreach ($member in $members) {
        if ($member.Bits) { return $false }
        if ($member.Pointer) { $memberSize = 8; $memberAlign = 8 }
        else {
            if (-not (Resolve-TypeAbi $member.Type)) { return $false }
            $memberSize = $typeSize[$member.Type]
            $memberAlign = $typeAlign[$member.Type]
        }
        $memberSize *= $member.Count
        if ($memberSize -gt $size) { $size = $memberSize }
        if ($memberAlign -gt $alignment) { $alignment = $memberAlign }
    }
    if ($size % $alignment) { $size += $alignment - ($size % $alignment) }
    $failedRecords.Remove($name)
    Set-TypeAbi $name $size $alignment 'union'
    $recordLayouts[$name] = @{ Size = $size; Align = $alignment; Lines = @("`trb $size"); Members = @(); Bitfields = @(); Union = $true }
    $recordDependencies[$name] = @()
    return $true
}
function Resolve-StructAbi([string]$name) {
    if ($recordLayouts.ContainsKey($name)) { return $true }
    $failedRecords[$name] = $true
    $members = Get-RecordMembers $structNodes[$name]
    if ($null -eq $members) { return $false }
    $lines = New-Lines
    $manifestMembers = [System.Collections.Generic.List[object]]::new()
    $manifestBitfields = [System.Collections.Generic.List[object]]::new()
    $dependencies = New-NameSet
    $bitState = @{ Unit = $null; Index = 0 }
    $offset = 0
    $maxAlignment = 1
    foreach ($member in $members) {
        if ($member.Pointer) { $memberSize = 8; $memberAlign = 8; $kind = 'pointer' }
        else {
            if (-not (Resolve-TypeAbi $member.Type)) { return $false }
            $memberSize = $typeSize[$member.Type]
            $memberAlign = $typeAlign[$member.Type]
            $kind = if ($recordLayouts.ContainsKey($member.Type)) { 'record' } else { 'scalar' }
        }
        if ($memberAlign -gt $maxAlignment) { $maxAlignment = $memberAlign }
        if ($member.Bits) {
            if ($kind -ne 'scalar' -or $member.Count -ne 1 -or $null -eq (Get-DataDirective $memberSize)) { return $false }
            $unit = $bitState.Unit
            if ($null -eq $unit -or $unit.Size -ne $memberSize -or ($unit.Used + $member.Bits) -gt ($memberSize * 8)) {
                Close-BitUnit $bitState $lines
                $padding = if ($offset % $memberAlign) { $memberAlign - ($offset % $memberAlign) } else { 0 }
                if ($padding) { $lines.Add("`trb $padding"); $offset += $padding }
                $unit = @{ Size = $memberSize; Used = 0; Offset = $offset; Fields = New-Lines }
                $bitState.Unit = $unit
                $offset += $memberSize
            }
            $range = if ($member.Bits -gt 1) { "$($unit.Used)-$($unit.Used + $member.Bits - 1)" } else { [string]$unit.Used }
            $unit.Fields.Add("$($member.Name):$range")
            $manifestBitfields.Add([pscustomobject]@{ Name = $member.Name; Bit = $unit.Offset * 8 + $unit.Used; Width = $member.Bits })
            $unit.Used += $member.Bits
            continue
        }
        Close-BitUnit $bitState $lines
        $padding = if ($offset % $memberAlign) { $memberAlign - ($offset % $memberAlign) } else { 0 }
        if ($padding) { $lines.Add("`trb $padding"); $offset += $padding }
        $manifestMembers.Add([pscustomobject]@{ Name = $member.Name; Offset = $offset; Size = $memberSize * $member.Count })
        if ($kind -eq 'record' -and $member.Count -eq 1) {
            $lines.Add("`t$($member.SafeName) $($member.Type)")
            [void]$dependencies.Add($member.Type)
        } elseif ($kind -eq 'pointer') {
            if ($member.Count -eq 1) { $lines.Add("`t$($member.SafeName) dq ?") }
            else { $lines.Add("`t$($member.SafeName) rq $($member.Count)") }
        } else {
            # An array is reserved in units of its element's alignment, so a
            # field's unit states the boundary it needs: eight-byte structs of
            # two dwords are dwords, not qwords.
            $directive = Get-DataDirective $memberAlign
            if ($member.Count -eq 1 -and $kind -eq 'scalar') { $lines.Add("`t$($member.SafeName) $directive ?") }
            else { $lines.Add("`t$($member.SafeName) r$($directive.Substring(1)) $($memberSize * $member.Count / $memberAlign)") }
        }
        $offset += $memberSize * $member.Count
    }
    Close-BitUnit $bitState $lines
    $tailPadding = if ($offset % $maxAlignment) { $maxAlignment - ($offset % $maxAlignment) } else { 0 }
    if ($tailPadding) { $lines.Add("`trb $tailPadding"); $offset += $tailPadding }
    $failedRecords.Remove($name)
    Set-TypeAbi $name $offset $maxAlignment 'struct'
    $recordLayouts[$name] = @{ Size = $offset; Align = $maxAlignment; Lines = $lines; Members = $manifestMembers; Bitfields = $manifestBitfields; Union = $false }
    $recordDependencies[$name] = @($dependencies)
    return $true
}
foreach ($name in @($structNodes.Keys) + @($unionNodes.Keys)) { [void](Resolve-TypeAbi $name) }
function Test-ProjectedType([string]$name) {
    return ($typeSize.ContainsKey($name) -or $recordLayouts.ContainsKey($name))
}

# ---------------------------------------------------------------------------
# Function resolvers

# vkGetDeviceProcAddr serves what dispatches from a device or its children.
# vkGetInstanceProcAddr serves the rest: what dispatches from an instance or a
# physical device, given the instance, and the functions that precede any
# instance, given none.

$parents = @{}
foreach ($type in $vk.registry.types.type) {
    if ($type.category -ne 'handle') { continue }
    $name = if ($type.name) { [string]$type.name } else { [string]$type.GetAttribute('name') }
    if ($name) { $parents[$name] = [string]$type.GetAttribute('parent') }
}

function Get-DispatchClass([string]$typeName) {
    $seen = @{}
    while ($typeName -and -not $seen.ContainsKey($typeName)) {
        $seen[$typeName] = $true
        if ($typeName -eq 'VkInstance' -or $typeName -eq 'VkPhysicalDevice') { return 'instance' }
        if ($typeName -eq 'VkDevice' -or $typeName -eq 'VkQueue' -or $typeName -eq 'VkCommandBuffer') { return 'device' }
        $typeName = $parents[$typeName]
    }
    return 'instance'
}

$classes = @{}
$aliases = @()
foreach ($command in $vk.registry.commands.command) {
    if (-not (Test-VulkanApi $command.api)) { continue }
    $alias = [string]$command.GetAttribute('alias')
    if ($alias) {
        $aliases += ,@([string]$command.GetAttribute('name'), $alias)
        continue
    }
    $name = [string]$command.proto.name
    if (-not $name) { continue }
    $params = @($command.SelectNodes('param'))
    $firstType = if ($params.Count) { [string]$params[0].type } else { '' }
    $class = Get-DispatchClass $firstType
    if ($name -eq 'vkGetDeviceProcAddr') { $class = 'instance' }
    $classes[$name] = $class
}

$unresolved = $aliases
do {
    $next = @()
    $progress = $false
    foreach ($pair in $unresolved) {
        if ($classes.ContainsKey($pair[1])) {
            $classes[$pair[0]] = $classes[$pair[1]]
            $progress = $true
        } else {
            $next += ,$pair
        }
    }
    $unresolved = $next
} while ($progress -and $unresolved.Count)
if ($unresolved.Count) { throw "Could not classify $($unresolved.Count) Vulkan command aliases" }

# ---------------------------------------------------------------------------
# Modules: the core API plus one per extension and per video header

$moduleNode = @{}
$moduleKind = @{}
$moduleNumber = @{}
foreach ($extension in $vk.registry.extensions.extension) {
    if (-not (Test-VulkanApi $extension.supported)) { continue }
    $name = [string]$extension.GetAttribute('name')
    $moduleNode[$name] = $extension
    $moduleKind[$name] = 'extension'
    $moduleNumber[$name] = [int]$extension.GetAttribute('number')
}
if ($video) {
    foreach ($extension in $video.registry.extensions.extension) {
        $name = [string]$extension.GetAttribute('name')
        $moduleNode[$name] = $extension
        $moduleKind[$name] = 'video'
        $moduleNumber[$name] = [int]$extension.GetAttribute('number')
    }
}

function Test-CoreToken([string]$token) {
    if ($token -notmatch '^VK_VERSION_(\d+)_(\d+)$') { return $false }
    return (([int]$Matches[1] * 1000 + [int]$Matches[2]) -le $target)
}
function Test-PromotedToCore([string]$name) {
    $seen = @{}
    while ($moduleKind[$name] -eq 'extension' -and -not $seen.ContainsKey($name)) {
        $seen[$name] = $true
        $promoted = [string]$moduleNode[$name].GetAttribute('promotedto')
        if (-not $promoted) { return $false }
        if (Test-CoreToken $promoted) { return $true }
        $name = $promoted
    }
    return $false
}
function Split-TopLevel([string]$expression, [char]$separator) {
    $parts = New-Lines
    $depth = 0
    $start = 0
    for ($i = 0; $i -lt $expression.Length; $i++) {
        if ($expression[$i] -eq '(') { $depth++ }
        elseif ($expression[$i] -eq ')') { $depth-- }
        elseif ($expression[$i] -eq $separator -and $depth -eq 0) {
            $parts.Add($expression.Substring($start, $i - $start))
            $start = $i + 1
        }
    }
    $parts.Add($expression.Substring($start))
    return $parts.ToArray()
}
function Remove-OuterParentheses([string]$expression) {
    $expression = $expression.Trim()
    while ($expression.Length -ge 2 -and $expression[0] -eq '(' -and $expression[-1] -eq ')') {
        $depth = 0
        $isOuter = $true
        for ($i = 0; $i -lt $expression.Length; $i++) {
            if ($expression[$i] -eq '(') { $depth++ }
            elseif ($expression[$i] -eq ')') { $depth-- }
            if ($depth -eq 0 -and $i -lt $expression.Length - 1) { $isOuter = $false; break }
        }
        if (-not $isOuter) { break }
        $expression = $expression.Substring(1, $expression.Length - 2).Trim()
    }
    return $expression
}
# True when the core baseline alone satisfies a registry dependency expression.
function Test-BaselineSatisfies([string]$expression) {
    $expression = Remove-OuterParentheses $expression
    if (-not $expression) { return $true }
    $alternatives = @(Split-TopLevel $expression ',')
    if ($alternatives.Count -gt 1) {
        foreach ($alternative in $alternatives) { if (Test-BaselineSatisfies $alternative) { return $true } }
        return $false
    }
    $terms = @(Split-TopLevel $expression '+')
    if ($terms.Count -gt 1) {
        foreach ($term in $terms) { if (-not (Test-BaselineSatisfies $term)) { return $false } }
        return $true
    }
    return ((Test-CoreToken $expression) -or (Test-PromotedToCore $expression))
}
function Get-VulkanRequires($node) {
    foreach ($require in $node.SelectNodes('./require')) {
        if (Test-VulkanApi $require.api) { $require }
    }
}

# An extension's author prefix names its directory: VK_NV_mesh_shader and
# VK_EXT_mesh_shader become nv/mesh_shader.inc and ext/mesh_shader.inc.
$moduleFile = @{}
$outputDirectories = New-NameSet
foreach ($name in $moduleNode.Keys) {
    if ($moduleKind[$name] -eq 'video') {
        if ($name -cnotmatch '^vulkan_video_(.+)$') { throw "Unexpected video header name '$name'" }
        $directory = 'video'
    } else {
        if ($name -cnotmatch '^VK_([A-Z0-9]+)_(.+)$') { throw "Unexpected extension name '$name'" }
        $directory = $Matches[1].ToLowerInvariant()
        if ($directory -in @('video','loader')) { throw "Extension author '$directory' collides with a reserved directory" }
    }
    [void]$outputDirectories.Add($directory)
    $moduleFile[$name] = "$directory/$($Matches[$Matches.Count - 1].ToLowerInvariant()).inc"
}
$fileOwners = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($name in $moduleFile.Keys) {
    if ($fileOwners.ContainsKey($moduleFile[$name])) { throw "$name and $($fileOwners[$moduleFile[$name]]) both map to $($moduleFile[$name])" }
    $fileOwners[$moduleFile[$name]] = $name
}

# ---------------------------------------------------------------------------
# What each module requires

$enumBlockMembers = @{}
$enumBlocks = @($vk.registry.enums)
if ($video) { $enumBlocks += @($video.registry.enums) }
foreach ($enumBlock in $enumBlocks) {
    $members = New-NameSet
    foreach ($enum in @($enumBlock.enum)) {
        $name = [string]$enum.name
        if (Test-Constant $name) { [void]$members.Add($name) }
    }
    $enumBlockMembers[[string]$enumBlock.name] = $members
}

$coreCommands = New-NameSet
$coreTypeRoots = New-NameSet
$coreEnumNames = New-NameSet

# API Constants are unconditional.  A named enum block follows ownership of
# its Vk* enum type and is added after type ownership is known.
foreach ($name in $enumBlockMembers['API Constants']) { [void]$coreEnumNames.Add($name) }
for ($minor = 0; $minor -le [int]($TargetApi -replace '^1\.',''); $minor++) {
    $name = "VK_API_VERSION_1_$minor"
    $enumValues[$name] = [string](([uint64]1 -shl 22) -bor ([uint64]$minor -shl 12))
    [void]$coreEnumNames.Add($name)
}
$enumValues['VK_NULL_HANDLE'] = '0'
[void]$coreEnumNames.Add('VK_NULL_HANDLE')
foreach ($feature in $vk.registry.feature) {
    if (-not (Test-VulkanApi $feature.api)) { continue }
    if ((Convert-ApiVersion ([string]$feature.number)) -gt $target) { continue }
    foreach ($require in (Get-VulkanRequires $feature)) {
        foreach ($command in @($require.command)) {
            $name = [string]$command.name
            if ($classes.ContainsKey($name)) { [void]$coreCommands.Add($name) }
        }
        foreach ($type in @($require.type)) {
            $name = [string]$type.name
            if (Test-ProjectedType $name) { [void]$coreTypeRoots.Add($name) }
        }
        foreach ($enum in @($require.enum)) {
            $name = [string]$enum.name
            if (Test-Constant $name) { [void]$coreEnumNames.Add($name) }
        }
    }
}
# A promoted extension's command aliases are listed by the core feature, but
# its legacy feature/property structs are not repeated there.  They remain
# valid spellings in the core API and therefore belong in core.inc too.
foreach ($extensionName in $moduleNode.Keys) {
    if (-not (Test-PromotedToCore $extensionName)) { continue }
    foreach ($require in (Get-VulkanRequires $moduleNode[$extensionName])) {
        foreach ($type in @($require.type)) {
            $name = [string]$type.name
            if (Test-ProjectedType $name) { [void]$coreTypeRoots.Add($name) }
        }
        foreach ($enum in @($require.enum)) {
            $name = [string]$enum.name
            if ($name -match '_(?:EXTENSION_NAME|SPEC_VERSION)$') { continue }
            if (Test-Constant $name) { [void]$coreEnumNames.Add($name) }
        }
    }
}
foreach ($typeName in $coreTypeRoots) {
    if ($enumBlockMembers.ContainsKey($typeName)) {
        foreach ($name in $enumBlockMembers[$typeName]) { [void]$coreEnumNames.Add($name) }
    }
}

function Get-TypeProjectionClosure($roots, $excluded) {
    $result = New-NameSet
    $pending = [System.Collections.Generic.Stack[string]]::new()
    foreach ($root in $roots) { $pending.Push($root) }
    while ($pending.Count) {
        $name = $pending.Pop()
        if ($excluded -and $excluded.Contains($name)) { continue }
        if (-not $result.Add($name)) { continue }
        foreach ($dependency in @($recordDependencies[$name])) { $pending.Push($dependency) }
    }
    return ,$result
}
$coreTypes = Get-TypeProjectionClosure $coreTypeRoots $null

$requiredCommands = @{}
$requiredTypes = @{}
$requiredEnums = @{}
$requiredOutright = @{}
$reachedTypes = @{}
foreach ($name in $moduleNode.Keys) {
    $commands = New-NameSet
    $types = New-NameSet
    $enums = New-NameSet
    $outright = New-NameSet
    foreach ($require in (Get-VulkanRequires $moduleNode[$name])) {
        # A block that depends on another extension describes an interaction
        # with it rather than something this extension brings on its own.
        $named = New-NameSet
        foreach ($command in @($require.command)) {
            $commandName = [string]$command.name
            if ($classes.ContainsKey($commandName) -and -not $coreCommands.Contains($commandName)) { [void]$commands.Add($commandName); [void]$named.Add($commandName) }
        }
        foreach ($type in @($require.type)) {
            $typeName = [string]$type.name
            if ((Test-ProjectedType $typeName) -and -not $coreTypes.Contains($typeName)) { [void]$types.Add($typeName); [void]$named.Add($typeName) }
            # A versioning macro is recorded as a type but projected as a constant.
            if ($defineValues.ContainsKey($typeName)) { [void]$enums.Add($typeName); [void]$named.Add($typeName) }
        }
        foreach ($enum in @($require.enum)) {
            $enumName = [string]$enum.name
            if ((Test-Constant $enumName) -and -not $coreEnumNames.Contains($enumName)) { [void]$enums.Add($enumName); [void]$named.Add($enumName) }
        }
        if (Test-BaselineSatisfies ([string]$require.GetAttribute('depends'))) { $outright.UnionWith($named) }
    }
    $requiredCommands[$name] = $commands
    $requiredTypes[$name] = $types
    $requiredEnums[$name] = $enums
    $requiredOutright[$name] = $outright
    $reachedTypes[$name] = Get-TypeProjectionClosure $types $coreTypes
}

# ---------------------------------------------------------------------------
# Ownership: every definition is emitted by exactly one file

# Without guards a definition cannot be repeated by each file that requires
# it.  Among the modules that reach one, prefer a video header (it defines the
# type), then a module that requires the definition outright, then one whose
# struct embeds it, then one that names it only for an interaction with
# another extension; ties go to the lowest registry number, which is the order
# the C headers define things in.
function Select-Owner([string]$entity, $candidates, $requiredTable) {
    $best = $null
    $bestKey = $null
    foreach ($name in $candidates) {
        $kind = if ($moduleKind[$name] -eq 'video') { 0 } else { 1 }
        $claim = if ($requiredOutright[$name].Contains($entity)) { 0 } elseif ($requiredTable[$name].Contains($entity)) { 2 } else { 1 }
        $key = '{0}{1}{2:D6}{3}' -f $kind,$claim,$moduleNumber[$name],$name
        if ($null -eq $bestKey -or [string]::CompareOrdinal($key, $bestKey) -lt 0) { $best = $name; $bestKey = $key }
    }
    return $best
}
function Add-Candidate($table, [string]$entity, [string]$module) {
    if (-not $table.ContainsKey($entity)) { $table[$entity] = [System.Collections.Generic.List[string]]::new() }
    $table[$entity].Add($module)
}

$ownedCommands = @{}
$ownedTypes = @{}
$ownedEnums = @{}
foreach ($name in $moduleNode.Keys) {
    $ownedCommands[$name] = New-NameSet
    $ownedTypes[$name] = New-NameSet
    $ownedEnums[$name] = New-NameSet
}
$sharedDefinitions = New-Lines
$elsewhere = @{}
function Set-Owners($candidateTable, $requiredTable, $ownedTable, $ownerTable, [string]$kind) {
    foreach ($entity in $candidateTable.Keys) {
        $candidates = $candidateTable[$entity]
        $owner = Select-Owner $entity $candidates $requiredTable
        $ownerTable[$entity] = $owner
        [void]$ownedTable[$owner].Add($entity)
        if ($candidates.Count -eq 1) { continue }
        $others = New-Lines
        foreach ($name in $candidates) {
            if ($name -ceq $owner) { continue }
            $others.Add($name)
            if (-not $elsewhere.ContainsKey($name)) { $elsewhere[$name] = @{} }
            if (-not $elsewhere[$name].ContainsKey($owner)) { $elsewhere[$name][$owner] = New-Lines }
            $elsewhere[$name][$owner].Add($entity)
        }
        $sharedDefinitions.Add("$kind|$entity|$($moduleFile[$owner])|$((Sort-Names $others) -join ',')")
    }
}

$typeCandidates = @{}
$commandCandidates = @{}
$enumCandidates = @{}
foreach ($name in $moduleNode.Keys) {
    foreach ($typeName in $reachedTypes[$name]) { Add-Candidate $typeCandidates $typeName $name }
    foreach ($commandName in $requiredCommands[$name]) { Add-Candidate $commandCandidates $commandName $name }
}
$typeOwner = @{}
$commandOwner = @{}
$enumOwner = @{}
Set-Owners $typeCandidates $requiredTypes $ownedTypes $typeOwner 'type'
Set-Owners $commandCandidates $requiredCommands $ownedCommands $commandOwner 'function'

# The values of an enum type travel with the type; values an extension adds to
# another type's domain are required by name.
$blockOwner = @{}
foreach ($name in $moduleNode.Keys) {
    foreach ($typeName in $ownedTypes[$name]) {
        if (-not $enumBlockMembers.ContainsKey($typeName)) { continue }
        foreach ($enumName in $enumBlockMembers[$typeName]) {
            if (-not $coreEnumNames.Contains($enumName)) { $blockOwner[$enumName] = $name }
        }
    }
}
foreach ($name in $moduleNode.Keys) {
    foreach ($enumName in $requiredEnums[$name]) {
        if (-not $blockOwner.ContainsKey($enumName)) { Add-Candidate $enumCandidates $enumName $name }
    }
}
foreach ($enumName in $blockOwner.Keys) { $enumCandidates[$enumName] = [System.Collections.Generic.List[string]]@($blockOwner[$enumName]) }
Set-Owners $enumCandidates $requiredEnums $ownedEnums $enumOwner 'constant'

# A struct that embeds another by value needs the file that defines it.  fasmg
# resolves the reference in either order, at the cost of a pass when the
# embedded definition comes later, so dependencies are listed first.
$includeFirst = @{}
foreach ($name in $moduleNode.Keys) {
    $needs = New-NameSet
    foreach ($typeName in $ownedTypes[$name]) {
        foreach ($dependency in @($recordDependencies[$typeName])) {
            if ($coreTypes.Contains($dependency)) { continue }
            if ($typeOwner[$dependency] -cne $name) { [void]$needs.Add($typeOwner[$dependency]) }
        }
    }
    $includeFirst[$name] = $needs
}

$includeOrder = [System.Collections.Generic.List[string]]::new()
$includeCycles = New-Lines
$visitState = @{}
function Add-InIncludeOrder([string]$name, $trail) {
    if ($visitState[$name] -eq 2) { return }
    if ($visitState[$name] -eq 1) {
        $includeCycles.Add((@($trail) + $name | ForEach-Object { $moduleFile[$_] }) -join ' -> ')
        return
    }
    $visitState[$name] = 1
    foreach ($dependency in (Sort-Names $includeFirst[$name])) { Add-InIncludeOrder $dependency (@($trail) + $name) }
    $visitState[$name] = 2
    $includeOrder.Add($name)
}
$byFile = @{}
foreach ($name in $moduleNode.Keys) { $byFile[$moduleFile[$name]] = $name }
foreach ($kind in @('video','extension')) {
    foreach ($file in (Sort-Names $byFile.Keys)) {
        if ($moduleKind[$byFile[$file]] -eq $kind) { Add-InIncludeOrder $byFile[$file] @() }
    }
}

# ---------------------------------------------------------------------------
# Emission

function Add-EnumDefinition($lines, [string]$name) {
    if ($enumValues.ContainsKey($name)) {
        $lines.Add("$name := $($enumValues[$name])")
    } elseif ($stringConstants.ContainsKey($name)) {
        $quoted = $stringConstants[$name].Replace("'", "''")
        $lines.Add("define $name '$quoted'")
    }
}
function Add-TypeDefinition($lines, [string]$name) {
    if ($recordLayouts.ContainsKey($name)) {
        $lines.Add("struct $name")
        foreach ($line in $recordLayouts[$name].Lines) { $lines.Add($line) }
        $lines.Add('ends')
    } elseif ($typeSize.ContainsKey($name)) {
        $lines.Add("sizeof.$name := $($typeSize[$name])")
    }
}
function Add-TypeDefinitions($lines, $projectedTypes) {
    $done = New-NameSet
    $emit = $null
    $emit = {
        param([string]$name)
        if (-not $projectedTypes.Contains($name) -or -not $done.Add($name)) { return }
        foreach ($dependency in @($recordDependencies[$name])) { & $emit $dependency }
        Add-TypeDefinition $lines $name
    }
    foreach ($name in (Sort-Names $projectedTypes)) { & $emit $name }
}
function Add-LoaderFunctions($lines, $commands) {
    foreach ($class in @('instance','device')) {
        $names = New-Lines
        foreach ($name in (Sort-Names $commands)) { if ($classes[$name] -eq $class) { $names.Add($name) } }
        if ($names.Count) { $lines.Add("define loader_functions_$class`t$($names -join ',')") }
    }
}
function Write-Lines([string]$path, $lines) {
    [System.IO.File]::WriteAllLines($path, $lines, [System.Text.UTF8Encoding]::new($false))
}

$includeRoot = ($Output -replace '\\','/').TrimEnd('/')
$testRoot = ($TestOutput -replace '\\','/').TrimEnd('/')
New-Item -ItemType Directory -Force -Path $Output,$TestOutput | Out-Null
# Extensions come and go between registries; hand-written loaders stay.
foreach ($directory in $outputDirectories) {
    $path = Join-Path $Output $directory
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    Get-ChildItem -LiteralPath $path -Filter '*.inc' -File | Remove-Item -Force
}

$coreLines = New-Lines
$coreLines.Add("; Vulkan core through $TargetApi. Generated from vk.xml; do not edit.")
$headerVersionNode = $vk.SelectSingleNode("//type[@category='define' and @api='vulkan,vulkanbase' and name='VK_HEADER_VERSION']")
if ($headerVersionNode -and $headerVersionNode.InnerText -match 'VK_HEADER_VERSION\s+(\d+)') {
    $headerVersion = [int]$Matches[1]
    $headerComplete = ([uint64]1 -shl 22) -bor ([uint64]4 -shl 12) -bor [uint64]$headerVersion
    $coreLines.Add("VK_HEADER_VERSION := $headerVersion")
    $coreLines.Add("VK_HEADER_VERSION_COMPLETE := $headerComplete")
}
$coreLines.Add('struc VK_MAKE_API_VERSION variant*,major*,minor*,patch*')
$coreLines.Add("`t. := (variant shl 29) or (major shl 22) or (minor shl 12) or patch")
$coreLines.Add('end struc')
$coreLines.Add('struc VK_MAKE_VERSION major*,minor*,patch*')
$coreLines.Add("`t. := (major shl 22) or (minor shl 12) or patch")
$coreLines.Add('end struc')
foreach ($name in (Sort-Names $coreEnumNames)) { Add-EnumDefinition $coreLines $name }
Add-TypeDefinitions $coreLines $coreTypes
Add-LoaderFunctions $coreLines $coreCommands
Write-Lines (Join-Path $Output 'core.inc') $coreLines

# Every function as an export of vulkan-1.dll, whether the library exports it
# or not.  An import library made from this lets the linker's delay-load
# mechanism carry all of them; loader\delay.asm supplies the addresses.
$exportLines = New-Lines
$exportLines.Add('; Every function of the projection. Generated from vk.xml; do not edit.')
$exportLines.Add('LIBRARY vulkan-1.dll')
$exportLines.Add('EXPORTS')
foreach ($name in (Sort-Names (@($coreCommands) + @($commandOwner.Keys)))) { $exportLines.Add("`t$name") }
Write-Lines (Join-Path $Output 'vulkan-1.def') $exportLines

foreach ($name in $moduleNode.Keys) {
    $node = $moduleNode[$name]
    $lines = New-Lines
    if ($moduleKind[$name] -eq 'video') {
        $lines.Add("; $name.h. Generated from video.xml; do not edit.")
    } else {
        $lines.Add("; $name, $([string]$node.GetAttribute('type')) extension $($moduleNumber[$name]). Generated from vk.xml; do not edit.")
        foreach ($attribute in @('depends','promotedto','deprecatedby','obsoletedby')) {
            $value = [string]$node.GetAttribute($attribute)
            if ($value) { $lines.Add("; ${attribute}: $value") }
        }
    }
    foreach ($dependency in (Sort-Names $includeFirst[$name])) {
        $lines.Add("; needs $includeRoot/$($moduleFile[$dependency])")
    }
    if ($elsewhere.ContainsKey($name)) {
        foreach ($owner in (Sort-Names $elsewhere[$name].Keys)) {
            $lines.Add("; in $includeRoot/$($moduleFile[$owner]): $((Sort-Names $elsewhere[$name][$owner]) -join ', ')")
        }
    }
    foreach ($require in (Get-VulkanRequires $node)) {
        foreach ($type in @($require.type)) {
            if ([string]$type.name -ceq 'VK_MAKE_VIDEO_STD_VERSION') {
                $lines.Add('struc VK_MAKE_VIDEO_STD_VERSION major*,minor*,patch*')
                $lines.Add("`t. := (major shl 22) or (minor shl 12) or patch")
                $lines.Add('end struc')
            }
        }
    }
    foreach ($enumName in (Sort-Names $ownedEnums[$name])) { Add-EnumDefinition $lines $enumName }
    Add-TypeDefinitions $lines $ownedTypes[$name]
    Add-LoaderFunctions $lines $ownedCommands[$name]
    Write-Lines (Join-Path $Output ($moduleFile[$name] -replace '/','\')) $lines
}

# ---------------------------------------------------------------------------
# Testing artifacts

$projectedRecords = New-NameSet
foreach ($name in $coreTypes) { if ($recordLayouts.ContainsKey($name)) { [void]$projectedRecords.Add($name) } }
foreach ($name in $typeOwner.Keys) { if ($recordLayouts.ContainsKey($name)) { [void]$projectedRecords.Add($name) } }

# The projection states layouts instead of deriving them, so the asserts that
# hold fasmg's view of every struct to the computed layout live with the tests.
$assertLines = New-Lines
$assertLines.Add('; Layout of every projected record. Generated from vk.xml; do not edit.')
$assertLines.Add("; Valid after $testRoot/everything.inc.")
foreach ($name in (Sort-Names $projectedRecords)) {
    $layout = $recordLayouts[$name]
    $assertLines.Add("assert sizeof.$name = $($layout.Size)")
    foreach ($member in @($layout.Members)) { $assertLines.Add("assert $name.$($member.Name) = $($member.Offset)") }
}
Write-Lines (Join-Path $TestOutput 'layout_asserts.inc') $assertLines

$everythingLines = New-Lines
$everythingLines.Add('; The whole projection, dependencies first. Generated from vk.xml; do not edit.')
$everythingLines.Add("include '$includeRoot/core.inc'")
foreach ($name in $includeOrder) { $everythingLines.Add("include '$includeRoot/$($moduleFile[$name])'") }
Write-Lines (Join-Path $TestOutput 'everything.inc') $everythingLines

$layoutLines = New-Lines
foreach ($name in (Sort-Names $projectedRecords)) {
    $layout = $recordLayouts[$name]
    $kind = if ($layout.Union) { 'union' } else { 'struct' }
    $layoutLines.Add("$kind|$name|$($layout.Size)|$($layout.Align)")
    foreach ($member in @($layout.Members)) { $layoutLines.Add("member|$name|$($member.Name)|$($member.Offset)|$($member.Size)") }
    foreach ($field in @($layout.Bitfields)) { $layoutLines.Add("bitfield|$name|$($field.Name)|$($field.Bit)|$($field.Width)") }
}
Write-Lines (Join-Path $TestOutput 'layouts.txt') $layoutLines
Write-Lines (Join-Path $TestOutput 'unsupported-types.txt') (Sort-Names $failedRecords.Keys)

$constantLines = New-Lines
foreach ($name in (Sort-Names $coreEnumNames)) {
    if ($enumValues.ContainsKey($name)) { $constantLines.Add("constant|core|$name|$($enumValues[$name])") }
}
foreach ($moduleName in (Sort-Names $moduleNode.Keys)) {
    foreach ($name in (Sort-Names $ownedEnums[$moduleName])) {
        if ($enumValues.ContainsKey($name)) { $constantLines.Add("constant|$moduleName|$name|$($enumValues[$name])") }
    }
}
Write-Lines (Join-Path $TestOutput 'constants.txt') $constantLines

# Everything the single-owner rule had to decide, for review.
$unownedConstants = New-Lines
foreach ($name in (Sort-Names (@($enumValues.Keys) + @($stringConstants.Keys)))) {
    if (-not $coreEnumNames.Contains($name) -and -not $enumOwner.ContainsKey($name)) { $unownedConstants.Add($name) }
}
$unownedRecords = New-Lines
foreach ($name in (Sort-Names $recordLayouts.Keys)) {
    if (-not $projectedRecords.Contains($name)) { $unownedRecords.Add($name) }
}
$orderLines = New-Lines
foreach ($name in (Sort-Names $moduleNode.Keys)) {
    if (-not $includeFirst[$name].Count) { continue }
    $files = New-Lines
    foreach ($dependency in $includeFirst[$name]) { $files.Add($moduleFile[$dependency]) }
    $orderLines.Add("$($moduleFile[$name]): $((Sort-Names $files) -join ', ')")
}
$reportLines = New-Lines
$reportLines.Add("Vulkan projection report. Generated from vk.xml; do not edit.")
$reportLines.Add('')
$reportLines.Add("[needed files] $($orderLines.Count) files embed a struct another file defines: file: needs")
foreach ($line in (Sort-Names $orderLines)) { $reportLines.Add($line) }
$reportLines.Add('')
$reportLines.Add("[needed files] $($includeCycles.Count) cycles, which no include order can satisfy in one pass")
foreach ($line in $includeCycles) { $reportLines.Add($line) }
$reportLines.Add('')
$reportLines.Add("[shared definitions] $($sharedDefinitions.Count) required by more than one module: kind|name|defining file|also required by")
foreach ($line in (Sort-Names $sharedDefinitions)) { $reportLines.Add($line) }
$reportLines.Add('')
$reportLines.Add("[unresolved records] $($failedRecords.Count) left out: a member type belongs to a platform header with no Windows x64 ABI")
foreach ($line in (Sort-Names $failedRecords.Keys)) { $reportLines.Add($line) }
$reportLines.Add('')
$reportLines.Add("[unrequired records] $($unownedRecords.Count) resolved but named by no enabled feature or extension")
foreach ($line in $unownedRecords) { $reportLines.Add($line) }
$reportLines.Add('')
$reportLines.Add("[unrequired constants] $($unownedConstants.Count) valued but named by no enabled feature or extension")
foreach ($line in $unownedConstants) { $reportLines.Add($line) }
Write-Lines (Join-Path $TestOutput 'report.txt') $reportLines

$count = { param($table) ($table.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum }
$classCounts = $classes.Values | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
$extensionCount = @($moduleKind.Values | Where-Object { $_ -eq 'extension' }).Count
Write-Host "[vk] core: $($coreCommands.Count) functions, $($coreTypes.Count) types, $($coreEnumNames.Count) constants"
Write-Host "[vk] $extensionCount extension and $($moduleNode.Count - $extensionCount) video files: $(& $count $ownedCommands) functions, $(& $count $ownedTypes) types, $(& $count $ownedEnums) constants ($($classCounts -join ', '))"
Write-Host "[vk] $($outputDirectories.Count - 1) author directories, $($sharedDefinitions.Count) shared definitions given one owner, $($orderLines.Count) files that need another file; see $testRoot/report.txt"
if ($failedRecords.Count) { Write-Host "[vk] skipped $($failedRecords.Count) unresolved record layouts" }
