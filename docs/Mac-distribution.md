# TaskLock for Mac distribution

The release script builds **1.1.0-beta.1**, build **2**, for **macOS 14 or later**, with **arm64 and x86_64** slices. The public bundle ID is `app.tasklock.desktop`. The existing personal installation is not installed over, launched, or stopped by packaging.

## Build a local test package

Run from the repository root on a Mac with full Xcode installed:

```sh
./script/package_macos.sh
```

The default is an **ad-hoc signed, unnotarized beta**, even if signing environment variables happen to be set. No upload occurs. It is intended for informed testers and may be blocked by Gatekeeper or managed-device policies.

Outputs are in `outputs/releases/macos/1.1.0-beta.1-unnotarized-beta/`:

- `TaskLock.app`
- `TaskLock-1.1.0-beta.1-macOS-universal-unnotarized-beta.zip`
- `TaskLock-1.1.0-beta.1-macOS-universal-unnotarized-beta.dmg`
- `Install-Guide.txt` — concise Arabic and English setup instructions, also inside both archives
- `BUILD-VERIFICATION.txt` — architecture, minimum OS, signature, linked libraries, actual Gatekeeper result, and verification limits
- `SHA256SUMS.txt` — archive/document hashes; integrity only, not publisher authentication

Both package formats include the app, the install guide, and an Applications shortcut. They include no task data, secrets, source files, or personal developer paths. Full build caches, temporary images, and unshared diagnostic logs stay under `work/distribution-build/`. Separate architecture scratch paths avoid the primary SwiftPM build lock. Re-running performs the same build and validation workflow, but filesystem timestamps/signatures mean byte-identical artifacts are not promised.

## What users should expect

The app currently has an Arabic interface. Install it in `/Applications`, enable Accessibility for TaskLock, try the bounded 15-second preview, and then enter and activate a personal routine. Launch at login is opt-in. A fresh routine is empty and disabled. Public data lives at `~/Library/Application Support/TaskLock-Desktop/`, separate from the personal development app. Quit an older copy before opening the public beta; the app prevents concurrent copies from competing.

For this unnotarized beta, macOS may block the first open. Informed testers who trust the source can use the system's **Privacy & Security → Open Anyway** option when it is offered. Do not disable Gatekeeper or use quarantine-removal scripts. Some managed Macs cannot run an ad-hoc beta. A new ad-hoc build can require Accessibility permission again. TaskLock is a focus aid, not a substitute for macOS authentication or an unbreakable security boundary.

The script verifies the compiled Intel slice; that is **not evidence of actual Intel Mac execution**. New recipient Macs, physical sleep/wake, multiple displays, current Accessibility grants, and login behavior still require runtime testing. Packaging itself never launches the barrier.

## Developer ID and notarization

General distribution requires a valid **Developer ID Application** identity in the signing Keychain and an existing authenticated **notarytool Keychain profile**. Keep account credentials in Keychain, not this repository. The default package remains explicitly unnotarized until the following opt-in command succeeds:

```sh
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Organization (TEAMID)' \
NOTARYTOOL_PROFILE='your-existing-keychain-profile' \
./script/package_macos.sh --notarize
```

**`--notarize` authorizes network submission to Apple.** Without it, the script never submits anything and ignores those identity/profile variables. This workflow has been prepared but has not been exercised with a valid identity/profile in this workspace.

The opt-in workflow signs the app with hardened runtime and a secure timestamp, submits an app ZIP, checks the accepted result, downloads the notary log, staples and validates the app ticket, builds the final ZIP and DMG, then signs/submits/staples/validates the DMG. It requires the final app to pass local Gatekeeper assessment. No custom designated requirement is injected. No sandbox or exceptional runtime entitlements are invented. Review the fetched notary logs for warnings before publishing.

Notarized outputs use a separate `1.1.0-beta.1-notarized-beta/` directory, so an unnotarized artifact is never relabeled as approved. A notarization or verification failure stops the script before publishing the staged files, preserving the previous verified release. Do not distribute intermediate files from `work/`.

## Metadata and validation

Apple requires the short bundle version to be numeric, so `CFBundleShortVersionString` is `1.1.0`, `CFBundleVersion` is `2`, and `TaskLockReleaseVersion` preserves `1.1.0-beta.1`. Artifact names and the guide also retain the beta label. [Apple's bundle-version format](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring).

The script checks `lipo` architecture membership, per-slice build metadata, strict code signatures, linked libraries, developer path leakage, ZIP extraction, DMG integrity and mounted contents, and SHA-256 readback. Disk images mount read-only without opening Finder or TaskLock and are detached after inspection. The actual `spctl` output and exit code are retained; an intact ad-hoc signature does not imply Gatekeeper acceptance. [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
