# Verify-FixStatus.ps1
# Checks if the critical "MaxMonitorDimension" key is really gone and status of other fixes.

$allGood = $true

Write-Host "--- Citrix Resolution Fix Verification ---" -ForeColor Cyan

# 1. Check MaxMonitorDimension (Must be GONE)
$desktopKey = "HKCU:\Control Panel\Desktop"
$valName = "MaxMonitorDimension"
if ((Get-ItemProperty -Path $desktopKey -Name $valName -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] 'MaxMonitorDimension' still exists!" -ForeColor Red
    $allGood = $false
}
else {
    Write-Host "[PASS] 'MaxMonitorDimension' is removed." -ForeColor Green
}

# 2. Check Compatibility Flags (Must be CLEAN)
$compatKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
$citrixFlags = $false
if (Test-Path $compatKey) {
    Get-ItemProperty -Path $compatKey | ForEach-Object {
        if ("$($_.PSObject.Properties.Value)" -match "Citrix|wfica32|wfcrun32") {
           $citrixFlags = $true
        }
    }
}
if ($citrixFlags) {
    Write-Host "[FAIL] Citrix Compatibility flags found." -ForeColor Red
    $allGood = $false
}
else {
    Write-Host "[PASS] No Citrix Compatibility flags found." -ForeColor Green
}

# 3. Check DPI Setting (Should be 1)
$dpiKey = "HKCU:\Software\Citrix\ICA Client\DPI"
$dpi = (Get-ItemProperty -Path $dpiKey -Name "DpiAware" -ErrorAction SilentlyContinue).DpiAware
if ($dpi -eq 1) {
    Write-Host "[PASS] DPI Awareness is set (DpiAware=1)." -ForeColor Green
}
else {
    Write-Host "[WARN] DPI Awareness is NOT set (Result: $dpi)." -ForeColor Yellow
    # Not a hard fail, but recommended
}

Write-Host "------------------------------------------"
if ($allGood) {
    Write-Host "Configuration looks CLEAN." -ForeColor Green
    Write-Host "CRITICAL NEXT STEP: You must SIGN OUT of the remote Windows session." -ForeColor Yellow
    Write-Host "   (Do not just close the Citrix window. Click Start -> User -> Sign Out inside the remote desktop)" -ForeColor Yellow
}
else {
    Write-Host "Some settings are still incorrect. Please run the 'remove_resolution_limits.ps1' script again." -ForeColor Red
}
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
