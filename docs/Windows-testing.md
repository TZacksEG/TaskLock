# Windows beta acceptance checklist

Status: **native runtime not tested**. macOS cross-compilation and portable core tests are evidence for code/build behavior only. Run this on supported Windows 11 x64 and Windows 11 ARM64 before promoting the beta. The application targets Windows APIs available from 10.0.17763, but this does not promise support on every Windows 10 edition. See [Microsoft's .NET OS support table](https://learn.microsoft.com/en-us/dotnet/core/install/windows).

## First-run and recovery

- Unzip and launch under a standard account. Confirm no elevation request, no initial tasks, no initial barrier, and startup off.
- Try the 15-second sample preview. Confirm keyboard attempts increment the count shown after the preview, only task-list clicks/scrolling work, and input returns at expiry. Verify Escape, Alt+Tab, Windows key, right/middle click and system gestures. Do not treat a hook thread heartbeat as proof that filtering works.
- While the preview runs, test the normal Windows secure attention/recovery path. Ctrl+Alt+Delete must remain OS-owned. Returning to the app should rebuild the pending barrier. It must not draw or intercept input on sign-in or UAC secure desktop.
- Test a deliberately stalled UI in a debugger during preview: filtering must fail open after the three-second UI lease expires. A hook message-loop gap over 750 ms must invalidate the session and release the barrier when the UI resumes. The hook APIs cannot prove continued hook presence after OS removal; this is mitigation, not a security guarantee.

## Daily routine and persistence

- Add three easy tasks, choose a reset time a few minutes ahead, then activate. Check one task; it must remain locked until all tasks are saved complete.
- Restart the process with one task complete; that completion must remain. Complete all tasks, restart again; the desktop must remain available that day.
- Sleep and wake; physically close/reopen a laptop lid where applicable. Pending tasks must reappear after sign-in. Completed tasks must not reopen before the reset boundary.
- Test lock/unlock, UAC, remote-session disconnect/reconnect and logout/restart. Sign-in authentication and shutdown must remain normal.
- At the next daily boundary tasks reset once. Change timezone while the process runs and verify new local rules. Moving the clock backwards must not erase completion or roll the stored cycle backwards.
- In an isolated test account, deny writes to the task directory. Failed completion must release filtering, leave previous progress intact and show recovery. Restore access and retry; configuration and progress must reload.
- In that isolated account, use a corrupt JSON file. The app must report recovery, keep the corrupt bytes untouched and remain unlocked.

## Displays and installation

- Test two displays, one left of the primary (negative coordinates), mixed 100%/150%/200% scaling, portrait layout, hotplug and DPI changes. Every display must be covered and task rows must remain clickable. Test long Arabic/English task names, 100 rows and scrolling.
- In the portable editor, type tasks without activating, then use “حفظ مسودة وتثبيت”. The installed copy must reopen those tasks as a disabled draft, preserving text and reset time.
- Enable startup after installation. Read the HKCU Run entry and perform a real sign-out/sign-in and reboot. Pending tasks should lock after sign-in; completed tasks should stay unlocked.
- Quit the app after completing tasks and run Uninstall.cmd. Confirm its own executable, Start menu shortcut and startup entry are removed, with routine.json preserved and input unaffected.

Record Windows edition/version, architecture, display layout/DPI, package SHA-256, observed results and screenshots. No item above is marked passed in this release.
