# Rebuild florence-2 image
$ErrorActionPreference = "Stop"
Set-Location "C:\\AI\\lora-dataset-builder\docker"
docker compose build --no-cache
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed. Check Docker output above." -ForegroundColor Red
} else {
    Write-Host "florence-2 image rebuilt." -ForegroundColor Green
}
pause
