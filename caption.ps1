<#
  Batch captioning helper for Florence-2.
  Usage:
    ./caption.ps1 -ImageDir "C:\AI\lora-training\mikey\IMG\12_mikey" -Concept "mikey"
  Optional:
    -Task "<MORE_DETAILED_CAPTION>"        # Florence prompt token
    -Endpoint "http://localhost:8080/caption"
    -Tagify                               # turn prose into simple comma tags
    -Overwrite                            # re-caption even if captions.json exists
    -Instruction "focus on subject"       # optional plain-English guidance appended to the task
    -ReviewUI                             # open a Gradio review UI to step through captions
    -PythonExe "C:\Users\admin\AppData\Local\Programs\Python\Python310\python.exe" # Python for Gradio UI
#>

param(
  [Parameter(Mandatory = $true)][string]$ImageDir,
  [Parameter(Mandatory = $true)][string]$Concept,
  [string]$Task = "<MORE_DETAILED_CAPTION>",
  [string]$Endpoint = "http://localhost:8080/caption",
  [string]$Instruction,
  [switch]$Tagify,
  [switch]$Overwrite,
  [switch]$ReviewUI,
  [int]$ReviewPort = 7860,
  [string[]]$PythonExe = @("C:\Users\admin\AppData\Local\Programs\Python\Python310\python.exe"),
  [string]$ReviewVenvPath = (Join-Path $PSScriptRoot ".venv_review"),
  [string]$FlorenceRoot = $PSScriptRoot,   # repo root that contains /docker
  [switch]$SkipAutoStart                    # set if you want to manage Docker yourself
)

$ErrorActionPreference = "Stop"

function Ensure-Florence {
  param([string]$ComposeDir)

  if ($SkipAutoStart) {
    Write-Host "SkipAutoStart set; assuming Florence API is already up at $Endpoint" -ForegroundColor Yellow
    return
  }

  $running = docker ps --filter "name=florence-2" --format "{{.Names}}"
  if (-not $running) {
    Write-Host "Starting florence-2 container via docker compose..." -ForegroundColor Cyan
    Push-Location $ComposeDir
    docker compose up -d
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) {
      throw "docker compose up failed (exit $code)"
    }
  } else {
    Write-Host "florence-2 container already running." -ForegroundColor DarkGray
  }
}

function Wait-FlorenceReady {
  param([string]$HealthUrl, [int]$Retries = 30, [int]$DelaySeconds = 2)
  for ($i = 1; $i -le $Retries; $i++) {
    try {
      $resp = Invoke-RestMethod -Method Get -Uri $HealthUrl -TimeoutSec 5
      if ($resp.status -eq "ok") {
        Write-Host "Florence healthcheck passed on attempt $i." -ForegroundColor Green
        return
      }
    } catch {}
    Start-Sleep -Seconds $DelaySeconds
  }
  throw "Florence API did not become ready at $HealthUrl after $Retries attempts."
}

function Ensure-Gradio {
  $cmd = $PythonExe
  if ($cmd.Count -eq 1 -and $cmd[0] -match '\s') { $cmd = $cmd[0] -split '\s+' }
  if ($cmd.Count -eq 1 -and -not (Test-Path $cmd[0])) { $cmd = @("py", "-3.10") }
  & $cmd -c "import gradio" 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "gradio not available in Python '$($cmd -join ' ')'. Install with: $($cmd -join ' ') -m pip install --only-binary=:all: gradio==4.44.1"
  }
  return $cmd
}

function Get-FreePort {
  param([int]$Preferred = 7860, [int]$Tries = 20)
  for ($i = 0; $i -lt $Tries; $i++) {
    $port = $Preferred + $i
    $listener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Parse("127.0.0.1"), $port)
    try {
      $listener.Start()
      $listener.Stop()
      return $port
    } catch {
      continue
    }
  }
  throw "Could not find a free port starting at $Preferred"
}

function Start-ReviewUI {
  param([string]$JsonPath, [string]$CsvPath)
  $cmd = Ensure-Gradio
  $uiScript = Join-Path $PSScriptRoot "review_ui.py"
  if (-not (Test-Path $uiScript)) {
    throw "review_ui.py not found at $uiScript"
  }
  $port = Get-FreePort -Preferred $ReviewPort
  Write-Host "Launching review UI at http://127.0.0.1:$port ..." -ForegroundColor Green
  & $cmd $uiScript --captions $JsonPath --csv $CsvPath --concept $Concept --port $port
}

if (-not (Test-Path $ImageDir)) {
  throw "ImageDir not found: $ImageDir"
}

$outJson = Join-Path $ImageDir "captions.json"
$outCsv  = Join-Path $ImageDir "captions.csv"

if (-not $Overwrite -and (Test-Path $outJson)) {
  Write-Host "captions.json already exists; use -Overwrite to regenerate." -ForegroundColor Yellow
  exit 0
}

$composeDir = Join-Path $FlorenceRoot "docker"
if (-not (Test-Path (Join-Path $composeDir "docker-compose.yml"))) {
  throw "Cannot locate docker-compose.yml under $composeDir. Use -FlorenceRoot to point at florence-2 repo."
}

Ensure-Florence -ComposeDir $composeDir
Wait-FlorenceReady -HealthUrl "http://localhost:8080/health"

function Get-FlorenceCaption {
  param([string]$Path)

  $form = @{
    file = Get-Item $Path
    task = $Task
  }

  $resp = Invoke-RestMethod -Method Post -Uri $Endpoint -Form $form -TimeoutSec 300

  # Result may be keyed by task token or "caption"
  if ($resp.result.$Task) { return [string]$resp.result.$Task }
  if ($resp.result.caption) { return [string]$resp.result.caption }
  if ($resp.result) { return [string]$resp.result }
  return ""
}

