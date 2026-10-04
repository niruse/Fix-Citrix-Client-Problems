# Citrix Problem Solver & Repair Bot

A comprehensive PowerShell repair bot and diagnostic suite for Citrix Receiver and Citrix Workspace. It forcefully terminates hanging processes, clears deep display and network deadlocks, repairs High-DPI and multi-monitor resolution issues, enables in-session **Alt-Tab hotkey passthrough (CTX232298)**, and permanently resolves the recurring **"ICAWebWrapper.msi / network resource unavailable"** Windows Installer loop.

---

## What This Bot Solves

When Citrix processes crash, get forcefully killed, or fail during automatic background updates, Windows is left in an unstable state. This bot actively diagnoses and repairs each broken subsystem:

### 1. "The feature you are trying to use is on a network resource that is unavailable (ICAWebWrapper.msi)"

#### Sample Error Dialog:
<p align="center">
  <img src="assets/icawebwrapper_error.png" alt="Citrix Online Plug-in ICAWebWrapper.msi Unavailable Network Resource Error" width="450">
</p>

```text
+------------------------------------------------------------------------+
| Online Plug-in                                                    [X]  |
+------------------------------------------------------------------------+
|  The feature you are trying to use is on a network resource that is   |
|  unavailable.                                                          |
|                                                                        |
|  Click OK to try again, or enter an alternate path to a folder         |
|  containing the installation package 'ICAWebWrapper.msi' in the        |
|  box below.                                                            |
|                                                                        |
|  Use source:                                                           |
|  [ C:\Program Files (x86)\Citrix\Citrix Workspace 26.x.x.x\   v ]      |
|                                               [  OK  ]  [ Cancel ]     |
|                                               [ Browse... ]            |
+------------------------------------------------------------------------+
```

* **The Root Cause:** When Citrix Workspace updates or uninstalls incompletely, Windows Installer retains hundreds of orphaned component locks (`UserData\...\Components`) and an auto-start `InstallHelper.exe` entry in the Windows `Run` key. Every time Windows boots or Citrix is invoked, Windows Installer triggers a silent self-repair looking for the original `ICAWebWrapper.msi` source package. Because the original folder no longer contains that exact package version, Windows locks up with an unavailable network resource dialog.
* **The Fix:** Option `[2]` (or `.\fix_citrix_msi.ps1`) presents a clear **safety warning**, prompts for explicit user confirmation, automatically exports a **safety registry backup (.reg)** to your Desktop, terminates deadlocked installer processes, purges the orphaned component locks, removes the `InstallHelper` auto-start trigger, and clears broken installer caches.

