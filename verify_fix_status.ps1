# Verify-FixStatus.ps1
# Checks Citrix configuration health: MaxMonitorDimension, Compatibility Flags,
# DPI Awareness, and Alt-Tab Hotkey Passthrough (CTX232298).

$allGood = $true

Write-Host "--- Citrix Resolution & Configuration Verification ---" -ForegroundColor Cyan

# 1. Check MaxMonitorDimension (Must be GONE)
$desktopKey = "HKCU:\Control Panel\Desktop"
$valName = "MaxMonitorDimension"
if ((Get-ItemProperty -Path $desktopKey -Name $valName -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] 'MaxMonitorDimension' still exists!" -ForegroundColor Red
    $allGood = $false
}
else {
    Write-Host "[PASS] 'MaxMonitorDimension' is removed." -ForegroundColor Green
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
    Write-Host "[FAIL] Citrix Compatibility flags found." -ForegroundColor Red
    $allGood = $false
}
else {
    Write-Host "[PASS] No Citrix Compatibility flags found." -ForegroundColor Green
}

# 3. Check DPI Setting (Should be 1)
$dpiKey = "HKCU:\Software\Citrix\ICA Client\DPI"
$dpi = (Get-ItemProperty -Path $dpiKey -Name "DpiAware" -ErrorAction SilentlyContinue).DpiAware
if ($dpi -eq 1) {
    Write-Host "[PASS] DPI Awareness is set (DpiAware=1)." -ForegroundColor Green
}
else {
    Write-Host "[WARN] DPI Awareness is NOT set (Result: $dpi)." -ForegroundColor Yellow
}

# 4. Check Alt-Tab Hotkey Passthrough (CTX232298)
$altTabKey = "HKCU:\Software\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
$altVal = (Get-ItemProperty -Path $altTabKey -Name "TransparentKeyPassthrough" -ErrorAction SilentlyContinue).TransparentKeyPassthrough
if ($altVal -eq "remote") {
    Write-Host "[PASS] Alt-Tab hotkey passthrough is enabled (TransparentKeyPassthrough=remote)." -ForegroundColor Green
}
else {
    Write-Host "[WARN] Alt-Tab hotkey passthrough is NOT set to 'remote' (Current: '$altVal')." -ForegroundColor Yellow
}

Write-Host "------------------------------------------"
if ($allGood) {
    Write-Host "Configuration looks CLEAN." -ForegroundColor Green
    Write-Host "CRITICAL NEXT STEP: If you experienced resolution issues, you must SIGN OUT of the remote Windows session." -ForegroundColor Yellow
    Write-Host "   (Do not just close the Citrix window. Click Start -> User -> Sign Out inside the remote desktop)" -ForegroundColor Yellow
}
else {
    Write-Host "Some settings are still incorrect. Please run 'kill_citrix.ps1' or the respective repair script." -ForegroundColor Red
}

if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
    Write-Host "Press any key to exit..."
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}
}
