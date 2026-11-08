<#
Register every <name>.wav (plus optional <name>.txt transcript) in a voices
folder with a running Qwen3-TTS *base* server, so clients can use
"voice": "<name>" right away. Registrations live in server RAM, so run this
again after every server start (scripts\start.cmd does it automatically).

  powershell -ExecutionPolicy Bypass -File scripts\register-voices.ps1 -VoicesDir models\voices
#>
param(
    [string]$VoicesDir = (Join-Path $PSScriptRoot "..\models\voices"),
    [int]$Port = 8090,
    [string]$ApiHost = "127.0.0.1",
    [int]$WaitSeconds = 300
)

$ErrorActionPreference = "Stop"
$base = "http://${ApiHost}:$Port"

if (-not (Test-Path $VoicesDir)) {
    Write-Host "No voices folder: $VoicesDir"
    exit 0
}
$wavs = Get-ChildItem -Path $VoicesDir -Filter *.wav -File
if (-not $wavs) {
    Write-Host "No .wav files in $VoicesDir"
    exit 0
}

$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ($true) {
    try {
        Invoke-RestMethod "$base/health" -TimeoutSec 2 | Out-Null
        break
    } catch {
        if ((Get-Date) -gt $deadline) { throw "Server $base did not become ready in $WaitSeconds s" }
        Start-Sleep -Seconds 2
    }
}

foreach ($wav in $wavs) {
    $name = [IO.Path]::GetFileNameWithoutExtension($wav.Name)
    $body = @{ name = $name; wav_b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($wav.FullName)) }
    $txt = Join-Path $wav.DirectoryName "$name.txt"
    if (Test-Path $txt) {
        $text = (Get-Content $txt -Raw -Encoding UTF8).Trim()
        if ($text) { $body.ref_text = $text }
    }
    $json = $body | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Method Post -Uri "$base/v1/audio/voices" -ContentType "application/json; charset=utf-8" `
            -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 120 | Out-Null
        Write-Host "registered: $name"
    } catch {
        Write-Warning "failed: $name - $($_.Exception.Message)"
    }
}
