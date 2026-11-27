@echo off
setlocal
set "CANYON_ARCH=amd64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "CANYON_ARCH=arm64"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "CANYON_ARCH=arm64"
set "CANYON_HOST=%~dp0bin\canyon-windows-%CANYON_ARCH%.exe"
if not exist "%CANYON_HOST%" set "CANYON_HOST=%~dp0build\canyon-web\bin\canyon-windows-%CANYON_ARCH%.exe"
if not exist "%CANYON_HOST%" (
    echo Extract the entire Canyon Tavern LAN package before launching.
    pause
    exit /b 1
)
"%CANYON_HOST%" %*
if errorlevel 1 (
    pause
    exit /b 1
)
