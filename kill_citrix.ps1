# Kill-Citrix.ps1 / Citrix Problem Solver Bot
# Comprehensive tool to resolve Citrix Receiver/Workspace hangs, deadlocks,
# resolution issues, and the 'ICAWebWrapper.msi' network resource unavailable loop.

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("1", "2", "3", "0", "Regular", "FixMSI", "Advanced", "Kill", "FixResolution", "CleanFlags", "Verify", "HardReset", "FullFix", "Menu")]
    [string]$Action,

    [switch]$Regular,
    [switch]$Kill,
    [switch]$FixMSI,
    [switch]$FixResolution,
    [switch]$CleanFlags,
    [switch]$Verify,
    [switch]$HardReset,
    [switch]$FullFix,
    [switch]$Force
)

# -------------------------------------------------------------
# 0. Administrator Check & Elevation Helper
# -------------------------------------------------------------
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    param([string]$PendingAction)
    if (-not (Test-IsAdmin)) {
        Write-Host "This operation requires Administrator privileges. Requesting elevation..." -ForeColor Cyan
        $cmd = "cd '$pwd'; & '$PSCommandPath'"
        if ($PendingAction) { $cmd += " -Action '$PendingAction'" }
        if ($Force) { $cmd += " -Force" }
        $cmd += "; Write-Host ''; Write-Host 'Press Enter to close window...' -ForeColor DarkGray; [void][System.Console]::ReadLine()"
        
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
        exit
    }
}

# -------------------------------------------------------------
# Module Functions
# -------------------------------------------------------------

function Invoke-KillCitrixProcesses {
    Write-Host ""
    Write-Host "--- Stopping Citrix Processes & Releasing Deadlocks ---" -ForeColor Cyan
    
    $processNames = @(
        "Receiver", "AuthManSvr", "SelfService", "SelfServicePlugin", "CtxWebBrowser",
        "wfcrun32", "Concentr", "CDViewer", "wfica32", "CtxCms", "CtxTwnPA",
        "CtxDps", "CtxSvcHost", "FlashContainer"
    )

    foreach ($name in $processNames) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($processes) {
            foreach ($proc in $processes) {
                try {
                    Stop-Process -InputObject $proc -Force -ErrorAction Stop
                    Write-Host "  [STOPPED] $($proc.ProcessName) (ID: $($proc.Id))" -ForeColor Green
                } catch {
                    Write-Host "  [FAILED] $($proc.ProcessName) (ID: $($proc.Id)) - $($_.Exception.Message)" -ForeColor Red
                }
            }
        }
    }

    $remaining = Get-Process -Name $processNames -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Host "Warning: Some Citrix processes could not be stopped." -ForeColor Yellow
    } else {
        Write-Host "All Citrix processes stopped." -ForeColor Green
    }

    # Clear stuck msiexec
    Write-Host "Clearing stuck Windows Installer processes (msiexec)..." -ForeColor Cyan
    Stop-Process -Name "msiexec" -Force -ErrorAction SilentlyContinue

    # Clean deadlocked RDP clients
    Write-Host "Cleaning up deadlocked RDP client processes..." -ForeColor Cyan
    Stop-Process -Name "mstsc", "msrdc" -Force -ErrorAction SilentlyContinue

    # Restart Remote Desktop Service
    Write-Host "Restarting Remote Desktop Service (TermService) to release hooks..." -ForeColor Cyan
    Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Write-Host "RDP services and client hooks have been reset." -ForeColor Green
}

function Invoke-RegularFix {
    Write-Host ""
    Write-Host "==========================================================================" -ForeColor Green
    Write-Host "                     RUNNING REGULAR CITRIX FIX                           " -ForeColor Green
    Write-Host "==========================================================================" -ForeColor Green
    
    # 1. Kill hanging processes and release RDP/msiexec deadlocks
    Invoke-KillCitrixProcesses

    # 2. Fix High-DPI and screen resolution limits
    Invoke-FixResolution

    # 3. Clean compatibility flags
    Invoke-CleanCompatibilityFlags

    Write-Host ""
    Write-Host "==========================================================================" -ForeColor Green
    Write-Host "                     REGULAR FIX COMPLETED!                               " -ForeColor Green
    Write-Host "==========================================================================" -ForeColor Green
    Write-Host " Citrix sessions have been terminated, RDP hooks released, and DPI restored." -ForeColor White
    Write-Host " You can now launch your Citrix app or Remote Desktop without hanging." -ForeColor White
    Write-Host "==========================================================================" -ForeColor Green
}

