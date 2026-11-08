@echo off
rem ------------------------------------------------------------------
rem Start Qwen3-TTS servers without any other launcher.
rem
rem   scripts\start.cmd [all|base|customvoice|voicedesign] [models_dir]
rem
rem models_dir (default: ..\models, or env QWEN_TTS_MODELS) must contain
rem   qwen-tokenizer-12hz-*.gguf  and the  qwen-talker-*-<mode>-*.gguf  files.
rem Ports: base 8090, customvoice 8091, voicedesign 8092 (127.0.0.1 only,
rem set TTS_HOST=0.0.0.0 to open them to the LAN).
rem Voices in <models_dir>\voices\*.wav are registered on the base server.
rem Close the server windows to stop them.
rem ------------------------------------------------------------------
setlocal EnableExtensions EnableDelayedExpansion

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "EXE=%ROOT%\bin\tts-server.exe"
set "WHICH=%~1"
if "%WHICH%"=="" set "WHICH=all"
set "MODELS=%~2"
if "%MODELS%"=="" if defined QWEN_TTS_MODELS set "MODELS=%QWEN_TTS_MODELS%"
if "%MODELS%"=="" set "MODELS=%ROOT%\models"
if not defined TTS_HOST set "TTS_HOST=127.0.0.1"

if not exist "%EXE%" (
    echo %EXE% not found. Run scripts\build.cmd first.
    exit /b 1
)

set "CODEC="
for %%F in ("%MODELS%\qwen-tokenizer-*.gguf") do if not defined CODEC set "CODEC=%%~fF"
if not defined CODEC (
    echo No qwen-tokenizer-*.gguf in %MODELS%
    exit /b 1
)

set "STARTED=0"
for %%M in (base:8090 customvoice:8091 voicedesign:8092) do (
    for /f "tokens=1,2 delims=:" %%A in ("%%M") do (
        if /i "%WHICH%"=="all" (call :run %%A %%B) else if /i "%WHICH%"=="%%A" (call :run %%A %%B)
    )
)

if "%STARTED%"=="0" (
    echo Nothing started. Mode must be all, base, customvoice or voicedesign.
    exit /b 1
)

if "%BASE_STARTED%"=="1" if exist "%MODELS%\voices\*.wav" (
    start "register voices" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0register-voices.ps1" -VoicesDir "%MODELS%\voices"
)

start "" "%ROOT%\web\index.html"
exit /b 0

:run
set "TALKER="
for %%F in ("%MODELS%\qwen-talker-*-%1-*.gguf") do if not defined TALKER set "TALKER=%%~fF"
if not defined TALKER (
    echo Skipping %1: no qwen-talker-*-%1-*.gguf in %MODELS%
    exit /b 0
)
echo Starting %1 on %TTS_HOST%:%2
start "qwen3-tts-%1 :%2" /min "%EXE%" --model "%TALKER%" --codec "%CODEC%" --alias qwen3-tts-%1 --host %TTS_HOST% --port %2
set /a STARTED+=1
if /i "%1"=="base" set "BASE_STARTED=1"
exit /b 0
