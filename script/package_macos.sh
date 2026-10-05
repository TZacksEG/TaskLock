#!/usr/bin/env bash
# Builds distribution artifacts only. Never installs, launches, or stops TaskLock.
set -euo pipefail

TASKLOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLOCK_RELEASE="1.1.1-beta.1"
TASKLOCK_VERSION="1.1.1"
TASKLOCK_BUILD="3"
TASKLOCK_ID="app.tasklock.desktop"
TASKLOCK_NOTARIZE=0
case "${1:-}" in
  "") ;;
  --notarize) TASKLOCK_NOTARIZE=1 ;;
  --help|-h)
    printf '%s\n' 'Usage: script/package_macos.sh [--notarize]' \
      'Default: local ad-hoc signed, unnotarized beta; no uploads.' \
      '--notarize: requires DEVELOPER_ID_APPLICATION and NOTARYTOOL_PROFILE; uploads to Apple.'
    exit 0 ;;
  *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf 'Only one option is supported.\n' >&2; exit 2; }

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export MACOSX_DEPLOYMENT_TARGET=14.0
TASKLOCK_MODE="unnotarized-beta"
if [[ "$TASKLOCK_NOTARIZE" == 1 ]]; then
  : "${DEVELOPER_ID_APPLICATION:?Set a Developer ID Application signing identity.}"
  : "${NOTARYTOOL_PROFILE:?Set the name of an existing notarytool Keychain profile.}"
  [[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application: "* ]] || {
    printf 'A Developer ID Application identity is required for notarization.\n' >&2; exit 2;
  }
  TASKLOCK_MODE="notarized-beta"
fi
TASKLOCK_SCRATCH="$TASKLOCK_ROOT/work/distribution-build"
TASKLOCK_STAGE="$TASKLOCK_SCRATCH/package-$TASKLOCK_MODE"
TASKLOCK_PUBLISH="$TASKLOCK_ROOT/outputs/releases/macos/$TASKLOCK_RELEASE-$TASKLOCK_MODE"
TASKLOCK_OUT="$TASKLOCK_STAGE/release"
TASKLOCK_BASE="TaskLock-$TASKLOCK_RELEASE-macOS-universal-$TASKLOCK_MODE"
TASKLOCK_APP="$TASKLOCK_OUT/TaskLock.app"
TASKLOCK_MOUNT="$TASKLOCK_STAGE/verify-mount"
TASKLOCK_MOUNTED=0
TASKLOCK_BUILD_SUCCEEDED=0
cleanup() {
  if [[ "$TASKLOCK_MOUNTED" == 1 ]]; then
    hdiutil detach "$TASKLOCK_MOUNT" >/dev/null || hdiutil detach -force "$TASKLOCK_MOUNT" >/dev/null
  fi
  if [[ "$TASKLOCK_BUILD_SUCCEEDED" == 1 && -d "$TASKLOCK_STAGE" ]]; then
    # Successful builds publish archives and reports only. Removing the exact
    # task-owned stage prevents Spotlight/LaunchServices finding extra app copies.
    /bin/rm -rf -- "$TASKLOCK_STAGE"
  fi
}
trap cleanup EXIT
mkdir -p "$TASKLOCK_SCRATCH"
# These are generated, task-owned directories, never an installed application.
rm -rf "$TASKLOCK_STAGE"
mkdir -p "$TASKLOCK_STAGE" "$TASKLOCK_APP/Contents/MacOS" "$TASKLOCK_APP/Contents/Resources"

cd "$TASKLOCK_ROOT"
for TASKLOCK_ARCH in arm64 x86_64; do
  xcrun swift build --configuration release --product TaskLock --arch "$TASKLOCK_ARCH" \
    --scratch-path "$TASKLOCK_SCRATCH/$TASKLOCK_ARCH" \
    -Xswiftc -gnone \
    -Xswiftc -file-prefix-map -Xswiftc "$TASKLOCK_ROOT=."
  TASKLOCK_BIN_DIR="$(xcrun swift build --configuration release --arch "$TASKLOCK_ARCH" \
    --scratch-path "$TASKLOCK_SCRATCH/$TASKLOCK_ARCH" --show-bin-path)"
  cp "$TASKLOCK_BIN_DIR/TaskLock" "$TASKLOCK_STAGE/TaskLock-$TASKLOCK_ARCH"
done
xcrun lipo -create "$TASKLOCK_STAGE/TaskLock-arm64" "$TASKLOCK_STAGE/TaskLock-x86_64" \
  -output "$TASKLOCK_APP/Contents/MacOS/TaskLock"
xcrun strip -S -x "$TASKLOCK_APP/Contents/MacOS/TaskLock"
xcrun lipo "$TASKLOCK_APP/Contents/MacOS/TaskLock" -verify_arch arm64 x86_64
chmod 755 "$TASKLOCK_APP/Contents/MacOS/TaskLock"

cat > "$TASKLOCK_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TaskLock</string>
<key>CFBundleIdentifier</key><string>$TASKLOCK_ID</string>
<key>CFBundleName</key><string>TaskLock</string>
<key>CFBundleDisplayName</key><string>TaskLock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$TASKLOCK_VERSION</string>
<key>CFBundleVersion</key><string>$TASKLOCK_BUILD</string>
<key>TaskLockReleaseVersion</key><string>$TASKLOCK_RELEASE</string>
<key>TaskLockDistributionChannel</key><string>$TASKLOCK_MODE</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
<key>CFBundleIconFile</key><string>TaskLock</string>
</dict></plist>
PLIST
plutil -lint "$TASKLOCK_APP/Contents/Info.plist"
mkdir -p "$TASKLOCK_STAGE/icon"
xcrun swift script/make_icon.swift "$TASKLOCK_STAGE/icon"
iconutil -c icns "$TASKLOCK_STAGE/icon/TaskLock.iconset" -o "$TASKLOCK_APP/Contents/Resources/TaskLock.icns"

# No inherited developer files, preferences, user routine, entitlements, or custom
# designated requirement. Only the executable, icon, plist, and signature ship.
if [[ "$TASKLOCK_NOTARIZE" == 1 ]]; then
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp \
    --identifier "$TASKLOCK_ID" "$TASKLOCK_APP"
else
  codesign --force --sign - --options runtime --identifier "$TASKLOCK_ID" "$TASKLOCK_APP"
fi
codesign --verify --deep --strict "$TASKLOCK_APP"

notarize_archive() {
  local archive="$1" label="$2" result status submission
  result="$TASKLOCK_STAGE/notary-$label-result.json"
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait --output-format json > "$result"
  status="$(plutil -extract status raw -o - "$result")"
  submission="$(plutil -extract id raw -o - "$result")"
  xcrun notarytool log "$submission" --keychain-profile "$NOTARYTOOL_PROFILE" \
    "$TASKLOCK_STAGE/notary-$label-log.json"
  [[ "$status" == Accepted ]] || {
    printf 'Apple notarization did not accept %s. Inspect the private build logs.\n' "$label" >&2; return 1;
  }
}
if [[ "$TASKLOCK_NOTARIZE" == 1 ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$TASKLOCK_APP" "$TASKLOCK_STAGE/submission.zip"
  notarize_archive "$TASKLOCK_STAGE/submission.zip" app
  xcrun stapler staple "$TASKLOCK_APP"
  xcrun stapler validate "$TASKLOCK_APP"
fi

cat > "$TASKLOCK_OUT/Install-Guide.txt" <<GUIDE
TaskLock $TASKLOCK_RELEASE | macOS 14+ | Apple Silicon + Intel
Channel: $TASKLOCK_MODE

العربية
نسخة تجريبية. الواجهة الحالية بالعربية، والمهام تُحفظ على جهازك فقط.
1. افتح DMG واسحب TaskLock إلى Applications، أو فك ZIP وانقل التطبيق إلى Applications.
2. أخرج القرص الافتراضي، ثم افتح TaskLock من Applications. أغلق أي نسخة قديمة أولًا.
3. من System Settings > Privacy & Security > Accessibility فعّل TaskLock.
4. جرّب «معاينة ١٥ ثانية» أولًا، ثم أضف مهامك ووقت التجديد واضغط حفظ وتفعيل.
5. التشغيل عند تسجيل الدخول اختياري من «تشغيل تلقائي مع دخول الماك».
6. بعد إغلاق نافذة الإعدادات يظل TaskLock شغالًا من أيقونة الدرع في شريط القوائم، من غير أيقونة في Dock.
الشاشة تُفتح بعد تحديد كل المهام كمكتملة. البداية فارغة وغير مفعلة.
لا يحل التطبيق محل قفل macOS أو كلمة المرور، وليس حاجزًا أمنيًا يستحيل تجاوزه.
إيقاف الاستخدام: بعد إكمال المهام، عطّل الروتين والتشغيل التلقائي ثم أغلق التطبيق.
لحذف التطبيق: انقله إلى سلة المهملات بعد إغلاقه؛ تُترك بياناتك المحلية محفوظة.

English
Beta software. The current interface is Arabic. Tasks remain on your own Mac.
1. Open the DMG and drag TaskLock into Applications, or unzip and move the app there.
2. Eject the disk image, then open TaskLock from Applications. Quit any older copy first.
3. Enable TaskLock in System Settings > Privacy & Security > Accessibility.
4. Try the 15-second preview first. Add your tasks/reset time, then save and enable.
5. Launch at login is optional; enable it with the app's login toggle if wanted.
6. Closing the settings window keeps TaskLock running from its shield menu-bar icon, without a Dock icon.
The screen unlocks after you check every task. A fresh install starts empty and disabled.
TaskLock does not replace macOS authentication and is not an unbreakable security boundary.
To stop using it, finish the checklist, disable the routine and login toggle, then quit.
To uninstall, move the closed app to Trash. Local task data is retained.

Local data: ~/Library/Application Support/TaskLock-Desktop/
Bundle ID: app.tasklock.desktop
Signing and verification details: BUILD-VERIFICATION.txt next to the download.
Verify download integrity: shasum -a 256 -c SHA256SUMS.txt (from the download directory).
A matching checksum verifies file integrity, not publisher identity.
GUIDE
if [[ "$TASKLOCK_NOTARIZE" == 0 ]]; then
  cat >> "$TASKLOCK_OUT/Install-Guide.txt" <<'GUIDE'

UNNOTARIZED BETA — TEST DISTRIBUTION ONLY
هذه النسخة موقعة محليًا ad-hoc وليست موثّقة من Apple. قد يمنع macOS فتحها.
إذا كنت تثق بمصدر الملف، وبعد محاولة فتحه، استخدم Open Anyway من
System Settings > Privacy & Security إذا أتاحه النظام. لا تعطّل Gatekeeper.
بعض سياسات الأجهزة تمنعها تمامًا. نحتاج توقيع Developer ID وتوثيق Apple للتوزيع العام.
قد يطلب النظام إذن Accessibility مجددًا عند تغيير هذه النسخة التجريبية.

This app is ad-hoc signed, not Apple notarized. Gatekeeper may block it.
Only if you trust the source, after attempting to open it, use Open Anyway in
System Settings > Privacy & Security when offered. Do not disable Gatekeeper.
Managed-device policies may prevent opening it. General distribution needs a
Developer ID signature and Apple notarization. Accessibility may need reapproval after updates.
GUIDE
else
  cat >> "$TASKLOCK_OUT/Install-Guide.txt" <<'GUIDE'

DEVELOPER ID SIGNED AND APPLE NOTARIZED BETA
هذه الحزمة موقعة بهوية Developer ID ومرفق بها توثيق Apple. تظل نسخة تجريبية.
This package has a Developer ID signature and stapled Apple notarization tickets.
It remains beta software; signing does not replace functional testing.
GUIDE
fi

TASKLOCK_PAYLOAD="$TASKLOCK_STAGE/$TASKLOCK_BASE"
mkdir -p "$TASKLOCK_PAYLOAD"
ditto "$TASKLOCK_APP" "$TASKLOCK_PAYLOAD/TaskLock.app"
cp "$TASKLOCK_OUT/Install-Guide.txt" "$TASKLOCK_PAYLOAD/Install-Guide.txt"
ln -s /Applications "$TASKLOCK_PAYLOAD/Applications"
ditto -c -k --sequesterRsrc --keepParent "$TASKLOCK_PAYLOAD" "$TASKLOCK_OUT/$TASKLOCK_BASE.zip"
hdiutil create -volname "TaskLock 1.1 Beta" -srcfolder "$TASKLOCK_PAYLOAD" \
  -format UDZO -imagekey zlib-level=6 -ov "$TASKLOCK_OUT/$TASKLOCK_BASE.dmg"
if [[ "$TASKLOCK_NOTARIZE" == 1 ]]; then
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$TASKLOCK_OUT/$TASKLOCK_BASE.dmg"
  notarize_archive "$TASKLOCK_OUT/$TASKLOCK_BASE.dmg" dmg
  xcrun stapler staple "$TASKLOCK_OUT/$TASKLOCK_BASE.dmg"
  xcrun stapler validate "$TASKLOCK_OUT/$TASKLOCK_BASE.dmg"
fi

# Inspect both actual packaged payloads without launching the application.
mkdir -p "$TASKLOCK_STAGE/zip-verify" "$TASKLOCK_MOUNT"
ditto -x -k "$TASKLOCK_OUT/$TASKLOCK_BASE.zip" "$TASKLOCK_STAGE/zip-verify"
codesign --verify --deep --strict "$TASKLOCK_STAGE/zip-verify/$TASKLOCK_BASE/TaskLock.app"
cmp "$TASKLOCK_APP/Contents/MacOS/TaskLock" "$TASKLOCK_STAGE/zip-verify/$TASKLOCK_BASE/TaskLock.app/Contents/MacOS/TaskLock"
[[ "$(readlink "$TASKLOCK_STAGE/zip-verify/$TASKLOCK_BASE/Applications")" == /Applications ]]
hdiutil verify "$TASKLOCK_OUT/$TASKLOCK_BASE.dmg"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$TASKLOCK_MOUNT" "$TASKLOCK_OUT/$TASKLOCK_BASE.dmg" >/dev/null
TASKLOCK_MOUNTED=1
codesign --verify --deep --strict "$TASKLOCK_MOUNT/TaskLock.app"
cmp "$TASKLOCK_APP/Contents/MacOS/TaskLock" "$TASKLOCK_MOUNT/TaskLock.app/Contents/MacOS/TaskLock"
[[ "$(readlink "$TASKLOCK_MOUNT/Applications")" == /Applications ]]
hdiutil detach "$TASKLOCK_MOUNT" >/dev/null
TASKLOCK_MOUNTED=0

# Reject accidental developer paths before publishing the manifests. Do not print matches.
/usr/bin/strings -a "$TASKLOCK_APP/Contents/MacOS/TaskLock" > "$TASKLOCK_STAGE/binary-strings.txt"
if /usr/bin/grep -q '/Users/' "$TASKLOCK_STAGE/binary-strings.txt"; then
  printf 'Release binary contains a developer home path; refusing completion.\n' >&2
  exit 1
fi

cd "$TASKLOCK_OUT"
TASKLOCK_GATEKEEPER_STATUS=0
spctl --assess --type execute --verbose=4 TaskLock.app > "$TASKLOCK_STAGE/gatekeeper.txt" 2>&1 || TASKLOCK_GATEKEEPER_STATUS=$?
{
  printf 'TaskLock %s | build %s | %s\n' "$TASKLOCK_RELEASE" "$TASKLOCK_BUILD" "$TASKLOCK_MODE"
  printf 'Bundle ID: %s\nMinimum macOS: 14.0\n' "$TASKLOCK_ID"
  printf 'Built UTC: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '\nToolchain\n'; xcrun swift --version 2>&1
  printf '\nUniversal binary\n'; xcrun lipo -info TaskLock.app/Contents/MacOS/TaskLock
  xcrun vtool -show-build TaskLock.app/Contents/MacOS/TaskLock
  printf '\nSignature\n'
  codesign -dvvv TaskLock.app 2>&1 | sed 's|^Executable=.*|Executable=TaskLock.app/Contents/MacOS/TaskLock|'
  codesign --verify --deep --strict --verbose=2 TaskLock.app 2>&1
  printf '\nLinked libraries\n'; xcrun otool -L TaskLock.app/Contents/MacOS/TaskLock
  printf '\nGatekeeper assessment exit code: %s\n' "$TASKLOCK_GATEKEEPER_STATUS"
  cat "$TASKLOCK_STAGE/gatekeeper.txt"
  if [[ "$TASKLOCK_NOTARIZE" == 0 ]]; then
    printf 'Notarization: NOT SUBMITTED. This is an unnotarized, ad-hoc signed beta.\n'
  else
    printf 'Notarization: app and DMG accepted; tickets stapled and validated.\n'
  fi
  printf '\nInspection results\nZIP extracted: signature, binary, Applications link verified.\n'
  printf 'DMG verified and mounted read-only: signature, binary, Applications link verified; then detached.\n'
  printf 'No developer home paths detected in executable strings.\n'
  printf 'Payload contains only the app, bilingual install guide, and Applications link.\n'
  printf 'No task database, secrets, preferences, or personal developer files were packaged.\n'
  printf '\nScope\nUniversal arm64+x86_64 compilation is verified, not execution on an Intel Mac.\n'
  printf 'This packaging run did not install or launch the app or change the existing personal installation.\n'
  printf 'Gatekeeper readback is from this build Mac; it does not certify launch on a clean recipient Mac.\n'
  printf 'A release build procedure is reproducible; archives are not guaranteed byte-identical.\n'
} > BUILD-VERIFICATION.txt
if [[ "$TASKLOCK_NOTARIZE" == 1 && "$TASKLOCK_GATEKEEPER_STATUS" != 0 ]]; then
  printf 'Notarized app failed local Gatekeeper assessment. See BUILD-VERIFICATION.txt.\n' >&2
  exit 1
fi
shasum -a 256 "$TASKLOCK_BASE.zip" "$TASKLOCK_BASE.dmg" Install-Guide.txt BUILD-VERIFICATION.txt > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
# The installable app remains inside the verified ZIP and DMG. Do not publish a
# loose .app that LaunchServices can index as another runnable copy.
/bin/rm -rf -- "$TASKLOCK_OUT/TaskLock.app"
# A failed build or notarization never replaces the previously verified release.
mkdir -p "$(dirname "$TASKLOCK_PUBLISH")"
if [[ -d "$TASKLOCK_PUBLISH" ]]; then
  mv "$TASKLOCK_PUBLISH" "$TASKLOCK_STAGE/previous-release"
fi
if ! mv "$TASKLOCK_OUT" "$TASKLOCK_PUBLISH"; then
  if [[ -d "$TASKLOCK_STAGE/previous-release" ]]; then
    mv "$TASKLOCK_STAGE/previous-release" "$TASKLOCK_PUBLISH"
  fi
  exit 1
fi
TASKLOCK_BUILD_SUCCEEDED=1
printf '\nCreated: %s\nGatekeeper exit code: %s (see BUILD-VERIFICATION.txt)\n' "$TASKLOCK_PUBLISH" "$TASKLOCK_GATEKEEPER_STATUS"
