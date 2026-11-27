#!/bin/sh
cd "$(dirname "$0")" || exit 1
machine=$(uname -m)
if [ "$machine" = arm64 ] || [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
    arch=arm64
elif [ "$machine" = x86_64 ]; then
    arch=amd64
else
    echo "此启动器支持 Apple 芯片和 Intel Mac。"
    exit 1
fi
host="bin/canyon-darwin-$arch"
[ -f "$host" ] || host="build/canyon-web/$host"
if [ ! -x "$host" ]; then
    echo "请先完整解压峡谷餐厅 Web 局域网包。源码目录可运行 python3 tools/build_lan_web.py 生成游戏包。"
    exit 1
fi
exec "./$host" "$@"
