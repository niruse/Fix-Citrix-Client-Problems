# Hard-Reset-Citrix.ps1
# WARNING: This script performs a destructive reset of local Citrix Workspace preferences.
# It deletes local configuration files and user registry settings.
# You will likely need to re-enter your Store URL and credentials.

# Check for Admin privileges (Optional but good for killing global processes)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Host "Running as Standard User." -ForeColor Cyan
}
else {
    Write-Host "Running as Administrator." -ForeColor Green
}

# --- 1. Backup Registry (Just in case) ---
$backupPath = "$HOME\Desktop\Citrix_HKCU_Backup_$(Get-Date -Format 'yyyyMMdd_HHmm').reg"
Write-Host "Backing up HKCU\Software\Citrix to $backupPath..." -ForeColor Cyan
reg export "HKCU\Software\Citrix" $backupPath /y
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Could not backup registry. Proceeding anyway..." -ForeColor Yellow
}

# --- 2. Kill Citrix Processes ---
$processNames = @(
    "Receiver", "AuthManSvr", "SelfService", "SelfServicePlugin", "CtxWebBrowser",
    "wfcrun32", "Concentr", "CDViewer", "wfica32", "CtxCms", "CtxTwnPA",
    "CtxDps", "CtxSvcHost", "FlashContainer"
)

Write-Host "Stopping Citrix processes..." -ForeColor Cyan
foreach ($name in $processNames) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# --- 3. Clean File System ---
$dirsToClean = @(
    "$env:APPDATA\Citrix",
    "$env:LOCALAPPDATA\Citrix"
)

foreach ($dir in $dirsToClean) {
    if (Test-Path $dir) {
        Write-Host "Removing directory: $dir" -ForeColor Yellow
        try {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Host "Failed to remove $dir logic. Close any open Citrix apps." -ForeColor Red
        }
    }
}

# --- 4. Clean Registry ---
$regPath = "HKCU:\Software\Citrix"
if (Test-Path $regPath) {
    Write-Host "Removing Registry Key: $regPath" -ForeColor Yellow
    try {
        Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to remove registry key. You may need permissions." -ForeColor Red
    }
}

# --- 5. Re-Apply Basic High DPI Fix ---
# Since we deleted the key, we need to recreate the folder structure for the fix
$dpiKey = "HKCU:\Software\Citrix\ICA Client\DPI"
if (!(Test-Path $dpiKey)) {
    New-Item -Path $dpiKey -Force | Out-Null
}
Set-ItemProperty -Path $dpiKey -Name "DpiAware" -Value 1 -Type DWord -Force
Write-Host "Restored High DPI setting (DpiAware=1)." -ForeColor Green

# --- 6. Reset FullScreen preference ---
$icaClientKey = "HKCU:\Software\Citrix\ICA Client"
if (Test-Path $icaClientKey) {
    Set-ItemProperty -Path $icaClientKey -Name "UseFullScreen" -Value 0 -Type DWord -Force
    Write-Host "Set specific Windowed Mode preference." -ForeColor Green
}

Write-Host "Hard Reset Complete." -ForeColor Cyan
Write-Host "1. Restart your computer (highly recommended) or just start Citrix Workspace."
Write-Host "2. You may be asked to 'Add Account'. Enter your Store URL."
Write-Host "3. Log in and launch your session."
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