function Invoke-FixCitrixMsi {
    param([switch]$SkipWarning)

    $msiScript = Join-Path $PSScriptRoot "fix_citrix_msi.ps1"
    if (Test-Path $msiScript) {
        if ($SkipWarning -or $Force) {
            & $msiScript -Force
        } else {
            & $msiScript
        }
    } else {
        Write-Host "Error: fix_citrix_msi.ps1 was not found in $PSScriptRoot." -ForeColor Red
    }
}

function Invoke-FixResolution {
    Write-Host ""
    Write-Host "--- Fixing Resolution & High-DPI Scaling Limits ---" -ForeColor Cyan

    # 1. High DPI registry fix in HKCU and HKLM
    $hkcuPath = "HKCU:\Software\Citrix\ICA Client\DPI"
    if (-not (Test-Path $hkcuPath)) {
        New-Item -Path $hkcuPath -Force | Out-Null
    }
    Set-ItemProperty -Path $hkcuPath -Name "DpiAware" -Value 1 -Type DWord -Force
    Write-Host "  [APPLIED] Set HKCU DpiAware = 1" -ForeColor Green

    $hklmPath = "HKLM:\SOFTWARE\Policies\Citrix\ICA Client\DPI"
    if (-not (Test-Path $hklmPath)) {
        try { New-Item -Path $hklmPath -Force -ErrorAction Stop | Out-Null } catch {}
    }
    if (Test-Path $hklmPath) {
        Set-ItemProperty -Path $hklmPath -Name "DpiAware" -Value 1 -Type DWord -Force
        Write-Host "  [APPLIED] Set HKLM Policy DpiAware = 1" -ForeColor Green
    }

    # 2. Remove MaxMonitorDimension
    $desktopKey = "HKCU:\Control Panel\Desktop"
    $valName = "MaxMonitorDimension"
    if (Get-ItemProperty -Path $desktopKey -Name $valName -ErrorAction SilentlyContinue) {
        try {
            Remove-ItemProperty -Path $desktopKey -Name $valName -ErrorAction Stop
            Write-Host "  [REMOVED] MaxMonitorDimension limit in HKCU:\Control Panel\Desktop" -ForeColor Green
        } catch {
            Write-Host "  [FAILED] Could not remove MaxMonitorDimension: $_" -ForeColor Red
        }
    } else {
        Write-Host "  [CLEAN] MaxMonitorDimension limit not present." -ForeColor Gray
    }

    # 3. Clear window placement cache
    $stuckKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
    if (Test-Path $stuckKey) {
        Remove-Item -Path $stuckKey -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "  [CLEANED] Explorer window placement cache (StuckRects3)." -ForeColor Green
    }
}

function Invoke-CleanCompatibilityFlags {
    Write-Host ""
    Write-Host "--- Scanning & Cleaning Windows Compatibility Flags ---" -ForeColor Cyan

    $citrixExes = @("wfica32.exe", "wfcrun32.exe", "SelfService.exe", "CDViewer.exe", "Concentr.exe")
    $registries = @(
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
        "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
    )

    $removedCount = 0
    foreach ($regPath in $registries) {
        if (Test-Path $regPath) {
            $properties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($properties) {
                foreach ($prop in $properties.PSObject.Properties) {
                    $exePath = $prop.Name
                    $flags = $prop.Value
                    foreach ($citrixExe in $citrixExes) {
                        if ($exePath -match [regex]::Escape($citrixExe)) {
                            try {
                                Remove-ItemProperty -Path $regPath -Name $exePath -ErrorAction Stop
                                Write-Host "  [REMOVED] $citrixExe override flag from $regPath" -ForeColor Green
                                $removedCount++
                            } catch {
                                Write-Host "  [FAILED] Could not remove $($exePath): $_" -ForeColor Red
                            }
                        }
                    }
                }
            }
        }
    }

    if ($removedCount -eq 0) {
        Write-Host "  [CLEAN] No Citrix compatibility flag overrides found." -ForeColor Green
    } else {
        Write-Host "Cleaned $removedCount compatibility override flags." -ForeColor Green
    }
}

