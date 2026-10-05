# TaskLock

### Finish your daily routine before starting on your computer

TaskLock is a native Mac and Windows app that places your daily checklist in the center of a desktop-covering screen. Complete your tasks away from the computer, check each one off, and the barrier disappears after the entire checklist is saved as complete.

**No accounts, backend, analytics, or cloud sync. Your routine stays on your device.**

[Repository downloads](download/) · [العربية](README.md) · [GitHub Releases](https://github.com/TZacksEG/TaskLock/releases) · [Report an issue](https://github.com/TZacksEG/TaskLock/issues) · [Validation report](docs/Release-status.md)

![Actual TaskLock macOS preview with sample tasks](docs/images/macos-preview.png)

*The image shows the Mac app with sample tasks. It is not a Windows screenshot or evidence of input filtering on every device.*

> **Current versions: Mac 1.1.1-beta.1 and Windows 1.1.0-beta.1 — pre-release.** The Mac package is not Apple notarized. Windows packages are unsigned, experimentally cross-built, and have not been run on a physical Windows machine. Review the validation section before relying on the barrier.

## Contents

- [Who it is for](#who-it-is-for)
- [Download and compatibility](#download-and-compatibility)
- [Features](#features)
- [Install on macOS](#install-on-macos)
- [Install on Windows](#install-on-windows)
- [Daily routine behavior](#daily-routine-behavior)
- [Login, sleep, and wake](#login-sleep-and-wake)
- [Privacy and storage](#privacy-and-storage)
- [Lock limitations and recovery](#lock-limitations-and-recovery)
- [What has been tested](#what-has-been-tested)
- [Build from source](#build-from-source)
- [Project structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [Updates and uninstalling](#updates-and-uninstalling)
- [Contributing and licensing](#contributing-and-licensing)

## Who it is for

Use TaskLock to make room for a small offline routine before getting absorbed in your computer: drink water, move around, tidy your workspace, read a paper book, or finish a morning habit.

Choose tasks you can perform **away from the computer**. A task requiring a browser or another desktop app is unsuitable for an input barrier on that same machine. Completion is self-reported; checking a task does not prove that you performed it.

Start with a short, manageable list and try the preview before enabling it. A new installation contains no personal tasks and starts with the routine disabled.

## Download and compatibility

Use the [Mac 1.1.1-beta.1 hotfix](https://github.com/TZacksEG/TaskLock/releases/tag/v1.1.1-beta.1) or the [Windows 1.1.0-beta.1 release](https://github.com/TZacksEG/TaskLock/releases/tag/v1.1.0-beta.1), then choose the matching asset:

| Platform | Download | Status |
|---|---|---|
| Apple Silicon or Intel Mac, macOS 14+ | [Download the Mac build](download/Mac/TaskLock-1.1.1-beta.1-macOS-universal-unnotarized-beta.dmg) | Universal binary; menu-bar agent with no Dock icon; ad-hoc signed, not notarized |
| Intel/AMD Windows PC, 64-bit | [Download Windows x64](download/Windows/TaskLock-1.1.0-beta.1-Windows-x64-experimental-beta.zip) | Experimental cross-build; native runtime untested |
| Windows on ARM64 | [Download Windows ARM64](download/Windows/TaskLock-1.1.0-beta.1-Windows-arm64-experimental-beta.zip) | Experimental ARM64 build; native runtime untested |

Windows packages include their .NET runtime; users do not need a separate .NET installation. Use a supported Windows 11 edition for initial testing. The source API target does not guarantee compatibility with every Windows 10 edition. See [Microsoft's supported Windows versions](https://learn.microsoft.com/en-us/dotnet/core/install/windows).

**To use the app**, download the DMG or the ZIP for your processor. GitHub's automatically generated **Source code** archives contain development files, not an installer.

Each package includes a bilingual install guide. The release also provides `SHA256SUMS.txt`; compare the checksum after downloading if you want to verify file integrity. Checksums do not authenticate the publisher.

## Features

- **Custom daily routine:** add tasks and choose a daily reset time, midnight by default.
- **Saved progress:** completion is persisted before it is acknowledged in the UI.
- **Same-day continuity:** completed tasks remain complete across process restarts until the next routine cycle.
- **One barrier per connected display:** display changes trigger rebuilding; actual multi-display testing remains pending.
- **15-second preview:** temporary sample tasks, automatic expiry, no modification of your real checklist.
- **Optional launch at login:** enabled through app settings, after OS sign-in.
- **macOS menu-bar agent:** closing the settings window leaves the routine running; the shield item reopens it without a Dock icon.
- **Arabic interface:** settings and labels are Arabic; task titles can contain other languages.
- **Storage recovery:** failed writes release the barrier and preserve the last successfully saved state.

## Install on macOS

1. Download and open the DMG.
2. Drag **TaskLock** into **Applications**.
3. Eject the image and open TaskLock from Applications. Quit any older copy first.
4. Enable TaskLock in **System Settings → Privacy & Security → Accessibility**. The app needs this permission for its session input filter.
5. Try **«معاينة ١٥ ثانية»** — the 15-second preview. Without Accessibility, this exercises the presentation only, not keyboard filtering.
6. Add tasks, choose the reset time, and press **«حفظ وتفعيل الروتين»** — save and enable the routine.
7. Optionally enable **«تشغيل تلقائي مع دخول الماك»** — launch at login. Approve it in Login Items if macOS asks.

After setup, close the settings window normally with its red button. TaskLock keeps running from the shield in the menu bar. Use **Quit TaskLock** from that menu only when you intend to stop the process after completing the routine.

### If macOS blocks the first launch

This beta is ad-hoc signed and not Apple notarized. If you trust the download source, attempt to open it, then use **Open Anyway** under **Privacy & Security** when the OS offers it. Do not disable Gatekeeper or run quarantine-removal scripts. Managed devices may prohibit this beta entirely.

Changing an ad-hoc build can require granting Accessibility again. See [Mac distribution](docs/Mac-distribution.md) for signing, notarization and package details.

## Install on Windows

1. Download the x64 or ARM64 ZIP for your processor and extract it fully.
2. Run **`Install.cmd`** for a per-user installation. Administrator elevation is not requested.
3. Alternatively, launch **`TaskLock.exe`** for portable use.
4. Try **«معاينة ١٥ ثانية»** before relying on the app. The preview expires automatically.
5. Enter tasks in the last row of the table and choose a reset time.
6. Press **«حفظ وتفعيل القفل»** — save and enable the barrier.
7. To launch at login, install first and then enable the setting. Startup requires a stable executable path.

The portable editor's **«حفظ مسودة وتثبيت»** action saves your edits as a **disabled draft** before installing and relaunching. Review the draft and explicitly enable it in the installed app.

The installer copies the executable into your account and creates a Start menu shortcut. It does not install a Windows service or register an Apps & Features uninstall entry. The tray icon opens settings or exits after the checklist is complete.

### Windows publisher warning

This beta has no Authenticode publisher signature. SmartScreen or managed-device policy may block it; do not disable Windows protection. Successful compilation does not establish that the native UI or input filtering works on your hardware. Use the [Windows runtime checklist](docs/Windows-testing.md), also included in each ZIP.

## Daily routine behavior

| Situation | Intended behavior |
|---|---|
| First launch | Empty task list and disabled routine |
| Enable a routine containing pending tasks | Show the barrier |
| Complete some tasks | Save progress and keep the barrier |
| Save completion of the last task | Release the barrier |
| Restart after completing the current cycle | Stay unlocked for that cycle |
| Reach the next configured reset boundary | Require the routine again |
| Skip several calendar days | Advance directly to the current cycle |
| Move the clock backwards | Preserve progress and never roll the saved cycle backwards |
| Rename or add a task when saving settings | Treat the changed/new task as pending |
| Encounter invalid storage or a failed write | Release filtering and show recovery |

For example, a **06:30** reset keeps a completed routine satisfied until 06:30 the next day. Calendar logic uses the local timezone and handles daylight-saving gaps and repeated times. There is no camera, activity surveillance, or external proof-of-completion system.

## Login, sleep, and wake

Shared builds use **opt-in** login startup. TaskLock launches after your user account signs in; it does not replace the OS password or its authentication screen.

The implementation is designed to restore pending tasks after sleep or session unlock and leave the desktop available if the current cycle is complete. Input filtering is suspended around system-lock/sleep transitions. Physical lid behavior, actual reboot/login and target hardware still need runtime validation, especially on Windows.

## Privacy and storage

The app has no accounts, analytics, network calls or cloud sync. It does not upload your routine to GitHub or Google Drive. Downloading a release is separate from the application's local operation.

| Build | Local data location |
|---|---|
| Public Mac release | `~/Library/Application Support/TaskLock-Desktop/routine.json` |
| Windows | `%LOCALAPPDATA%\TaskLock\routine.json` |
| Legacy Mac development build | `~/Library/Application Support/TaskLock/routine.json` |
| Isolated Mac test build | `~/Library/Application Support/TaskLock-Testing/` |

The file stores task titles and identifiers, completion identifiers, cycle date, reset time and enabled state. Writes use atomic replacement after successful serialization. Mac data files use owner-only permissions; Windows storage inherits the user directory's access controls.

To back up, finish the routine, quit the app and copy the platform's data directory somewhere you trust. Do not attach your real `routine.json` to a public issue. **The Mac and Windows formats are not a cross-platform synchronization contract; copying JSON between them is not a supported migration workflow.**

## Lock limitations and recovery

TaskLock is a personal commitment tool, not authentication software or an unbreakable system lockdown. Users with system recovery/admin controls can bypass or terminate it. Task completion is an honesty-based checkmark.

- **macOS:** AppKit shield windows, kiosk presentation options and an Accessibility-enabled session event tap. No persistent HID remapping.
- **Windows:** WinForms windows and low-level keyboard/mouse hooks. Ctrl+Alt+Delete, sign-in, UAC and recovery controls remain OS-owned.
- **Storage failures:** the barrier releases and the last saved progress remains authoritative.
- **Stalled Windows UI:** the input filter requires a refreshed three-second UI lease. Expiry stops filtering; a long hook-thread scheduling gap also invalidates the session.
- **Windows hook limitations:** the OS can silently remove a hook. A worker heartbeat measures thread liveness, not proof of continued filtering. See [Microsoft's hook documentation](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc).

Use ordinary OS recovery controls if the app malfunctions. During normal operation, complete the checklist before disabling the routine or quitting from the app's menu.

## What has been tested

| Check | Latest available evidence |
|---|---|
| Swift routine/storage logic | **18 tests passed** |
| Portable .NET routine/storage/pointer logic | **33 tests passed on macOS** |
| Universal Mac compilation, local signature and package integrity | Passed |
| Apple notarization/Gatekeeper approval | Not notarized; local assessment rejected the package |
| Actual Intel Mac execution | Not tested |
| Full macOS input filtering with Accessibility on the build machine | Not verified; Accessibility was not granted during the earlier UI test |
| Windows x64/ARM64 compilation and PE/package inspection | Passed |
| Native Windows UI, hooks, installation, startup and sleep/wake | **Not tested on a Windows machine** |
| Real multi-display, mixed-DPI, lid and reboot behavior | Requires device testing |

There are **51 passing automated tests**. Read the [release validation report](docs/Release-status.md). Logic and packaging checks do not substitute for native OS testing.

## Build from source

### macOS

Use macOS 14+ and a full Xcode installation containing Swift 6 and XCTest:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./script/package_macos.sh
```

Output: `outputs/releases/macos/1.1.1-beta.1-unnotarized-beta/`. The packaging script builds both architectures, produces a universal app, ZIP, DMG, verification report and checksums. It does not install or launch the app, and it removes temporary loose `.app` copies after a successful package run.

An explicit Developer ID/notarytool path is implemented for maintainers with an appropriate identity and Keychain profile. It submits artifacts to Apple and was not exercised with a publisher account for this release. See [Mac distribution](docs/Mac-distribution.md).

### Windows logic tests and builds

`global.json` pins SDK **10.0.401**, allowing compatible patch roll-forward. Run the portable tests from the repository root:

```sh
dotnet run --project Windows/TaskLock.Core.Tests -c Release
```

On macOS with Python 3 and the matching SDK:

```sh
TASKLOCK_DOTNET="$(command -v dotnet)" ./script/package_windows.sh
```

For direct native Windows publishing:

```powershell
dotnet publish Windows/TaskLock.Windows -c Release -r win-x64 --self-contained true -o work/windows-x64
dotnet publish Windows/TaskLock.Windows -c Release -r win-arm64 --self-contained true -o work/windows-arm64
```

The initial restore needs internet access for build/runtime packs. The packaging script does not install the SDK automatically. Each published app carries its runtime; servicing that runtime requires rebuilding and releasing the app. See [Windows distribution](docs/Windows-distribution.md).

### Isolated Mac verification harness

```sh
./script/build_and_run.sh --test-build
open -n 'work/TaskLock Test.app' --args --smoke-test
# After the first test exits:
open -n 'work/TaskLock Test.app' --args --storage-failure-test
```

The harness uses a separate app identity and isolated data. `inputGateActive=false` means it did not exercise the input tap. Avoid the legacy development helper's default/install modes when preparing public releases: some replace `/Applications/TaskLock.app`. Use the dedicated packaging script for distribution.

## Project structure

```text
Sources/TaskLock/             Mac UI, windows and input handling
Sources/TaskLockCore/         Mac routine and persistence
Tests/TaskLockCoreTests/      Swift tests
Windows/TaskLock.Core/       Platform-neutral Windows routine logic
Windows/TaskLock.Core.Tests/ Portable .NET tests
Windows/TaskLock.Windows/    WinForms UI, windows, input hooks and startup
Windows/ThirdParty/          Bundled runtime licenses/notices
script/                     Build, packaging and verification scripts
docs/                       Distribution guides, device checklist and image
```

The platforms have separate native implementations with comparable routine behavior. There is no shared backend or Electron shell. Large binary packages belong in Releases, not source history.

## Troubleshooting

| Problem | Check |
|---|---|
| macOS blocks opening | Unnotarized beta status and OS-provided Open Anyway, when available |
| Mac routine will not activate | Accessibility grant; the app may need reopening after permission changes |
| Windows blocks the EXE | SmartScreen/device policy; this is an unsigned publisher beta |
| Startup does not work | Install first, enable the app toggle; check macOS Login Items if applicable |
| No barrier after restart | The current cycle may already be complete, or the routine may be disabled |
| Old Mac data is absent | Public and legacy development builds intentionally use separate data directories |
| Storage recovery appears | Preserve the original file, check disk space/directory permissions, then retry |
| Windows cannot replace an existing installed EXE | Finish the routine and quit the previous process before reinstalling |
| Input or displays behave differently | Report OS/architecture, monitor layout and DPI; these native paths need hardware testing |

## Updates and uninstalling

**Update:** finish the routine, quit the app and replace it with a package from the same release channel. The data directory is separate from the executable. This release has no automatic updater. Mac Accessibility permission may need reapproval when an ad-hoc signature changes.

**macOS removal:** disable the routine and login toggle, quit the app and move it to Trash. Your data directory is retained.

**Windows removal:** complete the checklist, quit the tray app and run `Uninstall.cmd` from the extracted package. It removes its executable, shortcut and startup registration while retaining routine data. Deleting that data directory is a separate choice if you want a clean start.

## Contributing and licensing

Useful reports include the TaskLock version, OS version, architecture, reproduction steps, expected/observed behavior and display/DPI details where relevant. Use sample tasks in screenshots and remove personal information.

Run the relevant platform tests before submitting a change, and distinguish real-device tests from compilation. Windows hardware validation, publisher signing/notarization and an English UI are future work, not completed features.

A project-wide source license has not been selected yet. .NET and third-party notices are included in [Windows/ThirdParty](Windows/ThirdParty) and the Windows packages. Never commit signing keys, passwords, private task files or local project memory.
