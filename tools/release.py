#!/usr/bin/env python3
"""Pinned Godot tools, native-host export, packaged-game smoke test and archive."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".release-tools"
GODOT = "4.5.2"
BINDING = "e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{GODOT}-stable"
TARGETS = {
    "windows": ("Windows", "win64.exe.zip", "windows_", "KiskaCommand.exe"),
    "linux": ("Linux", "linux.x86_64.zip", "linux_", "KiskaCommand.x86_64"),
    "macos-intel": ("macOS Intel", "macos.universal.zip", "macos.zip", "Kiska Command.app"),
    "macos-arm64": ("macOS Apple Silicon", "macos.universal.zip", "macos.zip", "Kiska Command.app"),
}


def run(args, **kwargs):
    print("+", " ".join(map(str, args)), flush=True)
    kwargs.setdefault("check", True)
    return subprocess.run(list(map(str, args)), cwd=ROOT, **kwargs)


def download(url, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        try:
            print(f"Download {url}", flush=True)
            with urllib.request.urlopen(url, timeout=120) as source, destination.open("wb") as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
            return
        except Exception:
            destination.unlink(missing_ok=True)
            if attempt == 2:
                raise
            time.sleep(3)


def verified_download(filename):
    destination = TOOLS / filename
    sums = urllib.request.urlopen(f"{BASE}/SHA512-SUMS.txt", timeout=60).read().decode()
    expected = next(line.split()[0] for line in sums.splitlines() if line.split()[-1].lstrip("*") == filename)
    download(f"{BASE}/{filename}", destination)
    digest = hashlib.sha512()
    with destination.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != expected:
        destination.unlink()
        raise RuntimeError(f"Official SHA-512 mismatch: {filename}")
    return destination


def engine(target):
    if target.startswith("macos"):
        return TOOLS / "Godot.app/Contents/MacOS/Godot"
    if target == "windows":
        return TOOLS / f"Godot_v{GODOT}-stable_win64.exe"
    return TOOLS / f"Godot_v{GODOT}-stable_linux.x86_64"


def templates_dir():
    if platform.system() == "Darwin":
        base = Path.home() / "Library/Application Support/Godot"
    elif os.name == "nt":
        base = Path(os.environ["APPDATA"]) / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "godot"
    return base / "export_templates" / f"{GODOT}.stable"


def thin_macos_template(archive, target):
    # Official macOS templates contain universal executables only. Godot's
    # single-architecture presets expect explicitly named native executables.
    arch = "arm64" if target == "macos-arm64" else "x86_64"
    with tempfile.TemporaryDirectory(dir=TOOLS) as temporary:
        temporary = Path(temporary)
        derived = temporary / "macos.zip"
        count = 0
        with zipfile.ZipFile(archive) as source, zipfile.ZipFile(derived, "w", zipfile.ZIP_DEFLATED) as output:
            for entry in source.infolist():
                data = source.read(entry)
                if "/Contents/MacOS/godot_macos_" in entry.filename and entry.filename.endswith(".universal"):
                    universal = temporary / "universal"
                    native = temporary / "native"
                    universal.write_bytes(data)
                    run(["lipo", universal, "-thin", arch, "-output", native])
                    data = native.read_bytes()
                    entry.filename = entry.filename.removesuffix("universal") + arch
                    count += 1
                output.writestr(entry, data)
        if count != 2:
            raise RuntimeError("Expected debug and release universal macOS template executables")
        shutil.copy2(derived, archive)


def prepare(target):
    TOOLS.mkdir(exist_ok=True)
    if not engine(target).exists():
        archive = verified_download(f"Godot_v{GODOT}-stable_{TARGETS[target][1]}")
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(TOOLS)
        archive.unlink()
        if os.name != "nt":
            engine(target).chmod(0o755)
    cached = TOOLS / "templates"
    marker = cached / f"{target}-{GODOT}-v2.ready"
    if not marker.exists():
        archive = verified_download(f"Godot_v{GODOT}-stable_export_templates.tpz")
        cached.mkdir(exist_ok=True)
        with zipfile.ZipFile(archive) as bundle:
            for info in bundle.infolist():
                name = Path(info.filename).name
                if name == "version.txt" or name.startswith(TARGETS[target][2]):
                    with bundle.open(info) as source, (cached / name).open("wb") as output:
                        shutil.copyfileobj(source, output)
        archive.unlink()
        if target.startswith("macos"):
            thin_macos_template(cached / "macos.zip", target)
        marker.touch()
    templates_dir().mkdir(parents=True, exist_ok=True)
    for source in cached.iterdir():
        if not source.name.endswith(".ready"):
            shutil.copy2(source, templates_dir() / source.name)
    binding = ROOT / "third_party/godot-cpp"
    if not binding.exists():
        run(["git", "clone", "--depth", "1", "--branch", "godot-4.5-stable",
             "https://github.com/godotengine/godot-cpp.git", binding])
    actual = run(["git", "-C", binding, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    if actual != BINDING:
        raise RuntimeError(f"Unexpected binding commit: {actual}")
    run([engine(target), "--version"])


def checked_engine(args, marker=None, timeout=180):
    result = run(args, check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    print(result.stdout, flush=True)
    print(result.stderr, flush=True)
    result.check_returncode()
    text = result.stdout + result.stderr
    if re.search(r"SCRIPT ERROR|Parse Error|Failed loading resource|Error loading extension|GDExtension dynamic library not found", text):
        raise RuntimeError("Godot reported a script, resource or extension failure")
    if marker and marker not in text:
        raise RuntimeError(f"Missing success marker: {marker}")


def export(target):
    version = re.search(r'config/version="([^"]+)"', (ROOT / "game/project.godot").read_text()).group(1)
    tag = os.environ.get("GITHUB_REF", "")
    if tag.startswith("refs/tags/") and tag != f"refs/tags/v{version}":
        raise RuntimeError("Release tag must match project.godot config/version")
    output = ROOT / "dist" / target
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    binary = output / TARGETS[target][3]
    checked_engine([engine(target), "--headless", "--path", ROOT / "game", "--editor", "--import", "--quit"], timeout=300)
    checked_engine([engine(target), "--headless", "--path", ROOT / "game", "--export-release", TARGETS[target][0], binary], timeout=300)
    if target.startswith("macos"):
        binary = next((binary / "Contents/MacOS").iterdir())
        arch = "arm64" if target == "macos-arm64" else "x86_64"
        run(["lipo", "-verify_arch", arch, binary])
        run(["lipo", "-verify_arch", arch, ROOT / "game/bin/libridgeline.dylib"])
        run(["codesign", "--verify", "--deep", "--strict", output / TARGETS[target][3]])
    if os.name != "nt":
        binary.chmod(0o755)
    # Test the shipped release executable/PCK, not a second editor invocation.
    # Log-file also captures output from the Windows GUI-subsystem executable.
    log = ROOT / "dist" / f"{target}-smoke.log"
    result = run([binary, "--headless", "--fixed-fps", "60", "--quit-after", "1800",
                  "--log-file", log, "--", "--integration-test"],
                 check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=240)
    text = log.read_text(encoding="utf-8") if log.exists() else result.stdout + result.stderr
    print(text, flush=True)
    result.check_returncode()
    if "INTEGRATION_PASS: 184 checks" not in text or re.search(r"SCRIPT ERROR|Parse Error|INTEGRATION_FAILED|ERROR:", text):
        raise RuntimeError("Packaged release failed the engine integration suite")
    for name in ["LICENSE", "ASSETS.md", "README.md"]:
        shutil.copy2(ROOT / name, output / name)
    licenses = output / "licenses"
    licenses.mkdir()
    shutil.copy2(ROOT / "game/fonts/OFL.txt", licenses / "NotoSansSC-OFL.txt")
    shutil.copy2(ROOT / "third_party/godot-cpp/LICENSE.md", licenses / "godot-cpp-LICENSE.md")
    for name in ["LICENSE.txt", "COPYRIGHT.txt"]:
        download(f"https://raw.githubusercontent.com/godotengine/godot/{GODOT}-stable/{name}", licenses / f"Godot-{name}")
    info = {"version": version, "target": target, "godot": GODOT, "godot_cpp": BINDING,
            "commit": run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()}
    (output / "build-info.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    (output / "START-HERE.txt").write_text(
        "Kiska Command / 基斯卡行动\n\n"
        "解压整个文件夹后启动游戏；无需另装 Godot。请保留 PCK 和原生库。\n"
        "Extract the whole folder before launching; Godot is included. Keep the PCK and native libraries.\n\n"
        "Windows: KiskaCommand.exe\nLinux: ./KiskaCommand.x86_64 (chmod +x if needed)\n"
        "macOS: Kiska Command.app; Intel 与 Apple Silicon 请选对应版本。\n"
        "macOS uses ad-hoc signing, without Apple notarization. If blocked, use System Settings > Privacy & Security > Open Anyway.\n"
        "macOS 为本地签名，未公证；确认来源后可在系统设置 > 隐私与安全性中选择仍要打开。\n\n"
        "默认中文。WASD 移动，鼠标开火/瞄准，轻按 Q 智能命令、长按 Q 详细命令，B 背包，M 地图，E 上下车，F11 全屏。\n"
        "Prototype / 原型版本。源码与问题反馈：https://github.com/benzeneringlq/kiska-command\n",
        encoding="utf-8")
    stem = f"KiskaCommand-v{version}-{target}"
    if target.startswith("macos"):
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", output, ROOT / "dist" / f"{stem}.zip"])
    elif target == "linux":
        with tarfile.open(ROOT / "dist" / f"{stem}.tar.gz", "w:gz") as bundle:
            bundle.add(output, arcname=stem)
    else:
        shutil.make_archive(str(ROOT / "dist" / stem), "zip", output.parent, output.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["prepare", "export"])
    parser.add_argument("target", choices=TARGETS)
    args = parser.parse_args()
    (prepare if args.operation == "prepare" else export)(args.target)
