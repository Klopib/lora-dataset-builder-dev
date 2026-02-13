# Stop florence-2
$ErrorActionPreference = "Stop"
Set-Location "C:\\AI\\lora-dataset-builder\docker"
docker compose down
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to stop florence-2. Check Docker output above." -ForegroundColor Red
} else {
    Write-Host "florence-2 stopped." -ForegroundColor Yellow
}
pause
