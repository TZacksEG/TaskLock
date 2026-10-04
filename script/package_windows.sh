#!/usr/bin/env bash
# Cross-build only; never executes Windows binaries or publishes remotely.
set -euo pipefail
TASKLOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASKLOCK_ROOT"
TASKLOCK_DOTNET="${TASKLOCK_DOTNET:-$TASKLOCK_ROOT/work/toolchains/dotnet/dotnet}"
if [[ ! -x "$TASKLOCK_DOTNET" ]]; then TASKLOCK_DOTNET="$(command -v dotnet)"; fi
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_GENERATE_ASPNET_CERTIFICATE=false
export DOTNET_CLI_HOME="$TASKLOCK_ROOT/work/dotnet-home" NUGET_PACKAGES="$TASKLOCK_ROOT/work/nuget"
TASKLOCK_STAGE="$TASKLOCK_ROOT/work/windows-release"
mkdir -p "$TASKLOCK_STAGE"
"$TASKLOCK_DOTNET" run --project Windows/TaskLock.Core.Tests -c Release > "$TASKLOCK_STAGE/core-tests.txt"
cat "$TASKLOCK_STAGE/core-tests.txt"
for TASKLOCK_RID in win-x64 win-arm64; do
  TASKLOCK_PUBLISH="$TASKLOCK_STAGE/$TASKLOCK_RID"
  rm -rf "$TASKLOCK_PUBLISH"
  "$TASKLOCK_DOTNET" publish Windows/TaskLock.Windows/TaskLock.Windows.csproj -c Release \
    -r "$TASKLOCK_RID" --self-contained true -o "$TASKLOCK_PUBLISH" --nologo
  python3 script/verify_windows_package.py "$TASKLOCK_RID" "$TASKLOCK_PUBLISH" "$TASKLOCK_STAGE"
done
python3 - <<'PY'
from pathlib import Path
import hashlib
import shutil
root = Path.cwd()
out = root / 'outputs/releases/windows/1.1.0-beta.1'
shutil.copy2(root / 'Windows/Install-Guide.txt', out / 'Install-Guide.txt')
shutil.copy2(root / 'docs/Windows-testing.md', out / 'Runtime-test-checklist.md')
shutil.copy2(root / 'work/windows-release/core-tests.txt', out / 'Core-test-results.txt')
manifest = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in sorted(out.iterdir()) if p.is_file() and p.name != 'SHA256SUMS.txt')
(out / 'SHA256SUMS.txt').write_text(manifest)
PY
