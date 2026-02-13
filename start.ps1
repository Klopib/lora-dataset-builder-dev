# Start florence-2
$ErrorActionPreference = "Stop"
Set-Location "C:\\AI\\lora-dataset-builder\docker"
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start florence-2. Check Docker output above." -ForegroundColor Red
    pause
    exit $LASTEXITCODE
}
$url = "http://localhost:8080"
Write-Host "florence-2 is running at http://localhost:8080" -ForegroundColor Green
try { Start-Process $url | Out-Null; Write-Host "Opened $url in your browser." -ForegroundColor DarkGray } catch { Write-Host "Could not open browser automatically. Open $url manually." -ForegroundColor Yellow }
$docsUrl = "http://localhost:8080/docs"
try { Start-Process $docsUrl | Out-Null; Write-Host "Opened Florence docs: $docsUrl" -ForegroundColor DarkGray } catch { Write-Host "Florence docs: $docsUrl" -ForegroundColor Yellow }
pause
