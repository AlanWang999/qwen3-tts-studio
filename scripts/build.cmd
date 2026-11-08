@echo off
rem ------------------------------------------------------------------
rem Build qwentts.cpp (CUDA) on Windows and copy the binaries to bin\
rem
rem   scripts\build.cmd            build (clone the source first if missing)
rem   scripts\build.cmd update     git pull the source, then rebuild
rem
rem Needs: Visual Studio Build Tools (C++ workload, ships CMake + Ninja),
rem        CUDA Toolkit, git.
rem Optional env: CUDA_ARCH (default "native" = only the GPU in this PC;
rem               leave empty to use the upstream multi-arch list).
rem ------------------------------------------------------------------
setlocal EnableExtensions

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "SRC=%ROOT%\qwentts.cpp"
set "BUILD=%SRC%\build"
set "BIN=%ROOT%\bin"
set "REPO=https://github.com/ServeurpersoCom/qwentts.cpp.git"

if not exist "%SRC%\CMakeLists.txt" (
    echo [1/4] Cloning qwentts.cpp ...
    git clone --recurse-submodules "%REPO%" "%SRC%" || goto :fail
) else if /i "%~1"=="update" (
    echo [1/4] Updating qwentts.cpp ...
    git -C "%SRC%" pull --ff-only || goto :fail
    git -C "%SRC%" submodule update --init --recursive || goto :fail
) else (
    echo [1/4] Using existing source in %SRC%
)

echo [2/4] Loading the MSVC environment ...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo Visual Studio Installer not found. Install "Visual Studio Build Tools" with the C++ workload.
    goto :fail
)
set "VSDIR="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%I"
if not defined VSDIR (
    echo No Visual Studio installation with the C++ build tools was found.
    goto :fail
)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || goto :fail

if not defined CUDA_ARCH set "CUDA_ARCH=native"
set "ARCH_FLAG="
if not "%CUDA_ARCH%"=="" set "ARCH_FLAG=-DCMAKE_CUDA_ARCHITECTURES=%CUDA_ARCH%"

echo [3/4] Configuring and building (CUDA arch: %CUDA_ARCH%) ...
cmake -S "%SRC%" -B "%BUILD%" -G "Ninja Multi-Config" -DGGML_CUDA=ON %ARCH_FLAG% || goto :fail
cmake --build "%BUILD%" --config Release -j %NUMBER_OF_PROCESSORS% || goto :fail

set "OUT="
for %%D in ("%BUILD%\Release" "%BUILD%") do if not defined OUT if exist "%%~D\tts-server.exe" set "OUT=%%~D"
if not defined OUT (
    echo Build finished but tts-server.exe was not found under %BUILD%.
    goto :fail
)

echo [4/4] Copying binaries to %BIN% ...
if not exist "%BIN%" mkdir "%BIN%"
copy /y "%OUT%\*.exe" "%BIN%\" >nul || goto :fail
if exist "%OUT%\*.dll" copy /y "%OUT%\*.dll" "%BIN%\" >nul
if exist "%BUILD%\bin\Release\*.dll" copy /y "%BUILD%\bin\Release\*.dll" "%BIN%\" >nul

rem CUDA runtime next to the exe, so it also runs when CUDA is not on PATH
if defined CUDA_PATH (
    for %%P in ("%CUDA_PATH%\bin\x64" "%CUDA_PATH%\bin") do (
        if exist "%%~P\cudart64_*.dll" copy /y "%%~P\cudart64_*.dll" "%BIN%\" >nul
        if exist "%%~P\cublas64_*.dll" copy /y "%%~P\cublas64_*.dll" "%BIN%\" >nul
        if exist "%%~P\cublasLt64_*.dll" copy /y "%%~P\cublasLt64_*.dll" "%BIN%\" >nul
    )
)

for /f "usebackq delims=" %%H in (`git -C "%SRC%" log -1 --format^=%%h`) do set "HASH=%%H"
for /f "usebackq delims=" %%D in (`git -C "%SRC%" log -1 --format^=%%cs`) do set "CDATE=%%D"
> "%BIN%\BUILD.txt" (
    echo commit=%HASH%
    echo date=%CDATE%
    echo cuda_arch=%CUDA_ARCH%
)

echo.
echo Done: qwentts.cpp %HASH% (%CDATE%) -^> %BIN%
exit /b 0

:fail
echo.
echo Build FAILED.
exit /b 1
