#
# Run the Gradio review UI in Docker (no host Python/conda needed).
# Usage:
#   ./run-review-ui.ps1 -ImageDir "C:\AI\lora-dataset-builder\lora-training\mikey\IMG\12_mikey" -Concept "mikey" -Port 7861
#

param(
  [Parameter(Mandatory = $true)][string]$ImageDir,
  [Parameter(Mandatory = $true)][string]$Concept,
  [int]$Port = 7861,
  [string]$RegistryPath = "C:\AI\.registry.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ImageDir)) { throw "ImageDir not found: $ImageDir" }

if (Test-Path $RegistryPath) {
  try {
    $reg = Get-Content $RegistryPath | ConvertFrom-Json
    $reserved = $reg | Where-Object { $_.port -eq $Port }
    if ($reserved) {
      $sameApp = $reserved | Where-Object { $_.name -eq "review-ui" -and $_.storage_path -eq $ImageDir }
      if (-not $sameApp) {
        throw "Port $Port is already reserved for '$($reserved.name)'. Choose another or update the registry."
      } else {
        Write-Host "Port $Port already reserved for review-ui at $ImageDir; reusing entry." -ForegroundColor DarkGray
      }
    } else {
      $entry = [pscustomobject]@{
        name   = "review-ui"
        port   = $Port
        type   = "service"
        image  = "florence-2-review-ui"
        gpu    = $false
        model_cache = $false
        storage_path = $ImageDir
        created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
      }
      $reg = $reg + $entry
      $reg | ConvertTo-Json -Depth 5 | Set-Content $RegistryPath -Encoding UTF8
      Write-Host "Reserved port $Port in $RegistryPath for review-ui." -ForegroundColor Green
    }
  } catch { throw "Port registry error: $_" }
} else {
  Write-Host "Registry $RegistryPath not found; skipping reservation check." -ForegroundColor Yellow
}

$capsJson = Join-Path $ImageDir "captions.json"
$capsCsv  = Join-Path $ImageDir "captions.csv"
if (-not (Test-Path $capsJson) -or -not (Test-Path $capsCsv)) { throw "captions.json / captions.csv not found in $ImageDir. Run caption.ps1 first." }

$imageDirUnix = "/data"
$hostPath = (Resolve-Path $ImageDir).ProviderPath
if ($hostPath -match '^[A-Za-z]:\\') {
  $drive = $hostPath.Substring(0,1).ToLower()
  $rest = $hostPath.Substring(2) -replace '\\','/'
  $dockerHostPath = "/${drive}${rest}"
} else {
  $dockerHostPath = $hostPath -replace '\\','/'
}
$volume = "${dockerHostPath}:${imageDirUnix}"

Write-Host "Building review-ui image (florence-2-review-ui)..." -ForegroundColor Cyan
docker build -f docker/Dockerfile.review -t florence-2-review-ui .
if ($LASTEXITCODE -ne 0) { throw "docker build failed." }

Write-Host "Starting review UI at http://127.0.0.1:$Port ..." -ForegroundColor Green
Write-Host "docker run --rm -p ${Port}:7861 -v ${volume} florence-2-review-ui ..." -ForegroundColor DarkGray

docker run --rm `
  -p "${Port}:7861" `
  -v "${volume}" `
  florence-2-review-ui `
  python /workspace/review_ui.py `
    --captions "$imageDirUnix/captions.json" `
    --csv "$imageDirUnix/captions.csv" `
    --concept "$Concept" `
    --port 7861

if ($LASTEXITCODE -ne 0) { throw "review UI container exited with code $LASTEXITCODE" }
