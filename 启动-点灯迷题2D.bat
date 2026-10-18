@echo off
rem ============================================================
rem  One-click launcher: "Deng 2D" (16x16 four-quadrant Lights Out).
rem
rem  Why this file is pure ASCII: the game folder name is Chinese,
rem  and a Chinese literal inside a .bat gets mangled by the console
rem  code page. So the mapping lives in _tools\game_alias.json (UTF-8)
rem  and we only pass an ASCII alias here.
rem
rem  Usage:
rem    double-click              workbench  (/editor)
rem    start_deng2d.bat play     straight into play mode
rem    start_deng2d.bat --restart   restart server first
rem ============================================================
setlocal

chcp 65001 >nul 2>nul

set "NODE_EXE="
for /d %%D in ("%USERPROFILE%\.workbuddy\binaries\node\versions\*") do if exist "%%~fD\node.exe" set "NODE_EXE=%%~fD\node.exe"
if not defined NODE_EXE set "NODE_EXE=node"

if not exist "%~dp0_tools\dev_open.mjs" (
  echo.
  echo [!] _tools\dev_open.mjs not found next to this script.
  echo     Make sure this .bat stays in the workspace root.
  echo.
  pause
  exit /b 1
)

"%NODE_EXE%" "%~dp0_tools\dev_open.mjs" --alias deng2d %*
if errorlevel 1 (
  echo.
  echo [!] Startup failed. See the messages above.
  echo.
  pause
)

endlocal
