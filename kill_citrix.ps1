# Kill-Citrix.ps1
# Completely kills all Citrix Receiver/Workspace related processes.
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$PSCommandPath';`"";
    exit;
}

$processNames = @(
    "Receiver",
    "AuthManSvr",
    "SelfService",
    "SelfServicePlugin",
    "CtxWebBrowser",
    "wfcrun32",
    "Concentr",
    "CDViewer",
    "wfica32",
    "CtxCms",
    "CtxTwnPA",
    "CtxDps",
    "CtxSvcHost",
    "FlashContainer" 
)

Write-Host "Stopping Citrix processes..." -ForeColor Cyan

foreach ($name in $processNames) {
    $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($processes) {
        foreach ($proc in $processes) {
            try {
                Stop-Process -InputObject $proc -Force -ErrorAction Stop
                Write-Host "Stopped: $($proc.ProcessName) (ID: $($proc.Id))" -ForeColor Green
            }
            catch {
                Write-Host "Failed to stop: $($proc.ProcessName) (ID: $($proc.Id)) - $($_.Exception.Message)" -ForeColor Red
            }
        }
    }
}

# Check if any remain
$remaining = Get-Process -Name $processNames -ErrorAction SilentlyContinue
if ($remaining) {
    Write-Host "Some processes could not be stopped. You may need to run as Administrator." -ForeColor Yellow
}
else {
    Write-Host "All Citrix processes stopped." -ForeColor Green
}

# --- MSI Cleanup for Citrix Self-Repair Bug ---
Write-Host "Clearing stuck Windows Installer processes (Citrix self-repair bug)..." -ForeColor Cyan
Stop-Process -Name "msiexec" -Force -ErrorAction SilentlyContinue

# --- RDP / TermService Cleanup to prevent mstsc.exe from hanging ---
Write-Host "Cleaning up potentially deadlocked RDP client processes..." -ForeColor Cyan
Stop-Process -Name "mstsc", "msrdc" -Force -ErrorAction SilentlyContinue

Write-Host "Restarting Remote Desktop Service (TermService) to release hooks..." -ForeColor Cyan
Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue

Write-Host "RDP services and clients have been reset. You should now be able to open RDP." -ForeColor Green

# Optional: Restart Citrix Workspace Helper if needed
# Start-Process "C:\Program Files (x86)\Citrix\ICA Client\SelfServicePlugin\SelfService.exe" -ArgumentList "-logon"
