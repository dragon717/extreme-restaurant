"""Build a standalone Godot Web export, LAN hosts and a portable ZIP."""
from pathlib import Path
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
HOST = ROOT / "tools/lan"
PACKAGE = "canyon-web"
ARCHIVE = "峡谷餐厅-Web局域网.zip"


def find_godot():
    override = os.environ.get("GODOT_BIN")
    if override:
        executable = shutil.which(os.path.expanduser(override))
        if not executable:
            raise SystemExit("GODOT_BIN 未指向可运行的 Godot 编辑器：" + override)
        return executable
    for name in ("godot", "godot4", "godot_console"):
        executable = shutil.which(name)
        if executable:
            return executable
    if sys.platform == "darwin":
        for directory in (Path("/Applications"), Path.home() / "Applications"):
            executable = directory / "Godot.app/Contents/MacOS/Godot"
            if os.access(executable, os.X_OK):
                return str(executable)
    raise SystemExit("找不到 Godot 编辑器。请安装 Godot 4.6.3 和同版本导出模板，或用 GODOT_BIN 指定编辑器可执行文件的完整路径。")


def build():
    godot = find_godot()
    go = shutil.which("go")
    if not go:
        raise SystemExit("找不到 go。编译包内的 Mac 和 Windows 局域网服务器需要 Go 1.21 或更高版本，请将 go 加入 PATH。")
    BUILD.mkdir(exist_ok=True)
    (BUILD / ".gdignore").touch()
    with tempfile.TemporaryDirectory(dir=BUILD) as temp:
        staging = Path(temp)
        package = staging / PACKAGE
        site = package / "site"
        binaries = package / "bin"
        site.mkdir(parents=True)
        binaries.mkdir()
        base = [godot, "--headless", "--path", str(ROOT)]
        subprocess.run(base + ["--editor", "--import"], check=True)
        try:
            subprocess.run(base + ["--export-release", "Web", str(site / "index.html")], check=True)
        except subprocess.CalledProcessError:
            raise SystemExit("Godot Web 导出失败，请查看上方日志。如果缺少模板，请在 Godot 的「管理导出模板」中安装与编辑器同版本的标准导出模板。")
        for filename in ["index.html", "index.js", "index.wasm", "index.pck"]:
            if not (site / filename).stat().st_size:
                raise SystemExit("导出资源为空：" + filename)
        for system in ("darwin", "windows"):
            for arch in ("arm64", "amd64"):
                suffix = ".exe" if system == "windows" else ""
                binary = binaries / ("canyon-" + system + "-" + arch + suffix)
                env = dict(os.environ, CGO_ENABLED="0", GOOS=system, GOARCH=arch)
                subprocess.run([go, "build", "-p", "4", "-trimpath", "-ldflags=-s -w", "-o", str(binary),
                                str(HOST / "server.go"), str(HOST / "certificate.go")], env=env, check=True)
        shutil.copy2(ROOT / "局域网游玩.command", package)
        shutil.copy2(ROOT / "局域网游玩.cmd", package)
        shutil.copy2(HOST / "游玩说明.txt", package)
        archive = staging / ARCHIVE
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
            for item in sorted(package.rglob("*")):
                if item.is_file():
                    # Windows builds must also produce launchable files when unzipped on a Mac.
                    info = zipfile.ZipInfo.from_file(item, str(item.relative_to(staging)))
                    info.create_system = 3  # Unix file modes in the ZIP central directory.
                    mode = 0o755 if item.parent == binaries or item.suffix == ".command" else 0o644
                    info.external_attr = (stat.S_IFREG | mode) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    with item.open("rb") as source, output.open(info, "w") as target:
                        shutil.copyfileobj(source, target)
        # Publish only a completed export. Restore the previous folder if the swap fails.
        dest = BUILD / PACKAGE
        previous = staging / "previous"
        if dest.exists():
            dest.rename(previous)
        try:
            package.rename(dest)
        except OSError:
            if previous.exists():
                previous.rename(dest)
            raise
        os.replace(archive, BUILD / ARCHIVE)
    print(BUILD / ARCHIVE)


if __name__ == "__main__":
    build()