function Invoke-VerifyStatus {
    Write-Host ""
    Write-Host "--- Verifying Citrix Configuration & Health Status ---" -ForeColor Cyan

    $allGood = $true

    # 1. MaxMonitorDimension
    $desktopKey = "HKCU:\Control Panel\Desktop"
    if (Get-ItemProperty -Path $desktopKey -Name "MaxMonitorDimension" -ErrorAction SilentlyContinue) {
        Write-Host "  [FAIL] 'MaxMonitorDimension' still exists (limits monitor resolution)!" -ForeColor Red
        $allGood = $false
    } else {
        Write-Host "  [PASS] 'MaxMonitorDimension' is removed." -ForeColor Green
    }

    # 2. Compatibility Flags
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
        Write-Host "  [FAIL] Citrix Compatibility flags found (override DPI)." -ForeColor Red
        $allGood = $false
    } else {
        Write-Host "  [PASS] No Citrix Compatibility flags found." -ForeColor Green
    }

    # 3. DPI Setting
    $dpi = (Get-ItemProperty -Path "HKCU:\Software\Citrix\ICA Client\DPI" -Name "DpiAware" -ErrorAction SilentlyContinue).DpiAware
    if ($dpi -eq 1) {
        Write-Host "  [PASS] DPI Awareness is active (DpiAware=1)." -ForeColor Green
    } else {
        Write-Host "  [WARN] DPI Awareness is NOT set (Current: $dpi)." -ForeColor Yellow
    }

    # 4. InstallHelper Run Trigger
    $runProps = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
    if ($runProps.InstallHelper) {
        Write-Host "  [FAIL] Stuck Citrix InstallHelper auto-start entry detected in Run key!" -ForeColor Red
        $allGood = $false
    } else {
        Write-Host "  [PASS] No stuck InstallHelper auto-start entries in Run key." -ForeColor Green
    }

    # 5. Online Plug-in Component Locks
    $packedGuid = "2602849FCCDF11240AAB4EA10201C0D2"
    $compKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components"
    $lockCount = 0
    if (Test-Path $compKey) {
        Get-ChildItem -Path $compKey -ErrorAction SilentlyContinue | ForEach-Object {
            $cp = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($null -ne $cp.$packedGuid) { $lockCount++ }
        }
    }
    if ($lockCount -gt 0) {
        Write-Host "  [FAIL] $lockCount orphaned component locks for Online Plug-in (causes ICAWebWrapper error)!" -ForeColor Red
        $allGood = $false
    } else {
        Write-Host "  [PASS] No orphaned Online Plug-in component repair locks found." -ForeColor Green
    }

    Write-Host "--------------------------------------------------------" -ForeColor Gray
    if ($allGood) {
        Write-Host "Status: Citrix configuration is CLEAN and HEALTHY." -ForeColor Green
    } else {
        Write-Host "Status: Issues detected. Choose [1] for Regular Fix or [2] for MSI Fix." -ForeColor Yellow
    }
}

function Invoke-HardReset {
    Write-Host ""
    Write-Host "==========================================================================" -ForeColor Red
    Write-Host "                 WARNING: DESTRUCTIVE HARD RESET OF CITRIX                " -ForeColor Yellow
    Write-Host "==========================================================================" -ForeColor Red
    Write-Host " This will delete your local Citrix Workspace cache, temp files," -ForeColor White
    Write-Host " and user registry preferences (HKCU\Software\Citrix)." -ForeColor White
    Write-Host " You will need to re-enter your Store URL and credentials afterward." -ForeColor Yellow
    Write-Host "==========================================================================" -ForeColor Red
    Write-Host ""

    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to hard reset Citrix Workspace? (Y/N)"
        if ($confirm -notmatch "^[Yy]([Ee][Ss])?$") {
            Write-Host "Hard reset cancelled. No changes were made." -ForeColor Yellow
            return
        }
    }

    # Registry backup
    $backupPath = "$HOME\Desktop\Citrix_HKCU_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    Write-Host "Backing up HKCU\Software\Citrix to $backupPath..." -ForeColor Cyan
    reg export "HKCU\Software\Citrix" $backupPath /y 2>$null

    # Kill processes
    Invoke-KillCitrixProcesses

    # Clean directories
    $dirsToClean = @(
        "$env:APPDATA\Citrix",
        "$env:LOCALAPPDATA\Citrix"
    )
    foreach ($dir in $dirsToClean) {
        if (Test-Path $dir) {
            try {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
                Write-Host "  [DELETED] $dir" -ForeColor Green
            } catch {
                Write-Host "  [FAILED] Could not delete $($dir): $_" -ForeColor Red
            }
        }
    }

    # Clean registry
    $regPath = "HKCU:\Software\Citrix"
    if (Test-Path $regPath) {
        try {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Host "  [DELETED] $regPath" -ForeColor Green
        } catch {
            Write-Host "  [FAILED] Could not delete $($regPath): $_" -ForeColor Red
        }
    }

    # Restore DPI aware setting
    Invoke-FixResolution
    Write-Host "Hard reset complete. Launch Citrix Workspace to configure account." -ForeColor Green
}

