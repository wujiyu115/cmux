@echo off
REM Build TeamPilot for Windows (release).
REM Usage: build_windows.bat [--debug] [--run]

setlocal enabledelayedexpansion

set "MODE=release"
set "DORUN=0"

:parse
if "%~1"=="" goto after
if /i "%~1"=="--debug"  set "MODE=debug"  & shift & goto parse
if /i "%~1"=="--run"    set "DORUN=1"      & shift & goto parse
echo Unknown arg: %~1
exit /b 1
:after

cd /d "%~dp0client" || (echo client dir not found & exit /b 1)

echo === flutter pub get ===
call flutter pub get || goto fail

echo === flutter build windows --%MODE% ===
call flutter build windows --%MODE% || goto fail

set "OUT=build\windows\x64\runner\%MODE%"
if /i "%MODE%"=="release" set "OUT=build\windows\x64\runner\Release"
if /i "%MODE%"=="debug"   set "OUT=build\windows\x64\runner\Debug"

echo === Build OK: %CD%\%OUT%\TeamPilot.exe ===

if "%DORUN%"=="1" (
  echo === Launching ===
  start "" "%OUT%\TeamPilot.exe"
)

endlocal
exit /b 0

:fail
echo === Build FAILED ===
endlocal
exit /b 1
