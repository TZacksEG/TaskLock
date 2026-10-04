"""Validate PE metadata and package only an allowlisted self-contained payload."""
from pathlib import Path
import hashlib
import json
import shutil
import struct
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
rid, publish_arg, stage_arg = sys.argv[1:]
assert rid in ("win-x64", "win-arm64")
publish, stage = Path(publish_arg), Path(stage_arg)
exe = publish / "TaskLock.exe"
files = sorted(p.name for p in publish.iterdir())
assert files == ["TaskLock.exe"], f"Unexpected publish payload: {files}"
blob = exe.read_bytes()
assert blob[:2] == b"MZ"
pe = struct.unpack_from("<I", blob, 0x3c)[0]
assert blob[pe:pe+4] == b"PE\0\0"
machine = struct.unpack_from("<H", blob, pe + 4)[0]
assert machine == {"win-x64": 0x8664, "win-arm64": 0xaa64}[rid]
optional = pe + 24
assert struct.unpack_from("<H", blob, optional)[0] == 0x20b  # PE32+
assert struct.unpack_from("<H", blob, optional + 68)[0] == 2  # Windows GUI
certificate_offset, certificate_size = struct.unpack_from("<II", blob, optional + 112 + 4 * 8)
assert certificate_offset == certificate_size == 0, "Update signing/verification report before shipping signed artifacts."
assert b"asInvoker" in blob, "Manifest must not request administrator elevation."
assert b"/Users/" not in blob and b"ProjectSecrets" not in blob
assert len(blob) > 20_000_000, "Expected the bundled self-contained runtime."
# Check our uncompressed assemblies too; the executable bundles compressed files.
for assembly in (root / "Windows").glob("*/bin/Release/**/TaskLock*.dll"):
    data = assembly.read_bytes()
    assert b"/Users/" not in data and "/Users/".encode("utf-16le") not in data

deps_path = next((root / "Windows" / "TaskLock.Windows" / "bin" / "Release").glob(f"**/{rid}/TaskLock.deps.json"))
runtime_versions = {k.split("/", 1)[0].removeprefix("runtimepack."): k.split("/", 1)[1]
                    for k in json.loads(deps_path.read_text())["libraries"] if "Runtime.win-" in k}
assert len(runtime_versions) == 2
for pack, pack_version in runtime_versions.items():
    package = root / "work" / "nuget" / pack.lower() / pack_version
    license_path = next(p for p in package.iterdir() if p.name.lower() in ("license", "license.txt"))
    assert license_path.read_text().strip() == (root / "Windows/ThirdParty/DOTNET-LICENSE.txt").read_text().strip(), "Refresh embedded runtime license before packaging."
    notices = package / "THIRD-PARTY-NOTICES.TXT"
    if notices.exists():
        assert notices.read_bytes() == (root / "Windows/ThirdParty/DOTNET-THIRD-PARTY-NOTICES.txt").read_bytes(), "Refresh embedded third-party notices before packaging."
own_assembly = deps_path.with_name("TaskLock.dll").read_bytes()
for resource in (b"TaskLock.Windows.Assets.TaskLock.ico", b"TaskLock.Notices.DOTNET-LICENSE.txt", b"TaskLock.Notices.DOTNET-THIRD-PARTY-NOTICES.txt"):
    assert resource in own_assembly, f"Missing embedded resource: {resource.decode()}"
version = "1.1.0-beta.1"
name = f"TaskLock-{version}-Windows-{rid.removeprefix('win-')}-experimental-beta"
payload = stage / name
if payload.exists(): shutil.rmtree(payload)
payload.mkdir()
shutil.copy2(exe, payload / "TaskLock.exe")
for item in ("Install-Guide.txt", "Install.cmd", "Uninstall.cmd"):
    raw = (root / "Windows" / item).read_text()
    (payload / item).write_bytes(raw.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
shutil.copy2(root / "docs" / "Windows-testing.md", payload / "Runtime-test-checklist.md")
for notice in (root / "Windows" / "ThirdParty").glob("*.txt"):
    shutil.copy2(notice, payload / notice.name)
report = {
    "release": version, "rid": rid, "machine": hex(machine), "subsystem": "Windows GUI",
    "packaging": "self-contained .NET 10 WinForms, single executable, runtime notices included", "runtime_packs": runtime_versions, "publisher_signature": "UNSIGNED",
    "verification": ["PE architecture", "asInvoker manifest", "one-file publish payload", "no developer home paths in own assemblies", "portable core tests passed on macOS"],
    "native_windows_execution": "NOT TESTED", "gui_hooks_login_sleep_install_multi_display": "NOT TESTED",
    "exe_sha256": hashlib.sha256(blob).hexdigest(), "exe_bytes": len(blob)
}
(payload / "BUILD-VERIFICATION.json").write_text(json.dumps(report, indent=2) + "\n")
shutil.copy2(stage / "core-tests.txt", payload / "Core-test-results.txt")
zip_path = stage / f"{name}.zip"
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for file in sorted(payload.iterdir()): archive.write(file, f"{name}/{file.name}")
with zipfile.ZipFile(zip_path) as archive:
    assert archive.testzip() is None
    assert archive.read(f"{name}/TaskLock.exe") == blob
output = root / "outputs" / "releases" / "windows" / version
output.mkdir(parents=True, exist_ok=True)
shutil.copy2(zip_path, output / zip_path.name)
shutil.copy2(payload / "BUILD-VERIFICATION.json", output / f"{rid}-verification.json")
print(f"Verified {rid}: {len(blob):,} byte EXE, ZIP CRC and extraction bytes match; native runtime NOT TESTED.")
