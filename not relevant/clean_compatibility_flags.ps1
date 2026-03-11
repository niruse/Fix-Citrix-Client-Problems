# Clean-CompatibilityFlags.ps1
# Removes Windows "AppCompat" flags that override DPI settings for Citrix.
# This fixes cases where specific users have "Overridden High DPI scaling behavior" checked in properties.

# Check for Admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Host "Running as Standard User (checking HKCU)." -ForeColor Cyan
}
else {
    Write-Host "Running as Administrator (checking HKCU + HKLM)." -ForeColor Green
}

$citrixExes = @("wfica32.exe", "wfcrun32.exe", "SelfService.exe", "CDViewer.exe", "Concentr.exe")
$registries = @("HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers")

if ($isAdmin) {
    $registries += "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
}

Write-Host "Scanning for Compatibility Flags..." -ForeColor Cyan

foreach ($regPath in $registries) {
    if (Test-Path $regPath) {
        Write-Host "Checking: $regPath" -ForeColor DarkGray
        
        # Get all values in the key
        try {
            $properties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            
            # Since Get-ItemProperty returns an object with properties for each entry, we iterate names
            foreach ($prop in $properties.PSObject.Properties) {
                $exePath = $prop.Name
                $flags = $prop.Value

                # Check if this entry applies to a Citrix executable
                foreach ($citrixExe in $citrixExes) {
                    if ($exePath -match [regex]::Escape($citrixExe)) {
                        Write-Host "FOUND FLAG: $citrixExe" -ForeColor Red
                        Write-Host "   Path: $exePath" -ForeColor Yellow
                        Write-Host "   Flags: $flags" -ForeColor Yellow
                        
                        # Remove the entry
                        try {
                            Remove-ItemProperty -Path $regPath -Name $exePath -ErrorAction Stop
                            Write-Host "   [REMOVED]" -ForeColor Green
                        }
                        catch {
                            Write-Host "   [FAILED TO REMOVE]: $_" -ForeColor Red
                        }
                    }
                }
            }
        }
        catch {
            Write-Host "Error reading key: $_" -ForeColor Red
        }
    }
}

Write-Host "Scan Complete." -ForeColor Cyan
Write-Host "1. If any flags were removed, restart Citrix Workspace."
Write-Host "2. If nothing was found, your registry is clean of these specific overrides."
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
