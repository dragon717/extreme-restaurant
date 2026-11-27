"""Build a standalone Godot Web export, LAN hosts and a portable ZIP."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
HOST = ROOT / "tools/lan"
PACKAGE = "canyon-web"
ARCHIVE = "峡谷餐厅-Web局域网.zip"


def build():
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
    go = shutil.which("go")
    if not (Path(godot).is_file() or shutil.which(godot)) or not go:
        raise SystemExit("请安装 Godot 4.6.3（包含 Web 导出模板）和 Go 1.21 以上。可用 GODOT_BIN 指定编辑器。")
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
        subprocess.run(base + ["--export-release", "Web", str(site / "index.html")], check=True)
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
                    output.write(item, str(item.relative_to(staging)))
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
