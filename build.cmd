@echo off
setlocal
pushd "%~dp0"

if not defined VULKAN_SDK (
  echo [error] VULKAN_SDK is not set.
  popd & exit /b 1
)

where nmake >nul 2>nul
if not errorlevel 1 goto :build

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo [error] nmake is not on PATH and vswhere.exe was not found.
  popd & exit /b 1
)

for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT (
  echo [error] no Visual Studio C++ toolchain was found.
  popd & exit /b 1
)

call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 >nul
if errorlevel 1 (
  echo [error] failed to initialize the Visual Studio developer environment.
  popd & exit /b 1
)

:build
nmake /nologo %*
set "RESULT=%ERRORLEVEL%"
popd
exit /b %RESULT%

