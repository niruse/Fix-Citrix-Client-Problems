# Fix Citrix Client Problems

A PowerShell script to completely kill all Citrix Receiver/Workspace related processes and smoothly resolve the system hangs that usually follow a forceful termination.

## What this script solves

When you forcefully kill Citrix processes via Task Manager or conventional scripts, it often leaves the system in a hanging state, requiring a full Windows restart. This script forcefully closes Citrix and then actively repairs the specific subsystems that break as a result.

Specifically, it solves **two major issues** that happen after forcefully closing Citrix:

### 1. Remote Desktop (RDP) Hanging
When Citrix (`wfica32.exe`) is killed mid-session, it fails to release deep Windows networking and display hooks. If you attempt to open Windows Remote Desktop (`mstsc.exe`) afterward, it will completely lock up because it is waiting for those hooks. 
**The Fix:** This script automatically sweeps for hidden deadlocked RDP clients and forcefully restarts the background Windows `TermService` (Remote Desktop Services) to release the locks, allowing RDP to open instantly without a reboot.

### 2. "Another installation is already in progress" (.ica launch error)
When Windows detects that the Citrix Workspace app died unnaturally, it triggers an invisible "Self-Repair" using the Windows Installer service (`msiexec.exe`). Because the Citrix processes were forcefully killed, this hidden installer gets permanently stuck. When you then try to launch a fresh `.ica` file, you are blocked with an "installation in progress" error.
**The Fix:** This script sweeps and kills any stuck `msiexec.exe` processes caused by the Citrix self-repair bug, allowing new `.ica` files to open immediately.

## Usage

You must run this script as an **Administrator**. If you run it as a normal user, it will automatically prompt for Administrative privileges.

```powershell
.\kill_citrix.ps1
```