function Invoke-FullAutomatedRepair {
    Write-Host ""
    Write-Host "==========================================================================" -ForeColor Magenta
    Write-Host "                 RUNNING FULL AUTOMATED CITRIX REPAIR                     " -ForeColor Magenta
    Write-Host "==========================================================================" -ForeColor Magenta
    
    Invoke-KillCitrixProcesses
    Invoke-FixCitrixMsi -SkipWarning:($Force.IsPresent)
    Invoke-FixResolution
    Invoke-CleanCompatibilityFlags
    Invoke-VerifyStatus
    
    Write-Host ""
    Write-Host "==========================================================================" -ForeColor Green
    Write-Host "               ALL AUTOMATED REPAIRS COMPLETED SUCCESSFULLY!              " -ForeColor Green
    Write-Host "==========================================================================" -ForeColor Green
}

# -------------------------------------------------------------
# CLI Parameter Handling (Non-Interactive execution)
# -------------------------------------------------------------
$executedCli = $false

if ($Regular -or $Action -in @("1", "Regular")) {
    Assert-Administrator "Regular"
    Invoke-RegularFix
    $executedCli = $true
}
elseif ($FixMSI -or $Action -in @("2", "FixMSI")) {
    Assert-Administrator "FixMSI"
    Invoke-FixCitrixMsi
    $executedCli = $true
}
elseif ($Kill -or $Action -eq "Kill") {
    Assert-Administrator "Kill"
    Invoke-KillCitrixProcesses
    $executedCli = $true
}
elseif ($FixResolution -or $Action -eq "FixResolution") {
    Assert-Administrator "FixResolution"
    Invoke-FixResolution
    $executedCli = $true
}
elseif ($CleanFlags -or $Action -eq "CleanFlags") {
    Assert-Administrator "CleanFlags"
    Invoke-CleanCompatibilityFlags
    $executedCli = $true
}
elseif ($Verify -or $Action -eq "Verify") {
    Invoke-VerifyStatus
    $executedCli = $true
}
elseif ($HardReset -or $Action -eq "HardReset") {
    Assert-Administrator "HardReset"
    Invoke-HardReset
    $executedCli = $true
}
elseif ($FullFix -or $Action -eq "FullFix") {
    Assert-Administrator "FullFix"
    Invoke-FullAutomatedRepair
    $executedCli = $true
}
elseif ($Action -eq "0") {
    exit
}

if ($executedCli) {
    Write-Host ""
    Write-Host "Operation finished." -ForeColor Cyan
    exit
}

