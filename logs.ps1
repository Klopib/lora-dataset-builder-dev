# View florence-2 logs
$ErrorActionPreference = "Stop"
Set-Location "C:\\AI\\lora-dataset-builder\docker"
Write-Host "Streaming logs. Press Ctrl+C to stop." -ForegroundColor DarkGray
docker compose logs -f --tail 50
pause
