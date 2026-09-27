@echo off
rem ============================================================
rem  One-click launcher for the Qianxing sandbox simulator (Web).
rem  All real work lives in _tools\dev_open.mjs.
rem  This file is intentionally pure ASCII: it only locates a
rem  Node runtime and forwards every argument, so a non-ASCII
rem  workspace path can never be garbled by the code page.
rem
rem  Usage (double-click, or from a shell):
rem    start_simulator.bat              workbench  (/editor)
rem    start_simulator.bat play         straight into play mode
rem    start_simulator.bat --restart    restart the server first
rem ============================================================
setlocal

rem --- make console output readable (Node writes UTF-8) ---
chcp 65001 >nul 2>nul

rem --- locate a Node runtime: managed version dir first, PATH as fallback
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

"%NODE_EXE%" "%~dp0_tools\dev_open.mjs" %*
if errorlevel 1 (
  echo.
  echo [!] Startup failed. See the messages above.
  echo.
  pause
)

endlocal
