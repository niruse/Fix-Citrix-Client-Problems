# Kill-Citrix.ps1 / Citrix Problem Solver Bot
# Comprehensive tool to resolve Citrix Receiver/Workspace hangs, deadlocks,
# resolution issues, Alt-Tab hotkey passthrough (CTX232298), and the 'ICAWebWrapper.msi'
# network resource unavailable loop.

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("1", "2", "3", "4", "0", "Regular", "FixMSI", "EnableAltTab", "AltTab", "Advanced", "Kill", "FixResolution", "CleanFlags", "Verify", "HardReset", "FullFix", "Menu")]
    [string]$Action,

    [switch]$Regular,
    [switch]$Kill,
    [switch]$FixMSI,
    [switch]$EnableAltTab,
    [switch]$AltTab,
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
        Write-Host "This operation requires Administrator privileges. Requesting elevation..." -ForegroundColor Cyan
        $cmd = "cd '$pwd'; & '$PSCommandPath'"
        if ($PendingAction) { $cmd += " -Action '$PendingAction'" }
        if ($Force) { $cmd += " -Force" }
        $cmd += "; Write-Host ''; Write-Host 'Press Enter to close window...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine()"
        
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
        exit
    }
}

# -------------------------------------------------------------
# Helper: Detect Citrix Installation
# -------------------------------------------------------------
function Get-CitrixInstallInfo {
    $info = @{
        IsInstalled     = $false
        DisplayName     = $null
        DisplayVersion  = $null
        InstallLocation = $null
        DetectionMethod = $null
    }

    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($uRoot in $uninstallRoots) {
        $found = Get-ItemProperty -Path $uRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'Citrix\s+(Workspace|Receiver|Online Plug-in)' } |
            Select-Object -First 1
        if ($found) {
            $info.IsInstalled = $true
            $info.DisplayName = $found.DisplayName
            $info.DisplayVersion = $found.DisplayVersion
            $info.InstallLocation = $found.InstallLocation
            $info.DetectionMethod = "Windows Uninstall Registry ($($found.DisplayName))"
            return [PSCustomObject]$info
        }
    }

    $citrixCoreKeys = @(
        "HKLM:\SOFTWARE\Citrix\ICA Client",
        "HKLM:\SOFTWARE\WOW6432Node\Citrix\ICA Client",
        "HKLM:\SOFTWARE\Citrix\Install",
        "HKLM:\SOFTWARE\WOW6432Node\Citrix\Install"
    )
    foreach ($key in $citrixCoreKeys) {
        if (Test-Path $key) {
            $info.IsInstalled = $true
            $info.DisplayName = "Citrix Workspace / Receiver"
            $info.DetectionMethod = "Registry Key ($key)"
            return [PSCustomObject]$info
        }
    }

    $executables = @(
        "$env:ProgramFiles\Citrix\ICA Client\wfica32.exe",
        "${env:ProgramFiles(x86)}\Citrix\ICA Client\wfica32.exe",
        "$env:ProgramFiles\Citrix\Workspace App\Receiver.exe",
        "${env:ProgramFiles(x86)}\Citrix\Workspace App\Receiver.exe"
    )
    foreach ($exe in $executables) {
        if (Test-Path $exe) {
            $info.IsInstalled = $true
            $info.DisplayName = "Citrix Workspace"
            $info.InstallLocation = Split-Path -Parent $exe
            $info.DetectionMethod = "Executable binary ($exe)"
            return [PSCustomObject]$info
        }
    }

    return [PSCustomObject]$info
}

# -------------------------------------------------------------
# Module Functions
# -------------------------------------------------------------

function Invoke-KillCitrixProcesses {
    Write-Host ""
    Write-Host "--- Stopping Citrix Processes & Releasing Deadlocks ---" -ForegroundColor Cyan
    
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
                    Write-Host "  [STOPPED] $($proc.ProcessName) (ID: $($proc.Id))" -ForegroundColor Green
                } catch {
                    Write-Host "  [FAILED] $($proc.ProcessName) (ID: $($proc.Id)) - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }

    $remaining = Get-Process -Name $processNames -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Host "Warning: Some Citrix processes could not be stopped." -ForegroundColor Yellow
    } else {
        Write-Host "All Citrix processes stopped." -ForegroundColor Green
    }

    # Clear stuck msiexec
    Write-Host "Clearing stuck Windows Installer processes (msiexec)..." -ForegroundColor Cyan
    Stop-Process -Name "msiexec" -Force -ErrorAction SilentlyContinue

    # Clean deadlocked RDP clients
    Write-Host "Cleaning up deadlocked RDP client processes..." -ForegroundColor Cyan
    Stop-Process -Name "mstsc", "msrdc" -Force -ErrorAction SilentlyContinue

    # Restart Remote Desktop Service
    Write-Host "Restarting Remote Desktop Service (TermService) to release hooks..." -ForegroundColor Cyan
    Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Write-Host "RDP services and client hooks have been reset." -ForegroundColor Green
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
        Write-Host "Error: fix_citrix_msi.ps1 was not found in $PSScriptRoot." -ForegroundColor Red
    }
}

