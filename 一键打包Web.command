#!/bin/sh
cd "$(dirname "$0")" || exit 1
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin"
export PYTHONUTF8=1
if ! command -v python3 >/dev/null 2>&1; then
    echo "找不到 Python 3。请安装 Python 3 后重新打包。" >&2
    exit 1
fi
exec python3 tools/build_lan_web.py
