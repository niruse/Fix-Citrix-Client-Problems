# Fix-CitrixResolution.ps1
# Fixes Citrix Workspace high DPI/resolution issues by forcing DPI awareness.

# Check for Admin privileges (for HKLM and Process Killing)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (!$isAdmin) {
    Write-Host "Running as Standard User (HKCU will be updated)." -ForeColor Yellow
    Write-Host "Note: For HKLM changes or killing stubborn processes, run as Administrator." -ForeColor DarkGray
}
else {
    Write-Host "Running as Administrator." -ForeColor Green
}

# --- 1. Kill Citrix Processes (Imported logic) ---
$processNames = @(
    "Receiver", "AuthManSvr", "SelfService", "SelfServicePlugin", "CtxWebBrowser",
    "wfcrun32", "Concentr", "CDViewer", "wfica32", "CtxCms", "CtxTwnPA",
    "CtxDps", "CtxSvcHost", "FlashContainer"
)

Write-Host "Stopping Citrix processes..." -ForeColor Cyan
foreach ($name in $processNames) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# --- 2. Apply DPI Registry Fix ---
Write-Host "Applying Registry Fixes for High DPI..." -ForeColor Cyan

# Current User Key
$hkcuPath = "HKCU:\Software\Citrix\ICA Client\DPI"
if (!(Test-Path $hkcuPath)) {
    New-Item -Path $hkcuPath -Force | Out-Null
}
# Set DpiAware to 1 (Enabled) to match client resolution
Set-ItemProperty -Path $hkcuPath -Name "DpiAware" -Value 1 -Type DWord -Force
Write-Host "Set HKCU DpiAware to 1" -ForeColor Green

# Local Machine Key (Policy) - often overrides User settings
$hklmPath = "HKLM:\SOFTWARE\Policies\Citrix\ICA Client\DPI"
if (!(Test-Path $hklmPath)) {
    # Attempt to create if it doesn't exist (requires Admin)
    try {
        New-Item -Path $hklmPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "Could not create HKLM policy key (might need manual Admin check): $_" -ForeColor Yellow
    }
}

if (Test-Path $hklmPath) {
    Set-ItemProperty -Path $hklmPath -Name "DpiAware" -Value 1 -Type DWord -Force
    Write-Host "Set HKLM DpiAware to 1" -ForeColor Green
}

Write-Host "Registry settings updated." -ForeColor Cyan
Write-Host "Please restart Citrix Workspace." -ForeColor Green
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