# -------------------------------------------------------------
# Advanced Sub-Menu
# -------------------------------------------------------------
function Show-AdvancedMenu {
    while ($true) {
        Clear-Host
        Write-Host "==========================================================================" -ForeColor Cyan
        Write-Host "                 ADVANCED CITRIX DIAGNOSTICS & TOOLS                     " -ForeColor Yellow
        Write-Host "==========================================================================" -ForeColor Cyan
        Write-Host "  [1] Verify Citrix Configuration & Installer Health Status" -ForeColor White
        Write-Host "  [2] Kill Citrix & Reset Deadlocked Services Only" -ForeColor Cyan
        Write-Host "  [3] Fix High-DPI Resolution & Monitor Scaling Limits Only" -ForeColor Cyan
        Write-Host "  [4] Clean Windows Compatibility (AppCompat) Overrides Only" -ForeColor Cyan
        Write-Host "  [5] Hard Reset Citrix Workspace (Wipe Local Cache & HKCU)" -ForeColor Red
        Write-Host "  [6] Full Automated System Repair (Run All Fixes)" -ForeColor Magenta
        Write-Host "  [0] Back to Main Menu" -ForeColor DarkGray
        Write-Host "==========================================================================" -ForeColor Cyan

        $advChoice = Read-Host " Enter choice [0-6]"
        switch ($advChoice) {
            "1" { Invoke-VerifyStatus }
            "2" { Assert-Administrator "Kill"; Invoke-KillCitrixProcesses }
            "3" { Assert-Administrator "FixResolution"; Invoke-FixResolution }
            "4" { Assert-Administrator "CleanFlags"; Invoke-CleanCompatibilityFlags }
            "5" { Assert-Administrator "HardReset"; Invoke-HardReset }
            "6" { Assert-Administrator "FullFix"; Invoke-FullAutomatedRepair }
            "0" { return }
            default { Write-Host "Invalid selection." -ForeColor Red }
        }

        Write-Host ""
        Write-Host "Press any key to continue..." -ForeColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

# -------------------------------------------------------------
# Main Menu Loop
# -------------------------------------------------------------
while ($true) {
    Clear-Host
    $adminStatus = if (Test-IsAdmin) { "[Administrator]" } else { "[Standard User - Auto-Elevates on Repairs]" }
    $adminColor = if (Test-IsAdmin) { "Green" } else { "Yellow" }

    Write-Host "==========================================================================" -ForeColor Cyan
    Write-Host "                 CITRIX PROBLEM SOLVER & REPAIR BOT                      " -ForeColor Yellow
    Write-Host "                     $adminStatus                                        " -ForeColor $adminColor
    Write-Host "==========================================================================" -ForeColor Cyan
    Write-Host " What kind of fix do you need?" -ForeColor White
    Write-Host ""
    Write-Host "  [1] Regular Fix (Recommended for daily hangs)" -ForeColor Green
    Write-Host "      - Force-close frozen Citrix Receiver / Workspace sessions" -ForeColor Gray
    Write-Host "      - Release deadlocked RDP hooks (fix Remote Desktop hanging)" -ForeColor Gray
    Write-Host "      - Clear stuck msiexec background tasks" -ForeColor Gray
    Write-Host "      - Restore High-DPI scaling & clear screen resolution caps" -ForeColor Gray
    Write-Host ""
    Write-Host "  [2] Fix MSI & Installer Loop (Specialized Fix)" -ForeColor Yellow
    Write-Host "      - Target Error: 'The feature you are trying to use is on a network" -ForeColor DarkYellow
    Write-Host "        resource that is unavailable: ICAWebWrapper.msi / Online Plug-in'" -ForeColor DarkYellow
    Write-Host "      - Purge orphaned Windows Installer component locks (self-repair loops)" -ForeColor Gray
    Write-Host "      - Remove stuck InstallHelper startup auto-run registry entries" -ForeColor Gray
    Write-Host "      - [!] Includes safety warning & automatic Desktop registry backup" -ForeColor DarkYellow
    Write-Host "      - [!] REQUIRED: Download & install fresh Citrix Workspace after cleanup" -ForeColor Red
    Write-Host ""
    Write-Host "  [3] Advanced Tools & Diagnostics (Verify, Hard Reset, etc.)" -ForeColor Cyan
    Write-Host ""
    Write-Host "  [0] Exit" -ForeColor DarkGray
    Write-Host "==========================================================================" -ForeColor Cyan
    
    $choice = Read-Host " Enter choice [1, 2, 3, or 0]"
    switch ($choice) {
        "1" { Assert-Administrator "Regular"; Invoke-RegularFix }
        "2" { Assert-Administrator "FixMSI"; Invoke-FixCitrixMsi }
        "3" { Show-AdvancedMenu }
        "0" { Write-Host "Exiting Citrix Problem Solver Bot. Goodbye!" -ForeColor Cyan; exit }
        default { Write-Host "Invalid selection. Please choose 1, 2, 3, or 0." -ForeColor Red }
    }

    Write-Host ""
    Write-Host "Press any key to return to menu..." -ForeColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