function Invoke-FixResolution {
    Write-Host ""
    Write-Host "--- Fixing Resolution & High-DPI Scaling Limits ---" -ForegroundColor Cyan

    # 1. High DPI registry fix in HKCU and HKLM
    $hkcuPath = "HKCU:\Software\Citrix\ICA Client\DPI"
    if (-not (Test-Path $hkcuPath)) {
        New-Item -Path $hkcuPath -Force | Out-Null
    }
    Set-ItemProperty -Path $hkcuPath -Name "DpiAware" -Value 1 -Type DWord -Force
    Write-Host "  [APPLIED] Set HKCU DpiAware = 1" -ForegroundColor Green

    $hklmPath = "HKLM:\SOFTWARE\Policies\Citrix\ICA Client\DPI"
    if (-not (Test-Path $hklmPath)) {
        try { New-Item -Path $hklmPath -Force -ErrorAction Stop | Out-Null } catch {}
    }
    if (Test-Path $hklmPath) {
        Set-ItemProperty -Path $hklmPath -Name "DpiAware" -Value 1 -Type DWord -Force
        Write-Host "  [APPLIED] Set HKLM Policy DpiAware = 1" -ForegroundColor Green
    }

    # 2. Remove MaxMonitorDimension
    $desktopKey = "HKCU:\Control Panel\Desktop"
    $valName = "MaxMonitorDimension"
    if (Get-ItemProperty -Path $desktopKey -Name $valName -ErrorAction SilentlyContinue) {
        try {
            Remove-ItemProperty -Path $desktopKey -Name $valName -ErrorAction Stop
            Write-Host "  [REMOVED] MaxMonitorDimension limit in HKCU:\Control Panel\Desktop" -ForegroundColor Green
        } catch {
            Write-Host "  [FAILED] Could not remove MaxMonitorDimension: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  [CLEAN] MaxMonitorDimension limit not present." -ForegroundColor Gray
    }

    # 3. Clear window placement cache
    $stuckKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
    if (Test-Path $stuckKey) {
        Remove-Item -Path $stuckKey -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "  [CLEANED] Explorer window placement cache (StuckRects3)." -ForegroundColor Green
    }
}

function Invoke-CleanCompatibilityFlags {
    Write-Host ""
    Write-Host "--- Scanning & Cleaning Windows Compatibility Flags ---" -ForegroundColor Cyan

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
                                Write-Host "  [REMOVED] $citrixExe override flag from $regPath" -ForegroundColor Green
                                $removedCount++
                            } catch {
                                Write-Host "  [FAILED] Could not remove $($exePath): $_" -ForegroundColor Red
                            }
                        }
                    }
                }
            }
        }
    }

    if ($removedCount -eq 0) {
        Write-Host "  [CLEAN] No Citrix compatibility flag overrides found." -ForegroundColor Green
    } else {
        Write-Host "Cleaned $removedCount compatibility override flags." -ForegroundColor Green
    }
}

