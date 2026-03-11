# Reset-CitrixResolution.ps1
# Clears locked/stuck resolution settings from the Registry to force Citrix to re-negotiate.

# Check for Admin privileges (Process Killing benefit, though HKCU is the target)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Host "Running as Standard User (recommended for HKCU cleanup)." -ForeColor Cyan
}
else {
    Write-Host "Running as Administrator." -ForeColor Green
}

# --- 1. Kill Citrix Processes ---
$processNames = @(
    "Receiver", "AuthManSvr", "SelfService", "SelfServicePlugin", "CtxWebBrowser",
    "wfcrun32", "Concentr", "CDViewer", "wfica32", "CtxCms", "CtxTwnPA",
    "CtxDps", "CtxSvcHost", "FlashContainer"
)

Write-Host "Stopping Citrix processes..." -ForeColor Cyan
foreach ($name in $processNames) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

# --- 2. Remove Stuck Resolution Keys ---
$basePath = "HKCU:\Software\Citrix\ICA Client"
$keysToDelete = @("DesiredHRES", "DesiredVRES", "ScreenPercent", "SessionSize", "LastWindowSize")

Write-Host "Scanning for stuck resolution keys in $basePath..." -ForeColor Cyan

# Recursive function to delete specific values
function Remove-ResValues {
    param (
        [string]$Path
    )
    
    # Check current key properties
    try {
        $properties = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
        if ($properties) {
            foreach ($key in $keysToDelete) {
                if ($properties.$key) {
                    Remove-ItemProperty -Path $Path -Name $key -ErrorAction SilentlyContinue
                    Write-Host "Removed '$key' from $Path" -ForeColor Yellow
                }
            }
            
            # Reset UseFullScreen to 0 (False) to force windowed mode initially, triggering resize
            if ($properties.UseFullScreen) {
                Set-ItemProperty -Path $Path -Name "UseFullScreen" -Value 0 -Force
                Write-Host "Reset 'UseFullScreen' to 0 in $Path" -ForeColor Yellow
            }
        }
    }
    catch {}

    # Recurse into subkeys
    $subkeys = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue
    foreach ($subkey in $subkeys) {
        Remove-ResValues -Path $subkey.PSPath
    }
}

if (Test-Path $basePath) {
    Remove-ResValues -Path $basePath
}

# --- 3. Ensure DPI Aware is ON ---
$dpiPath = "$basePath\DPI"
if (!(Test-Path $dpiPath)) { New-Item -Path $dpiPath -Force | Out-Null }
Set-ItemProperty -Path $dpiPath -Name "DpiAware" -Value 1 -Type DWord -Force
Write-Host "Ensured DpiAware is 1." -ForeColor Green

Write-Host "Cleanup Complete." -ForeColor Cyan
Write-Host "1. Restart Citrix Workspace."
Write-Host "2. Launch your desktop/app."
Write-Host "3. If it starts in Windowed mode, Maximize it to prompt a resolution update."
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
