#!/usr/bin/env bash
set -euo pipefail
TASKLOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASKLOCK_ROOT"
MODE="${1:-run}"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
case "$MODE" in
  run|--verify|--install|--logs|--telemetry|--build|--test-build) ;;
  *) echo "Usage: $0 [--build|--install|--verify|--test-build|--logs|--telemetry]" >&2; exit 2 ;;
esac
swift build
TASKLOCK_BINARY="$(swift build --show-bin-path)/TaskLock"
TASKLOCK_ID="local.tamer.TaskLock"
TASKLOCK_NAME="TaskLock"
TASKLOCK_BUNDLE="$TASKLOCK_ROOT/outputs/TaskLock.app"
TASKLOCK_INSTALL_STAGE=""
if [[ "$MODE" == "--install" ]]; then
  mkdir -p "$TASKLOCK_ROOT/work"
  TASKLOCK_INSTALL_STAGE="$(mktemp -d "$TASKLOCK_ROOT/work/tasklock-install.XXXXXX")"
  TASKLOCK_BUNDLE="$TASKLOCK_INSTALL_STAGE/TaskLock.app"
  trap '[[ -z "$TASKLOCK_INSTALL_STAGE" ]] || /bin/rm -rf -- "$TASKLOCK_INSTALL_STAGE"' EXIT
fi
if [[ "$MODE" == "--test-build" ]]; then
  TASKLOCK_ID="local.tamer.TaskLock.test"
  TASKLOCK_NAME="TaskLock Test"
  TASKLOCK_BUNDLE="$TASKLOCK_ROOT/work/TaskLock Test.app"
fi
mkdir -p "$TASKLOCK_BUNDLE/Contents/MacOS" "$TASKLOCK_BUNDLE/Contents/Resources"
cp "$TASKLOCK_BINARY" "$TASKLOCK_BUNDLE/Contents/MacOS/TaskLock"
cat > "$TASKLOCK_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TaskLock</string>
<key>CFBundleIdentifier</key><string>$TASKLOCK_ID</string>
<key>CFBundleName</key><string>$TASKLOCK_NAME</string>
<key>CFBundleDisplayName</key><string>$TASKLOCK_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
<key>CFBundleIconFile</key><string>TaskLock</string>
</dict></plist>
PLIST
if [[ ! -f "$TASKLOCK_ROOT/work/TaskLock.icns" ]]; then
  swift script/make_icon.swift "$TASKLOCK_ROOT/work"
  iconutil -c icns "$TASKLOCK_ROOT/work/TaskLock.iconset" -o "$TASKLOCK_ROOT/work/TaskLock.icns"
fi
cp "$TASKLOCK_ROOT/work/TaskLock.icns" "$TASKLOCK_BUNDLE/Contents/Resources/TaskLock.icns"
codesign --force --sign - --identifier "$TASKLOCK_ID" -r="designated => identifier \"$TASKLOCK_ID\"" "$TASKLOCK_BUNDLE"
codesign --verify --strict "$TASKLOCK_BUNDLE"
if [[ "$MODE" == "--build" || "$MODE" == "--test-build" ]]; then
  echo "Built: $TASKLOCK_BUNDLE"
  exit 0
fi
# Only stop this app, never shared tools or unrelated tasks.
pkill -x TaskLock >/dev/null 2>&1 || true
if [[ "$MODE" == "--install" ]]; then
  TASKLOCK_INSTALL_TARGET="/Applications/TaskLock.app"
  [[ "$TASKLOCK_INSTALL_TARGET" == "/Applications/TaskLock.app" ]] || exit 3
  if [[ -e "$TASKLOCK_INSTALL_TARGET" ]]; then
    /bin/rm -rf -- "$TASKLOCK_INSTALL_TARGET"
  fi
  ditto "$TASKLOCK_BUNDLE" "$TASKLOCK_INSTALL_TARGET"
  TASKLOCK_BUNDLE="$TASKLOCK_INSTALL_TARGET"
fi
/usr/bin/open -n "$TASKLOCK_BUNDLE"
case "$MODE" in
  --verify|--install) sleep 1; pgrep -x TaskLock >/dev/null; echo "Launched: $TASKLOCK_BUNDLE" ;;
  --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'process == "TaskLock"' ;;
esac
