@echo off
setlocal
chcp 65001 >nul
set "PYTHONUTF8=1"
py -3 -c "import sys" >nul 2>&1
if not errorlevel 1 (
    py -3 "%~dp0tools\build_lan_web.py"
) else (
    python -c "import sys; sys.exit(sys.version_info.major != 3)" >nul 2>&1
    if errorlevel 1 (
        echo 找不到 Python 3。请安装 Python 3 后重新打包。
        goto :failed
    )
    python "%~dp0tools\build_lan_web.py"
)
if not errorlevel 1 exit /b 0
:failed
pause
exit /b 1
