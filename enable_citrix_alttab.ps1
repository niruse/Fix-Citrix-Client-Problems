# Enable-CitrixAltTab.ps1
# Enables Alt-Tab Hotkey Within A Citrix Desktop Session - Citrix Workspace App
# Reference: Citrix Knowledge Center Article CTX232298
#
# Configures the 'TransparentKeyPassthrough' registry key to 'remote' across
# Per-Machine (HKLM) and Per-User (HKCU) hives so Alt+Tab switches windows
# inside the remote Citrix Desktop session instead of the local endpoint.
#
# Prerequisite: Verifies whether Citrix Workspace / Receiver is installed before applying changes.

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [switch]$Force,
    [switch]$RestartCitrix,
    [switch]$Elevate
)

# -------------------------------------------------------------
# 0. Helper: Check if Citrix is installed on this machine
# -------------------------------------------------------------
function Get-CitrixInstallInfo {
    $info = @{
        IsInstalled     = $false
        DisplayName     = $null
        DisplayVersion  = $null
        InstallLocation = $null
        DetectionMethod = $null
    }

    # 1. Search Windows Installer / Add-Remove Programs (HKLM 64-bit, HKLM 32-bit, HKCU)
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

    # 2. Check Core Citrix Configuration Keys
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

    # 3. Check File System Executables
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

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# -------------------------------------------------------------
# 1. Header & Context
# -------------------------------------------------------------
Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "         ENABLE ALT-TAB HOTKEY PASSTHROUGH IN CITRIX (CTX232298)         " -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host " Problem: Pressing Alt+Tab toggles local endpoint windows instead of" -ForegroundColor DarkGray
Write-Host "          windows inside the active Citrix Desktop session." -ForegroundColor DarkGray
Write-Host " Fix:     Configures 'TransparentKeyPassthrough=remote' in client registry." -ForegroundColor DarkGray
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------------------
# 2. Check if Citrix is installed
# -------------------------------------------------------------
Write-Host "[1/4] Verifying Citrix installation status..." -ForegroundColor Cyan
$installInfo = Get-CitrixInstallInfo

if (-not $installInfo.IsInstalled) {
    if (-not $Force) {
        Write-Host "  [!] CITRIX NOT DETECTED: Citrix Workspace or Receiver is not installed." -ForegroundColor Red
        Write-Host "      Registry update aborted. Please install Citrix Workspace before enabling hotkeys." -ForegroundColor Yellow
        Write-Host "      Official Download: https://www.citrix.com/downloads/workspace-app/windows/" -ForegroundColor White
        Write-Host ""
        Write-Host "      (To bypass this check and force registry creation, run with -Force)" -ForegroundColor DarkGray
        Write-Host ""
        return
    } else {
        Write-Host "  [WARN] Citrix not detected, but -Force switch specified. Proceeding with registry update..." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [PASS] Citrix installation verified!" -ForegroundColor Green
    Write-Host "         - Product:  $($installInfo.DisplayName)" -ForegroundColor White
    if ($installInfo.DisplayVersion) {
        Write-Host "         - Version:  $($installInfo.DisplayVersion)" -ForegroundColor White
    }
    if ($installInfo.InstallLocation) {
        Write-Host "         - Path:     $($installInfo.InstallLocation)" -ForegroundColor White
    }
    Write-Host "         - Method:   $($installInfo.DetectionMethod)" -ForegroundColor Gray
}

# -------------------------------------------------------------
# 3. Check Privileges & Elevation
# -------------------------------------------------------------
$isAdmin = Test-IsAdmin
if (-not $isAdmin -and $Elevate) {
    Write-Host ""
    Write-Host "Requesting Administrator elevation for machine-wide (HKLM) registry..." -ForegroundColor Cyan
    $elevateCmd = "cd '$pwd'; & '$PSCommandPath' $(if($Force){'-Force'}) $(if($RestartCitrix){'-RestartCitrix'}); Write-Host ''; Write-Host 'Press Enter to exit...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine();"
    Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$elevateCmd`""
    exit
}

if ($isAdmin) {
    Write-Host "  [INFO] Running with Administrator privileges (HKLM + HKCU will be updated)." -ForegroundColor Green
} else {
    Write-Host "  [INFO] Running as Standard User (HKCU will be updated; HKLM may require Admin)." -ForegroundColor Yellow
}

# -------------------------------------------------------------
# 4. Apply Registry Settings (Per-User and Per-Machine)
# -------------------------------------------------------------
Write-Host ""
Write-Host "[2/4] Applying TransparentKeyPassthrough registry configuration..." -ForegroundColor Cyan

$keysToUpdate = @()

# Per-User setting (Always applicable)
$keysToUpdate += @{
    Hive = "HKCU"
    Path = "HKCU:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
    Description = "Per-User Setting (HKCU)"
}

$is64Bit = [Environment]::Is64BitOperatingSystem

if ($is64Bit) {
    # 64-bit OS: 32-bit subsystem key
    $keysToUpdate += @{
        Hive = "HKLM"
        Path = "HKLM:\SOFTWARE\WOW6432Node\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
        Description = "Per-Machine Setting (HKLM WOW6432Node - 64-bit OS)"
    }
    # 64-bit OS: Native 64-bit key (for Workspace 2402+ 64-bit native builds)
    $keysToUpdate += @{
        Hive = "HKLM"
        Path = "HKLM:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
        Description = "Per-Machine Setting (HKLM Native 64-bit)"
    }
} else {
    # 32-bit OS: Native key
    $keysToUpdate += @{
        Hive = "HKLM"
        Path = "HKLM:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard"
        Description = "Per-Machine Setting (HKLM - 32-bit OS)"
    }
}

$successCount = 0
foreach ($entry in $keysToUpdate) {
    $targetPath = $entry.Path
    $desc = $entry.Description

    try {
        if (-not (Test-Path $targetPath)) {
            New-Item -Path $targetPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $targetPath -Name "TransparentKeyPassthrough" -Value "remote" -Type String -Force -ErrorAction Stop
        Write-Host "  [APPLIED] $desc" -ForegroundColor Green
        Write-Host "            Path:  $targetPath" -ForegroundColor DarkGray
        Write-Host "            Value: TransparentKeyPassthrough = remote (REG_SZ)" -ForegroundColor DarkGray
        $successCount++
    } catch {
        if ($entry.Hive -eq "HKLM" -and -not $isAdmin) {
            Write-Host "  [SKIPPED] $desc (Requires Administrator elevation for machine-wide policy)" -ForegroundColor Yellow
        } else {
            Write-Host "  [FAILED]  $desc - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# -------------------------------------------------------------
# 5. Verification
# -------------------------------------------------------------
Write-Host ""
Write-Host "[3/4] Verifying applied registry configuration..." -ForegroundColor Cyan

$hkcuVal = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard" -Name "TransparentKeyPassthrough" -ErrorAction SilentlyContinue).TransparentKeyPassthrough
if ($hkcuVal -eq "remote") {
    Write-Host "  [PASS] HKCU TransparentKeyPassthrough = 'remote'" -ForegroundColor Green
} else {
    Write-Host "  [WARN] HKCU TransparentKeyPassthrough is '$hkcuVal' (Expected: 'remote')" -ForegroundColor Yellow
}

if ($is64Bit) {
    $hklmWowVal = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard" -Name "TransparentKeyPassthrough" -ErrorAction SilentlyContinue).TransparentKeyPassthrough
    if ($hklmWowVal -eq "remote") {
        Write-Host "  [PASS] HKLM (WOW6432Node) TransparentKeyPassthrough = 'remote'" -ForegroundColor Green
    } elseif ($isAdmin) {
        Write-Host "  [WARN] HKLM (WOW6432Node) TransparentKeyPassthrough is '$hklmWowVal'" -ForegroundColor Yellow
    }
}

# -------------------------------------------------------------
# 6. Process Restart & Completion Guidance
# -------------------------------------------------------------
Write-Host ""
Write-Host "[4/4] Finalizing configuration..." -ForegroundColor Cyan

$runningCitrix = Get-Process -Name "Receiver", "wfica32", "wfcrun32", "CDViewer", "SelfService" -ErrorAction SilentlyContinue

if ($runningCitrix) {
    Write-Host "  [!] Notice: Active Citrix processes detected ($($runningCitrix.Count) process(es))." -ForegroundColor Yellow
    Write-Host "      According to CTX232298, Citrix Workspace App must be exited and" -ForegroundColor Yellow
    Write-Host "      re-launched for the Alt-Tab hotkey passthrough change to take effect." -ForegroundColor Yellow
    
    if ($RestartCitrix) {
        Write-Host "  Restarting active Citrix processes as requested..." -ForegroundColor Cyan
        $runningCitrix | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Write-Host "  [DONE] Citrix processes terminated. Ready for fresh launch." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  Tip: You can run with -RestartCitrix to automatically restart processes," -ForegroundColor DarkGray
        Write-Host "       or close Citrix from your system tray and launch it again." -ForegroundColor DarkGray
    }
} else {
    Write-Host "  No active Citrix sessions running. Setting will apply on your next launch." -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "               ALT-TAB HOTKEY PASSTHROUGH CONFIGURATION COMPLETE          " -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " Alt+Tab will now switch between open windows inside your Citrix Desktop." -ForegroundColor White
Write-Host "==========================================================================" -ForegroundColor Green
