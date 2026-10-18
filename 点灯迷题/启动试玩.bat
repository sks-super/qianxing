@echo off
rem ============================================================
rem  One-click launcher for THIS game folder.
rem  Real work lives in ..\_tools\dev_open.mjs
rem  Pure ASCII on purpose: the game name is derived from the
rem  enclosing folder name, so no non-ASCII literal is ever
rem  written into this file (a Chinese path can therefore never
rem  be garbled by the code page).
rem
rem  Usage (double-click, or from a shell):
rem    launch_play.bat              start simulator + open play page
rem    launch_play.bat editor       open the workbench instead
rem    launch_play.bat --restart    restart the server first
rem ============================================================
setlocal

rem --- make console output readable (Node writes UTF-8) ---
chcp 65001 >nul 2>nul

rem --- locate a Node runtime: managed version dir first, PATH as fallback
set "NODE_EXE="
for /d %%D in ("%USERPROFILE%\.workbuddy\binaries\node\versions\*") do if exist "%%~fD\node.exe" set "NODE_EXE=%%~fD\node.exe"
if not defined NODE_EXE set "NODE_EXE=node"

rem --- game name = name of the folder this script lives in
set "HERE=%~dp0"
set "HERE=%HERE:~0,-1%"
for %%I in ("%HERE%") do set "GAME=%%~nxI"

if not exist "%~dp0..\_tools\dev_open.mjs" (
  echo.
  echo [!] ..\_tools\dev_open.mjs not found.
  echo     Keep this .bat inside the game folder ^(one level under the workspace root^).
  echo.
  pause
  exit /b 1
)

set "MODE=play"
if /i "%~1"=="editor" set "MODE=" & shift

echo.
echo   Game    %GAME%
echo   Mode    %MODE%
echo.

"%NODE_EXE%" "%~dp0..\_tools\dev_open.mjs" --game "%GAME%" %MODE% %*
if errorlevel 1 (
  echo.
  echo [!] Startup failed. See the messages above.
  echo.
  pause
)

endlocal
