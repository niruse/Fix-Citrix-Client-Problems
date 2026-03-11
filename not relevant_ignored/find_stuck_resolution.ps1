# Find-StuckResolution.ps1
# Searches the entire HKCU Registry hive for the value "3440" AND byte sequence 0xD70 (3440).
# Targets binary blobs where resolution is often stored.

$searchValueString = "3440"
# 3440 in Hex is 0x0D70. Little Endian byte sequence: 70 0D
# We look for this sequence in binary arrays.
$searchBytes = @(0x70, 0x0D) 

Write-Output "Searching entire HKCU for keys/values containing '3440' or binary '70 0D'..."

$root = "HKCU:\" 
# Excluding already searched or huge hives if needed, but let's do root.
# Note: Iterating HKCU:\ can be slow and hit permission issues. We'll try.

$foundCount = 0

Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $key = $_
    
    # 1. Check Property Values
    foreach ($propName in $key.Property) {
        try {
            $val = $key.GetValue($propName)
            
            # CHECK STRING MATCH
            if ("$val" -match $searchValueString) {
                Write-Output "MATCH FOUND [String]"
                Write-Output "   Key: $($key.PSPath)"
                Write-Output "   Property: $propName"
                Write-Output "   Value: $val"
                $foundCount++
            }
            
            # CHECK BINARY MATCH (if byte array)
            if ($val -is [byte[]]) {
                # Simple check for the sequence
                for ($i = 0; $i -lt ($val.Length - 1); $i++) {
                    if ($val[$i] -eq $searchBytes[0] -and $val[$i + 1] -eq $searchBytes[1]) {
                        Write-Output "MATCH FOUND [Binary]"
                        Write-Output "   Key: $($key.PSPath)"
                        Write-Output "   Property: $propName"
                        Write-Output "   Value (Hex): $([BitConverter]::ToString($val, $i, 2)) (at index $i)"
                        $foundCount++
                        break # Found one match in this property, move on
                    }
                }
            }

        }
        catch {}
    }

    # 2. Check Key Names
    if ($key.PSChildName -match $searchValueString) {
        Write-Output "MATCH FOUND [KeyName]"
        Write-Output "   Key: $($key.PSPath)"
        $foundCount++
    }
}

Write-Output "Search Complete. Found $foundCount matches."