function Convert-ToTags {
  param([string]$Caption)

  # Light tag extraction: split on punctuation/and, drop articles, lower-case.
  $clean = ($Caption -replace '[\r\n]', ' ') -replace '[\.;]', ',' -replace '\s+', ' '
  $parts = $clean -split ',| and '
  $tags = foreach ($p in $parts) {
    $t = $p.Trim().ToLower()
    if (-not $t) { continue }
    $t = $t -replace '^(a|an|the)\s+', ''
    if ($t) { $t }
  }
  $unique = $tags | Where-Object { $_ } | Select-Object -Unique
  return ($unique -join ', ')
}

function Replace-Subject {
  param([string]$Text)
  # Normalize references to people to the concept name (assumes single subject per image).
  $out = $Text
  $out = $out -replace "(?i)\b(man|woman|boy|girl)'s", "$Concept's"
  $out = $out -replace "(?i)\b(man|woman|boy|girl)\b", $Concept
  $out = $out -replace "(?i)\ba\s+$([regex]::Escape($Concept))\b", $Concept
  $out = $out -replace "(?i)\ban\s+$([regex]::Escape($Concept))\b", $Concept
  # Pronouns -> concept
  $out = $out -replace "(?i)\b(he|she|they)\s+is\b", "$Concept is"
  $out = $out -replace "(?i)\b(he|she|they)\s+was\b", "$Concept was"
  $out = $out -replace "(?i)\b(he|she|they)\s+has\b", "$Concept has"
  $out = $out -replace "(?i)\b(he|she|they)\s+have\b", "$Concept have"
  $out = $out -replace "(?i)\b(he|she|they)\s+wearing\b", "$Concept wearing"
  $out = $out -replace "(?i)\b(his|her|their)\b", "$Concept's"
  $out = $out -replace "(?i)\b(him|her|them)\b", $Concept
  $out = $out -replace "(?i)\b(he|she|they)\b", $Concept
  return $out
}

function Apply-Instruction {
  param([string]$Caption)
  if ([string]::IsNullOrWhiteSpace($Instruction)) { return $Caption }

  $text = $Caption
  $instr = $Instruction.ToLower()

  if ($instr -match "ignore background|less background|focus on (the )?(subject|person)|focus on the man") {
    $parts = $text -split ',\s*'
    $filtered = $parts | Where-Object { $_ -notmatch 'background|wall|door|window|room|house|building|trees?|sky' }
    if ($filtered.Count -gt 0) {
      $text = ($filtered -join ', ')
    }
  }

  return $text
}

function Get-Jaccard {
  param([string]$A, [string]$B)
  $setA = [System.Collections.Generic.HashSet[string]]::new(($A -split ',\s*'))
  $setB = [System.Collections.Generic.HashSet[string]]::new(($B -split ',\s*'))
  $inter = ($setA | Where-Object { $setB.Contains($_) }).Count
  $union = ($setA + $setB | Select-Object -Unique).Count
  if ($union -eq 0) { return 0 }
  return [double]$inter / $union
}

$images = Get-ChildItem -Path $ImageDir -Include *.png,*.jpg,*.jpeg,*.webp -Recurse |
  Sort-Object @{Expression = {
      $m = [regex]::Match($_.BaseName, '\d+')
      if ($m.Success) { [int]$m.Value } else { [int]::MaxValue }
    }}, @{Expression = { $_.FullName }}
if (-not $images) {
  throw "No images found under $ImageDir"
}

$result = @()
foreach ($img in $images) {
  Write-Host "Captioning $($img.FullName)" -ForegroundColor DarkGray
  $raw = Get-FlorenceCaption -Path $img.FullName
  $body = if ($Tagify) { Convert-ToTags -Caption $raw } else { $raw.Trim() }
  $body = Replace-Subject -Text $body
  $body = Apply-Instruction -Caption $body
  $final = if ($body.StartsWith($Concept, 'InvariantCultureIgnoreCase')) {
    $body
  } else {
    "$Concept, $body"
  }

  $result += [pscustomobject]@{
    image         = $img.FullName
    raw_caption   = $raw
    final_caption = $final
  }
}

# Simple validation: length and near-duplicates.
$issues = @()
for ($i = 0; $i -lt $result.Count; $i++) {
  $cap = $result[$i].final_caption
  $tags = $cap -split ',\s*'
  if ($tags.Count -lt 4 -or $tags.Count -gt 40) {
    $issues += [pscustomobject]@{ image = $result[$i].image; issue = "Tag count=$($tags.Count)" }
  }
  for ($j = $i + 1; $j -lt $result.Count; $j++) {
    $sim = Get-Jaccard -A $cap -B $result[$j].final_caption
    if ($sim -gt 0.85) {
      $issues += [pscustomobject]@{
        image = $result[$i].image
        issue = "Too similar to $($result[$j].image) (Jaccard=$('{0:N2}' -f $sim))"
      }
    }
  }
}

$result | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $outJson
$result | Export-Csv -Encoding utf8 -NoTypeInformation $outCsv

if ($issues.Count) {
  $issuesPath = Join-Path $ImageDir "caption_issues.csv"
  $issues | Export-Csv -Encoding utf8 -NoTypeInformation $issuesPath
  Write-Host "Validation issues logged to $issuesPath" -ForegroundColor Yellow
} else {
  Write-Host "No validation flags." -ForegroundColor Green
}

Write-Host "Saved captions to $outJson and $outCsv" -ForegroundColor Green

if ($ReviewUI) {
  Start-ReviewUI -JsonPath $outJson -CsvPath $outCsv
}

