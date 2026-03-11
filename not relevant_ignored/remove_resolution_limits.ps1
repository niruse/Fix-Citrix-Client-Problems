# Remove-ResolutionLimits.ps1
# Removes Windows Desktop metrics that might be limiting window size to 3440.
# Specifically targets "MaxMonitorDimension" found in registry analysis.

Write-Host "Checking for stuck resolution limits..." -ForeColor Cyan

# 1. MaxMonitorDimension
$desktopKey = "HKCU:\Control Panel\Desktop"
$valName = "MaxMonitorDimension"

if ((Get-ItemProperty -Path $desktopKey -Name $valName -ErrorAction SilentlyContinue)) {
    Write-Host "Found '$valName' in $desktopKey." -ForeColor Red
    try {
        Remove-ItemProperty -Path $desktopKey -Name $valName -ErrorAction Stop
        Write-Host "   [REMOVED] MaxMonitorDimension check." -ForeColor Green
    }
    catch {
        Write-Host "   [FAILED] Could not remove key: $_" -ForeColor Red
    }
}
else {
    Write-Host "'$valName' not found (already clean)." -ForeColor Gray
}

# 2. VirtualScreen (SystemMetrics)
# Sometimes systemic metrics get cached. 
# We can't delete SystemMetrics widely, but we can check for overrides.

# 3. Explorer Window Placement Caches (StuckRects3)
$stuckKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
if (Test-Path $stuckKey) {
    Write-Host "Clearing Explorer Window Placement Cache (StuckRects3)..." -ForeColor Yellow
    Remove-Item -Path $stuckKey -Force -Recurse -ErrorAction SilentlyContinue
    # Restart Explorer to regenerate? Maybe not needed for Citrix, but good for cleanliness.
}

Write-Host "Cleanup Complete. Please restart Citrix Workspace." -ForeColor Cyan