> [!IMPORTANT]
> **REQUIRED: Install Fresh Citrix Workspace After MSI Removal**  
> If you uninstall or purge the MSI components using this code, the broken repair loop is stopped, but the client package is cleared. **You are REQUIRED to download and install a fresh copy of Citrix Workspace App** to restore clean binaries, ICA file associations, and registry entries:  
> [👉 Download Workspace App for Windows (Official Citrix Portal)](https://www.citrix.com/downloads/workspace-app/windows/)

### 2. Alt-Tab Hotkey Toggles Local Apps Instead of Citrix Session (CTX232298) `[NEW FEATURE]`
* **The Problem:** Pressing `Alt+Tab` within a windowed Citrix Desktop session switches between applications on the local endpoint machine instead of switching between windows inside the active Citrix Desktop session.
* **Citrix Knowledge Center Reference:** [CTX232298](https://support.citrix.com/article/CTX232298) - *Enable Alt-Tab Hotkey Within A Citrix Desktop Session - Citrix Workspace App*.
* **Citrix Installation Check:** Before updating registry values, the tool verifies that Citrix Workspace or Citrix Receiver is currently installed on the machine (via Windows Uninstall entries, core configuration keys, and executable binaries). If Citrix is not installed, it alerts the user and halts to avoid writing redundant keys.
* **The Fix:** Configures `TransparentKeyPassthrough` to `"remote"` (`REG_SZ`) across:
  - **Per-User (HKCU):** `HKCU:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard`
  - **Per-Machine 64-bit (HKLM WOW6432Node & Native):** `HKLM:\SOFTWARE\WOW6432Node\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard` and `HKLM:\SOFTWARE\Citrix\ICA Client\...`
  - **Per-Machine 32-bit (HKLM):** `HKLM:\SOFTWARE\Citrix\ICA Client\Engine\Lockdown Profiles\All Regions\Lockdown\Virtual Channels\Keyboard`
* **Restart Requirement:** As noted in CTX232298, exit Citrix Workspace App / Receiver and launch it again for the hotkey passthrough change to take effect (supported automatically with `-RestartCitrix`).

### 3. Remote Desktop (RDP / mstsc.exe) Hanging
* **The Root Cause:** Killing `wfica32.exe` mid-session leaves Windows display and terminal networking hooks locked. Opening Windows Remote Desktop (`mstsc.exe`) afterward locks up indefinitely.
* **The Fix:** Sweeps for hidden deadlocked RDP client instances and restarts `TermService` (Remote Desktop Services) to release hooks without requiring a computer reboot.

### 4. "Another installation is already in progress" (.ica launch blocked / Error 1618)
* **The Root Cause:** Windows Installer (`msiexec.exe`) gets stuck in the background after an unnatural termination, blocking new `.ica` files or installer executions.
* **The Fix:** Forcefully clears stuck `msiexec.exe` background tasks and releases MSI mutex locks.

### 5. Blurry Text, Low Resolution, or Widescreen Caps
* **The Root Cause:** Compatibility flags or legacy `MaxMonitorDimension` registry limits clamp Citrix to lower resolutions or break High-DPI scaling across 4K and ultrawide monitors.
* **The Fix:** Configures native DPI awareness (`DpiAware=1`) in HKCU and HKLM Policies, removes `MaxMonitorDimension`, and clears corrupted Explorer window caches.

---

## Interactive Bot Menu

Simply execute `kill_citrix.ps1`. If running as a standard user, it will display the menu and automatically request Administrator elevation when executing repair operations:

```powershell
.\kill_citrix.ps1
```

```text
==========================================================================
                 CITRIX PROBLEM SOLVER & REPAIR BOT                      
                     [Administrator]                                     
==========================================================================
 What kind of fix do you need?

  [1] Regular Fix (Recommended for daily hangs & Alt-Tab)
      - Force-close frozen Citrix Receiver / Workspace sessions
      - Release deadlocked RDP hooks (fix Remote Desktop hanging)
      - Clear stuck msiexec background tasks
      - Restore High-DPI scaling & clear screen resolution caps
      - Enable Alt-Tab hotkey passthrough within sessions

  [2] Fix MSI & Installer Loop (Specialized Fix)
      - Target Error: 'The feature you are trying to use is on a network
        resource that is unavailable: ICAWebWrapper.msi / Online Plug-in'
      - Purge orphaned Windows Installer component locks (self-repair loops)
      - Remove stuck InstallHelper startup auto-run registry entries

  [3] Enable Alt-Tab Hotkey Passthrough (CTX232298) [NEW FEATURE]
      - Fix Alt+Tab switching local apps instead of Citrix session apps
      - Verifies Citrix installation before updating registry
      - Configures TransparentKeyPassthrough = remote (HKLM & HKCU)

  [4] Advanced Tools & Diagnostics (Verify, Hard Reset, etc.)

  [0] Exit
==========================================================================
```

---

## Command-Line & Automation Options

You can also run specific repair actions directly via command-line switches without the interactive menu:

| Switch / Parameter | Description |
| :--- | :--- |
| `.\kill_citrix.ps1 -Regular` | Runs standard cleanup: kills Citrix processes, resets RDP/msiexec deadlocks, restores DPI, and configures Alt-Tab hotkey passthrough. |
| `.\kill_citrix.ps1 -EnableAltTab` | **[NEW]** Verifies Citrix is installed and configures Alt-Tab hotkey passthrough (`TransparentKeyPassthrough=remote`, CTX232298). |
| `.\kill_citrix.ps1 -FixMSI` | Runs the MSI registry repair for `ICAWebWrapper.msi` (includes safety warning & Desktop backup). |
| `.\kill_citrix.ps1 -FixResolution` | Enables High-DPI awareness and clears monitor resolution limits. |
| `.\kill_citrix.ps1 -CleanFlags` | Purges Citrix DPI override flags from Windows AppCompat. |
| `.\kill_citrix.ps1 -Verify` | Performs a read-only health check on Citrix settings, Alt-Tab hotkey, and installer locks. |
| `.\kill_citrix.ps1 -HardReset` | Destructive wipe of local Citrix cache and HKCU settings (prompts for confirmation). |
| `.\kill_citrix.ps1 -FullFix` | Runs an end-to-end automated sequence (Kill + MSI Fix + RDP reset + DPI fix + Alt-Tab + Verify). |
| `.\kill_citrix.ps1 -Force` | Suppresses confirmation prompts (useful for automated IT deployments). |

---

## Standalone Scripts

Individual repair scripts can also be run independently:

* [`enable_citrix_alttab.ps1`](enable_citrix_alttab.ps1) - **[NEW]** Checks if Citrix is installed and configures `TransparentKeyPassthrough = "remote"` in HKLM and HKCU (CTX232298). Supports `-Force` and `-RestartCitrix`.
* [`fix_citrix_msi.ps1`](fix_citrix_msi.ps1) - Dedicated MSI and `ICAWebWrapper.msi` registry repair with safety warning and Desktop `.reg` backup.
* [`fix_citrix_resolution.ps1`](fix_citrix_resolution.ps1) - High-DPI scaling configuration.
* [`remove_resolution_limits.ps1`](remove_resolution_limits.ps1) - Removes `MaxMonitorDimension` cap.
* [`clean_compatibility_flags.ps1`](clean_compatibility_flags.ps1) - Cleans Windows AppCompat layers.
* [`verify_fix_status.ps1`](verify_fix_status.ps1) - Verifies current system configuration and Alt-Tab status.
* [`hard_reset_citrix.ps1`](hard_reset_citrix.ps1) - Full preference and cache reset with DPI and Alt-Tab re-application.
