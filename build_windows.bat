@echo off
REM Build TeamPilot for Windows.
REM
REM Usage: build_windows.bat [options]
REM   --debug            build debug mode
REM   --profile          build profile mode
REM   --release          build release mode (default)
REM   --run              launch TeamPilot.exe after a successful build
REM   --assets           force the asset prerequisites even when already present
REM   --package          also package via fastforge: zip + msix + exe
REM   --zip              package zip only  (--zip/--msix/--exe imply --package
REM   --msix             package msix only  and select targets; the exe target
REM   --exe              package exe only   needs Inno Setup 6)
REM   -h, --help         show this help
REM
REM Asset prerequisites are the gitignored generated files a fresh clone lacks:
REM   google_fonts/*.ttf, assets/fonts/terminal/*.ttf
REM     -> dart run tool/sync_bundled_google_fonts.dart  (~100MB downloaded)
REM     Not a build blocker, but the app needs them at runtime for Chinese text
REM     and terminal glyphs.
REM   windows/runner/native_splash_screen_{debug,profile,release}.cpp
REM     -> dart run native_splash_screen_cli gen
REM     windows/runner/native_splash_screen.cmake raises a CMake FATAL_ERROR
REM     unless all three exist, so a fresh clone cannot build without them.
REM File-type icons (assets/file_icons, lib/utils/ui/file_icon_mapping.g.dart)
REM are tracked in git and are therefore not regenerated here.

setlocal enabledelayedexpansion

set "MODE=release"
set "DORUN=0"
set "FORCE_ASSETS=0"
set "DOPACKAGE=0"
set "PKG_TARGETS="
set "PF86=%ProgramFiles(x86)%"

REM Pub-cache shims (fastforge.bat) are not always on PATH after
REM "dart pub global activate fastforge"; add them when present, as release.yml does.
if exist "%LOCALAPPDATA%\Pub\Cache\bin\fastforge.bat" set "PATH=%PATH%;%LOCALAPPDATA%\Pub\Cache\bin"

:parse
if "%~1"=="" goto after
set "ARG=%~1"
if /i "!ARG!"=="--debug"     set "MODE=debug"     & shift & goto parse
if /i "!ARG!"=="--profile"   set "MODE=profile"   & shift & goto parse
if /i "!ARG!"=="--release"   set "MODE=release"   & shift & goto parse
if /i "!ARG!"=="--run"       set "DORUN=1"        & shift & goto parse
if /i "!ARG!"=="--assets"    set "FORCE_ASSETS=1" & shift & goto parse
if /i "!ARG!"=="--package"   set "DOPACKAGE=1"                       & shift & goto parse
if /i "!ARG!"=="--zip"       set "DOPACKAGE=1" & call :addpkg zip    & shift & goto parse
if /i "!ARG!"=="--msix"      set "DOPACKAGE=1" & call :addpkg msix   & shift & goto parse
if /i "!ARG!"=="--exe"       set "DOPACKAGE=1" & call :addpkg exe    & shift & goto parse
if /i "!ARG!"=="-h"          goto help
if /i "!ARG!"=="--help"      goto help
echo Unknown arg: !ARG!
echo Try: build_windows.bat --help
endlocal
exit /b 1

:addpkg
if "!PKG_TARGETS!"=="" (set "PKG_TARGETS=%~1") else (set "PKG_TARGETS=!PKG_TARGETS!,%~1")
exit /b 0

:after
REM Bare --package keeps fastforge's own default target set.
if "%DOPACKAGE%"=="1" if "!PKG_TARGETS!"=="" set "PKG_TARGETS=zip,msix,exe"

cd /d "%~dp0client" || (echo client dir not found & exit /b 1)

echo === flutter pub get ===
call flutter pub get || goto fail

if "%FORCE_ASSETS%"=="1" goto fonts
set "NEED_FONTS=0"
for %%F in ("google_fonts\NotoSansSC-Regular.ttf" "google_fonts\NotoSansSC-Bold.ttf" "assets\fonts\terminal\JetBrainsMonoNerdFontMono-Regular.ttf" "assets\fonts\terminal\UbuntuSansMono-Regular.ttf") do if not exist %%F set "NEED_FONTS=1"
if "!NEED_FONTS!"=="0" (
  echo === Bundled fonts present - skipping sync ^(use --assets to force^) ===
  goto splash
)

:fonts
REM ~50s even when cached: Dart VM start plus SHA256 over ~100MB of fonts.
echo === Sync bundled fonts ^(tool/sync_bundled_google_fonts.dart^) ===
call dart run tool/sync_bundled_google_fonts.dart || goto fail

:splash
REM Idempotent and fast (~7s); always regenerate so an edited
REM native_splash_screen.yaml or assets/icons/icon_bg.png cannot go stale.
echo === Generate native splash sources ===
call dart run native_splash_screen_cli gen || goto fail

echo === flutter build windows --!MODE! ===
call flutter build windows --!MODE! || goto fail

REM Flutter capitalises the per-config runner dir; map MODE to it explicitly so
REM the paths we print match what is actually on disk.
set "CFGDIR=!MODE!"
if /i "!MODE!"=="release" set "CFGDIR=Release"
if /i "!MODE!"=="debug"   set "CFGDIR=Debug"
if /i "!MODE!"=="profile" set "CFGDIR=Profile"
set "OUT=build\windows\x64\runner\!CFGDIR!"
if not exist "!OUT!\TeamPilot.exe" (
  echo Expected binary missing: %CD%\!OUT!\TeamPilot.exe
  goto fail
)

if "%DOPACKAGE%"=="0" goto done

where fastforge >nul 2>&1
if errorlevel 1 (
  echo fastforge not found on PATH.
  echo   Install: dart pub global activate fastforge
  echo   Then make sure the pub-cache bin dir is on PATH.
  goto fail
)
echo !PKG_TARGETS!| findstr /i "exe" >nul
if not errorlevel 1 (
  where iscc >nul 2>&1
  if errorlevel 1 if exist "!PF86!\Inno Setup 6\ISCC.exe" set "PATH=!PATH!;!PF86!\Inno Setup 6"
  where iscc >nul 2>&1
  if errorlevel 1 (
    echo ISCC ^(Inno Setup 6^) not found - required for the exe target.
    echo   Install: choco install innosetup --no-progress -y
    echo   Or skip it: build_windows.bat --zip --msix
    goto fail
  )
)
REM fastforge performs its own release build; output lands in client\dist\<version>\.
echo === fastforge package --platform windows --targets !PKG_TARGETS! ===
call fastforge package --platform windows --targets !PKG_TARGETS! || goto fail
echo === Packages under %CD%\dist ===

:done
echo === Build OK: %CD%\!OUT!\TeamPilot.exe ===
if "%DORUN%"=="1" (
  echo === Launching ===
  start "" "!OUT!\TeamPilot.exe"
)
endlocal
exit /b 0

:help
echo Build TeamPilot for Windows.
echo.
echo Usage: build_windows.bat [options]
echo   --debug            build debug mode
echo   --profile          build profile mode
echo   --release          build release mode (default)
echo   --run              launch TeamPilot.exe after a successful build
echo   --assets           force the asset prerequisites even when already present
echo   --package          also package via fastforge: zip + msix + exe
echo   --zip              package zip only  (--zip/--msix/--exe imply --package
echo   --msix             package msix only  and select targets; the exe target
echo   --exe              package exe only   needs Inno Setup 6)
echo   -h, --help         show this help
echo.
echo Output:   client\build\windows\x64\runner\^<Release^|Debug^|Profile^>\TeamPilot.exe
echo Packages: client\dist\^<version^>\  (fastforge always builds release)
endlocal
exit /b 0

:fail
echo === Build FAILED ===
endlocal
exit /b 1
