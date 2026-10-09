# Shared binary assertions for both recipes; dot-sourced by their GPU checks.
function Assert-RecipeBinaryLayout([string]$Executable, [string]$BssGroup) {
    $object = [IO.File]::ReadAllBytes([IO.Path]::ChangeExtension($Executable, 'obj'))
    # NEWCOFF emits BigObj; also accept conventional COFF header/symbol sizes.
    if ([BitConverter]::ToUInt16($object,0) -eq 0 -and [BitConverter]::ToUInt16($object,2) -eq 0xffff) {
        $headerSize = 56
        $sectionCount = [BitConverter]::ToUInt32($object,44)
        $strings = [BitConverter]::ToUInt32($object,48) + 20*[BitConverter]::ToUInt32($object,52)
    } else {
        $headerSize = 20
        $sectionCount = [BitConverter]::ToUInt16($object,2)
        $strings = [BitConverter]::ToUInt32($object,8) + 18*[BitConverter]::ToUInt32($object,12)
    }
    $objectSections = @(for ($i=0; $i -lt $sectionCount; $i++) {
        $offset = $headerSize + 40*$i
        $name = [Text.Encoding]::ASCII.GetString($object,$offset,8).Trim([char]0)
        if ($name.StartsWith('/')) {
            $start = $strings + [int]$name.Substring(1)
            $end = $start
            while ($object[$end]) { $end++ }
            $name = [Text.Encoding]::ASCII.GetString($object,$start,$end-$start)
        }
        [pscustomobject]@{
            Name=$name; Size=[BitConverter]::ToUInt32($object,$offset+16)
            Raw=[BitConverter]::ToUInt32($object,$offset+20)
            Flags=[BitConverter]::ToUInt32($object,$offset+36)
        }
    })
    foreach ($section in ($objectSections | Where-Object Name -like '.bss*')) {
        if ($section.Raw -or -not ($section.Flags -band 0x80) -or ($section.Flags -band 0x40)) {
            throw "$($section.Name) serialized initialized bytes instead of reserving BSS"
        }
    }
    $reserved = @($objectSections | Where-Object Name -eq $BssGroup)
    # Long-lived resource/diagnostic state fits comfortably in one page.
    # Startup enumeration/query arrays must not return to persistent storage.
    if ($reserved.Count -ne 1 -or $reserved[0].Size -gt 4096) {
        throw "$BssGroup retains large startup scratch instead of scoped procedure storage"
    }

    $bytes = [IO.File]::ReadAllBytes($Executable)
    $pe = [BitConverter]::ToInt32($bytes,0x3c)
    $imageBase = [BitConverter]::ToInt64($bytes,$pe+48)
    $table = $pe+24+[BitConverter]::ToUInt16($bytes,$pe+20)
    $sections = @(for ($i=0; $i -lt [BitConverter]::ToUInt16($bytes,$pe+6); $i++) {
        $offset = $table+40*$i
        [pscustomobject]@{
            Name=[Text.Encoding]::ASCII.GetString($bytes,$offset,8).Trim([char]0)
            VirtualSize=[BitConverter]::ToUInt32($bytes,$offset+8)
            Address=$imageBase+[BitConverter]::ToUInt32($bytes,$offset+12)
            Size=[BitConverter]::ToUInt32($bytes,$offset+16)
            Raw=[BitConverter]::ToUInt32($bytes,$offset+20)
            Code=([BitConverter]::ToUInt32($bytes,$offset+36) -band 0x20) -ne 0
        }
    })
    $data = $sections | Where-Object Name -eq '.data'
    if ($data.VirtualSize-$data.Size -lt $reserved[0].Size-512) {
        throw 'PE data lost the reserved zero-filled tail or serialized it into the file'
    }

    $calls = @{}
    foreach ($line in (Get-Content -LiteralPath ([IO.Path]::ChangeExtension($Executable,'map')))) {
        if ($line -match '^\s*\d{4}:[0-9a-f]{8}\s+(\S+)\s+([0-9a-f]{16})\s+(?:f\s+)?(?:kernel32:KERNEL32.dll|user32:USER32.dll)\s*$') {
            if ($Matches[1] -notlike '__imp_*') {
                $address = [Convert]::ToInt64($Matches[2],16)
                if ($sections | Where-Object { $_.Code -and $address -ge $_.Address -and $address -lt $_.Address+$_.Size }) {
                    throw "Implicit named Win32 thunk: $($Matches[1])"
                }
                continue # Import descriptors and null terminators are metadata.
            }
            $calls[$Matches[2]] = [pscustomobject]@{Name=$Matches[1]; Count=0}
        }
    }
    if (-not $calls.Count) { throw 'No Win32 IAT symbols found in the recipe map' }
    foreach ($section in ($sections | Where-Object Code)) {
        for ($i=0; $i -le $section.Size-6; $i++) {
            $offset = [int]($section.Raw+$i)
            if ($bytes[$offset] -ne 0xff -or $bytes[$offset+1] -ne 0x15) { continue }
            $target = $section.Address+$i+6+[BitConverter]::ToInt32($bytes,$offset+2)
            $key = '{0:x16}' -f $target
            if ($calls.ContainsKey($key)) { $calls[$key].Count++ }
        }
    }
    foreach ($entry in $calls.Values) {
        if (-not $entry.Count) { throw "$($entry.Name) has no direct IAT call instruction" }
    }
    $count = ($calls.Values | Measure-Object -Property Count -Sum).Sum
    Write-Host "[binary] $BssGroup reserves $($reserved[0].Size) bytes; Win32: $count IAT call sites, $($calls.Count) imports, no named thunks; executable $($bytes.Length) bytes"
}
