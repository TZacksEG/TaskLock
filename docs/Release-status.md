# Release validation — Mac 1.1.1-beta.1 / Windows 1.1.0-beta.1

Validation date: 2026-10-05. These are pre-releases with explicit platform-testing gaps.

| Scope | Evidence | Result |
|---|---|---|
| Swift routine and persistence | 18 XCTest cases; date boundaries, DST, backwards clock, atomic writes and corruption handling | PASS |
| Windows portable core | 33 .NET console tests on macOS; routine cycles, editing, installation drafts, persistence failures and pointer rules | PASS |
| Mac build | Universal arm64+x86_64; deployment target macOS 14 on both slices | PASS |
| Mac package integrity | Strict ad-hoc codesign, ZIP extraction, read-only DMG mount comparison, SHA-256 readback | PASS |
| Mac menu-bar lifecycle | Accessory activation policy, `LSUIElement`, status-item presence, settings close without process exit, and settings reopen from menu | PASS |
| Apple trust | No Developer ID identity; no notarization submission; local Gatekeeper returned exit 3, rejected | NOT APPROVED |
| Mac original UI | Bounded native preview and completion/storage-failure paths on one Apple Silicon machine | OBSERVED IN DEVELOPMENT |
| Full Mac input filtering | Accessibility was not granted during the previous development UI test | NOT VERIFIED |
| Actual Intel execution | Cross-compilation only | NOT TESTED |
| Windows builds | win-x64 and win-arm64, .NET SDK 10.0.401, runtime 10.0.12 | PASS |
| Windows payloads | PE architecture, Windows GUI subsystem, asInvoker manifest, embedded resources/notices, ZIP extraction and hashes | PASS |
| Windows publisher signature | No Authenticode certificate | UNSIGNED |
| Windows native execution | UI, hooks, installation, startup, sleep/wake, secure desktop, multiple displays and mixed DPI | NOT TESTED |

## What the tests establish

The 51 automated tests validate the routine and persistence logic and the tested pointer-policy decisions. The packaging checks validate the exact architecture and bytes produced. Neither proves that an operating system will allow the app to open or that its input barrier will work under every desktop/session condition.

## Review corrections included

- A Windows installation from the editor saves unsaved input as a disabled draft before relaunch.
- Time-change notifications clear Windows' cached timezone rules before reconciliation.
- The Windows hook thread requires a renewed three-second UI lease. Expiry releases filtering.
- A hook-thread scheduling gap longer than 750 ms invalidates the session conservatively.
- Hook heartbeat is documented as thread liveness, not proof of continued OS hook registration.
- Runtime license notices are embedded and included in Windows packages.
- Public Mac data and app identity are isolated from the original development build. Launch at login is opt-in for recipients.
- The Mac app runs as a menu-bar agent with no Dock icon. Successful packaging removes loose staged app copies after producing the ZIP and DMG.

## Required device testing

Follow [Windows-testing.md](Windows-testing.md) on real x64/ARM64 Windows systems. For Mac, exercise current Accessibility grants, Intel hardware, multiple displays, gestures, actual sign-out/reboot and physical sleep/lid transitions. Record OS version, architecture, display arrangement, package SHA-256 and observed results. Do not mark these checks passed solely because a build succeeds.