function Invoke-EnableAltTabHotkey {
    Write-Host ""
    Write-Host "--- Enabling Alt-Tab Hotkey in Citrix Desktop (CTX232298) ---" -ForegroundColor Cyan
    Write-Host "Verifying Citrix installation status..." -ForegroundColor Cyan

    $installInfo = Get-CitrixInstallInfo
    if (-not $installInfo.IsInstalled) {
        if (-not $Force) {
            Write-Host "  [!] CITRIX NOT DETECTED: Citrix Workspace or Receiver is not installed." -ForegroundColor Red
            Write-Host "      Registry update aborted. Please install Citrix Workspace before enabling hotkeys." -ForegroundColor Yellow
            Write-Host "      Official Download: https://www.citrix.com/downloads/workspace-app/windows/" -ForegroundColor White
            return
        } else {
            Write-Host "  [WARN] Citrix not detected, but -Force switch specified. Proceeding..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [PASS] Citrix installation verified: $($installInfo.DisplayName) ($($installInfo.DisplayVersion))" -ForegroundColor Green
    }

    $altTabScript = Join-Path $PSScriptRoot "enable_citrix_alttab.ps1"
    if (Test-Path $altTabScript) {
        & $altTabScript -Force
    } else {
        # Fallback inline registry application
        $keysToUpdate = @(
            "HKCU:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
        )
        if ([Environment]::Is64BitOperatingSystem) {
            $keysToUpdate += "HKLM:\SOFTWARE\WOW6432Node\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
            $keysToUpdate += "HKLM:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
        } else {
            $keysToUpdate += "HKLM:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
        }

        foreach ($p in $keysToUpdate) {
            try {
                if (-not (Test-Path $p)) { New-Item -Path $p -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -Path $p -Name "TransparentKeyPassthrough" -Value "remote" -Type String -Force -ErrorAction Stop
                Write-Host "  [APPLIED] Set TransparentKeyPassthrough = remote in $p" -ForegroundColor Green
            } catch {
                Write-Host "  [WARN] Could not update $p - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

function Invoke-RegularFix {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "                     RUNNING REGULAR CITRIX FIX                           " -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Green
    
    # 1. Kill hanging processes and release RDP/msiexec deadlocks
    Invoke-KillCitrixProcesses

    # 2. Fix High-DPI and screen resolution limits
    Invoke-FixResolution

    # 3. Clean compatibility flags
    Invoke-CleanCompatibilityFlags

    # 4. Enable Alt-Tab hotkey passthrough (CTX232298)
    Invoke-EnableAltTabHotkey

    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "                     REGULAR FIX COMPLETED!                               " -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host " Citrix sessions terminated, RDP hooks released, DPI restored, and Alt-Tab configured." -ForegroundColor White
    Write-Host " You can now launch your Citrix app or Remote Desktop without hanging." -ForegroundColor White
    Write-Host "==========================================================================" -ForegroundColor Green
}

function Invoke-VerifyStatus {
    Write-Host ""
    Write-Host "--- Verifying Citrix Configuration & Health Status ---" -ForegroundColor Cyan

    $allGood = $true

    # 1. MaxMonitorDimension
    $desktopKey = "HKCU:\Control Panel\Desktop"
    if (Get-ItemProperty -Path $desktopKey -Name "MaxMonitorDimension" -ErrorAction SilentlyContinue) {
        Write-Host "  [FAIL] 'MaxMonitorDimension' still exists (limits monitor resolution)!" -ForegroundColor Red
        $allGood = $false
    } else {
        Write-Host "  [PASS] 'MaxMonitorDimension' is removed." -ForegroundColor Green
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
        Write-Host "  [FAIL] Citrix Compatibility flags found (override DPI)." -ForegroundColor Red
        $allGood = $false
    } else {
        Write-Host "  [PASS] No Citrix Compatibility flags found." -ForegroundColor Green
    }

    # 3. DPI Setting
    $dpi = (Get-ItemProperty -Path "HKCU:\Software\Citrix\ICA Client\DPI" -Name "DpiAware" -ErrorAction SilentlyContinue).DpiAware
    if ($dpi -eq 1) {
        Write-Host "  [PASS] DPI Awareness is active (DpiAware=1)." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] DPI Awareness is NOT set (Current: $dpi)." -ForegroundColor Yellow
    }

    # 4. InstallHelper Run Trigger
    $runProps = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
    if ($runProps.InstallHelper) {
        Write-Host "  [FAIL] Stuck Citrix InstallHelper auto-start entry detected in Run key!" -ForegroundColor Red
        $allGood = $false
    } else {
        Write-Host "  [PASS] No stuck InstallHelper auto-start entries in Run key." -ForegroundColor Green
    }

    # 5. Online Plug-in Component Locks
    $packedGuid = "2602849FCCDF11240AAB4EA10201C0D2"
    $lockCount = 0
    try {
        $baseKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components")
        if ($baseKey) {
            foreach ($subName in $baseKey.GetSubKeyNames()) {
                $subKey = $baseKey.OpenSubKey($subName)
                if ($subKey) {
                    if ($null -ne $subKey.GetValue($packedGuid)) { $lockCount++ }
                    $subKey.Close()
                }
            }
            $baseKey.Close()
        }
    } catch {}
    if ($lockCount -gt 0) {
        Write-Host "  [FAIL] $lockCount orphaned component locks for Online Plug-in (causes ICAWebWrapper error)!" -ForegroundColor Red
        $allGood = $false
    } else {
        Write-Host "  [PASS] No orphaned Online Plug-in component repair locks found." -ForegroundColor Green
    }

    # 6. Alt-Tab Hotkey Passthrough (CTX232298)
    $altTabKey = "HKCU:\Software\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
    $altVal = (Get-ItemProperty -Path $altTabKey -Name "TransparentKeyPassthrough" -ErrorAction SilentlyContinue).TransparentKeyPassthrough
    if ($altVal -eq "remote") {
        Write-Host "  [PASS] Alt-Tab hotkey passthrough is enabled (TransparentKeyPassthrough=remote)." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Alt-Tab hotkey passthrough is NOT set to 'remote' (Current: '$altVal') - see CTX232298." -ForegroundColor Yellow
    }

    Write-Host "--------------------------------------------------------" -ForegroundColor Gray
    if ($allGood) {
        Write-Host "Status: Citrix configuration is CLEAN and HEALTHY." -ForegroundColor Green
    } else {
        Write-Host "Status: Issues detected. Choose [1] for Regular Fix or [2] for MSI Fix." -ForegroundColor Yellow
    }
}

function Invoke-HardReset {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host "                 WARNING: DESTRUCTIVE HARD RESET OF CITRIX                " -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host " This will delete your local Citrix Workspace cache, temp files," -ForegroundColor White
    Write-Host " and user registry preferences (HKCU\Software\Citrix)." -ForegroundColor White
    Write-Host " You will need to re-enter your Store URL and credentials afterward." -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host ""

    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to hard reset Citrix Workspace? (Y/N)"
        if ($confirm -notmatch "^[Yy]([Ee][Ss])?$") {
            Write-Host "Hard reset cancelled. No changes were made." -ForegroundColor Yellow
            return
        }
    }

    # Registry backup
    $backupPath = "$HOME\Desktop\Citrix_HKCU_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    Write-Host "Backing up HKCU\Software\Citrix to $backupPath..." -ForegroundColor Cyan
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
                Write-Host "  [DELETED] $dir" -ForegroundColor Green
            } catch {
                Write-Host "  [FAILED] Could not delete $($dir): $_" -ForegroundColor Red
            }
        }
    }

    # Clean registry
    $regPath = "HKCU:\Software\Citrix"
    if (Test-Path $regPath) {
        try {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
            Write-Host "  [DELETED] $regPath" -ForegroundColor Green
        } catch {
            Write-Host "  [FAILED] Could not delete $($regPath): $_" -ForegroundColor Red
        }
    }

    # Restore DPI aware setting & Alt-Tab hotkey
    Invoke-FixResolution
    Invoke-EnableAltTabHotkey
    Write-Host "Hard reset complete. Launch Citrix Workspace to configure account." -ForegroundColor Green
}

function Invoke-FullAutomatedRepair {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Magenta
    Write-Host "                 RUNNING FULL AUTOMATED CITRIX REPAIR                     " -ForegroundColor Magenta
    Write-Host "==========================================================================" -ForegroundColor Magenta
    
    Invoke-KillCitrixProcesses
    Invoke-FixCitrixMsi -SkipWarning:($Force.IsPresent)
    Invoke-FixResolution
    Invoke-CleanCompatibilityFlags
    Invoke-EnableAltTabHotkey
    Invoke-VerifyStatus
    
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "               ALL AUTOMATED REPAIRS COMPLETED SUCCESSFULLY!              " -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Green
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
elseif ($EnableAltTab -or $AltTab -or $Action -in @("3", "EnableAltTab", "AltTab")) {
    Assert-Administrator "EnableAltTab"
    Invoke-EnableAltTabHotkey
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
    Write-Host "Operation finished." -ForegroundColor Cyan
    exit
}

# -------------------------------------------------------------
# Advanced Sub-Menu
# -------------------------------------------------------------
function Show-AdvancedMenu {
    while ($true) {
        Clear-Host
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host "                 ADVANCED CITRIX DIAGNOSTICS & TOOLS                     " -ForegroundColor Yellow
        Write-Host "==========================================================================" -ForegroundColor Cyan
        Write-Host "  [1] Verify Citrix Configuration & Installer Health Status" -ForegroundColor White
        Write-Host "  [2] Kill Citrix & Reset Deadlocked Services Only" -ForegroundColor Cyan
        Write-Host "  [3] Fix High-DPI Resolution & Monitor Scaling Limits Only" -ForegroundColor Cyan
        Write-Host "  [4] Clean Windows Compatibility (AppCompat) Overrides Only" -ForegroundColor Cyan
        Write-Host "  [5] Enable Alt-Tab Hotkey Passthrough (CTX232298) Only" -ForegroundColor Cyan
        Write-Host "  [6] Hard Reset Citrix Workspace (Wipe Local Cache & HKCU)" -ForegroundColor Red
        Write-Host "  [7] Full Automated System Repair (Run All Fixes)" -ForegroundColor Magenta
        Write-Host "  [0] Back to Main Menu" -ForegroundColor DarkGray
        Write-Host "==========================================================================" -ForegroundColor Cyan

        $advChoice = Read-Host " Enter choice [0-7]"
        switch ($advChoice) {
            "1" { Invoke-VerifyStatus }
            "2" { Assert-Administrator "Kill"; Invoke-KillCitrixProcesses }
            "3" { Assert-Administrator "FixResolution"; Invoke-FixResolution }
            "4" { Assert-Administrator "CleanFlags"; Invoke-CleanCompatibilityFlags }
            "5" { Assert-Administrator "EnableAltTab"; Invoke-EnableAltTabHotkey }
            "6" { Assert-Administrator "HardReset"; Invoke-HardReset }
            "7" { Assert-Administrator "FullFix"; Invoke-FullAutomatedRepair }
            "0" { return }
            default { Write-Host "Invalid selection." -ForegroundColor Red }
        }

        Write-Host ""
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
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

    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "                 CITRIX PROBLEM SOLVER & REPAIR BOT                      " -ForegroundColor Yellow
    Write-Host "                     $adminStatus                                        " -ForegroundColor $adminColor
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host " What kind of fix do you need?" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Regular Fix (Recommended for daily hangs & Alt-Tab)" -ForegroundColor Green
    Write-Host "      - Force-close frozen Citrix Receiver / Workspace sessions" -ForegroundColor Gray
    Write-Host "      - Release deadlocked RDP hooks (fix Remote Desktop hanging)" -ForegroundColor Gray
    Write-Host "      - Clear stuck msiexec background tasks" -ForegroundColor Gray
    Write-Host "      - Restore High-DPI scaling & clear screen resolution caps" -ForegroundColor Gray
    Write-Host "      - Enable Alt-Tab hotkey passthrough within sessions" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [2] Fix MSI & Installer Loop (Specialized Fix)" -ForegroundColor Yellow
    Write-Host "      - Target Error: 'The feature you are trying to use is on a network" -ForegroundColor DarkYellow
    Write-Host "        resource that is unavailable: ICAWebWrapper.msi / Online Plug-in'" -ForegroundColor DarkYellow
    Write-Host "      - Purge orphaned Windows Installer component locks (self-repair loops)" -ForegroundColor Gray
    Write-Host "      - Remove stuck InstallHelper startup auto-run registry entries" -ForegroundColor Gray
    Write-Host "      - [!] Includes safety warning & automatic Desktop registry backup" -ForegroundColor DarkYellow
    Write-Host "      - [!] REQUIRED: Download & install fresh Citrix Workspace after cleanup" -ForegroundColor Red
    Write-Host ""
    Write-Host "  [3] Enable Alt-Tab Hotkey Passthrough (CTX232298) [NEW FEATURE]" -ForegroundColor Green
    Write-Host "      - Fix Alt+Tab switching local apps instead of Citrix session apps" -ForegroundColor Gray
    Write-Host "      - Verifies Citrix installation before updating registry" -ForegroundColor Gray
    Write-Host "      - Configures TransparentKeyPassthrough = remote (HKLM & HKCU)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [4] Advanced Tools & Diagnostics (Verify, Hard Reset, etc.)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [0] Exit" -ForegroundColor DarkGray
    Write-Host "==========================================================================" -ForegroundColor Cyan
    
    $choice = Read-Host " Enter choice [1, 2, 3, 4, or 0]"
    switch ($choice) {
        "1" { Assert-Administrator "Regular"; Invoke-RegularFix }
        "2" { Assert-Administrator "FixMSI"; Invoke-FixCitrixMsi }
        "3" { Assert-Administrator "EnableAltTab"; Invoke-EnableAltTabHotkey }
        "4" { Show-AdvancedMenu }
        "0" { Write-Host "Exiting Citrix Problem Solver Bot. Goodbye!" -ForegroundColor Cyan; exit }
        default { Write-Host "Invalid selection. Please choose 1, 2, 3, 4, or 0." -ForegroundColor Red }
    }

    Write-Host ""
    Write-Host "Press any key to return to menu..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
