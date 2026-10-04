# TaskLock Windows experimental beta

The Windows implementation uses .NET 10 WinForms with a platform-neutral routine library. The interface is Arabic; the installation guide is Arabic/English. Two self-contained single-executable ZIPs are produced for `win-x64` and `win-arm64`. There is no separate .NET installation and no service or administrator elevation.

Portable execution is supported. Explicit per-user installation copies the executable into `%LOCALAPPDATA%\Programs\TaskLock`, creates a Start menu shortcut, and reopens settings. Installing from the editor first saves its contents as a disabled draft. Launch at login is a separate, opt-in HKCU Run registration and begins after Windows sign-in. Data is stored separately at `%LOCALAPPDATA%\TaskLock\routine.json`; uninstall preserves it.

A dedicated message-loop thread owns `WH_KEYBOARD_LL` and `WH_MOUSE_LL`. Task-list rectangles allow left clicks and scrolling only while TaskLock has foreground focus. Keyboard and other pointer events are filtered during an active routine. The UI renews a three-second lease; callback/worker expiry makes filtering fail open. A hook-thread scheduling gap over 750 ms invalidates the session. These are recovery measures. Windows may silently remove low-level hooks; the heartbeat is not proof of continued input blocking. [Microsoft hook documentation](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc).

The app releases its filtering on session lock/sleep, checks the active desktop, and rebuilds after return when tasks remain. Time-change notifications refresh cached timezone rules. It does not alter Ctrl+Alt+Delete, sign-in, UAC, Task Manager policy, registry security settings, or OS recovery controls. It is a personal focus barrier, not an authentication/security product.

## Build

Install the SDK pinned in `global.json` (10.0.401), then on macOS/Linux with Python 3 and Windows targeting enabled:

```sh
TASKLOCK_DOTNET=/absolute/path/to/dotnet ./script/package_windows.sh
```

The script runs the portable tests, publishes each architecture sequentially, checks PE architecture/GUI subsystem/asInvoker, checks the strict payload allowlist and paths, verifies ZIP extraction/CRC, and writes local archives. It never launches the Windows executable or uploads files. NuGet targeting/runtime packs are fetched during restore. [Microsoft cross-targeting documentation](https://learn.microsoft.com/en-us/dotnet/core/tools/sdk-errors/netsdk1100), [self-contained single-file deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview).

On Windows with that SDK installed:

```powershell
dotnet run --project Windows/TaskLock.Core.Tests -c Release
dotnet publish Windows/TaskLock.Windows -c Release -r win-x64 --self-contained true -o work/windows-native-x64
# Use win-arm64 on the ARM64 validation machine.
```

## Release status

Version `1.1.0-beta.1` is **unsigned and experimentally cross-built**. Authenticode/SmartScreen acceptance is not claimed. The first Windows run, native input filtering, installation, startup, sleep/wake, secure desktop, multiple displays and mixed DPI all remain unverified. Complete [Windows-testing.md](Windows-testing.md) before wider distribution. Keep this status in the download description and guide. Do not label a passing cross-build as a tested Windows release.

Use supported Windows 11 editions for initial validation. The API target is 10.0.17763; Microsoft limits current .NET support on Windows 10 to specific servicing/Enterprise editions. [Current supported Windows versions](https://learn.microsoft.com/en-us/dotnet/core/install/windows).

The app makes no network calls and has no accounts, telemetry or cloud sync. Its bundled runtime must be rebuilt when security updates are adopted; a recipient's separate .NET update does not update a self-contained copy. Keep SDK/runtime patch maintenance part of subsequent releases.
