<#
.SYNOPSIS
    Prepares a dataset for LoRA training.

.DESCRIPTION
    Creates a standardized folder structure and prepares images for LoRA training
    using kohya_ss or similar training frameworks.
    
    v1: Dataset preparation and folder structure only.
    v2: Will add integrated captioning.

.PARAMETER ConceptName
    Name of the concept you're training (e.g., "moroccan_caftan", "cyberpunk_edg").

.PARAMETER SourceImagesPath
    Path to folder containing source images.

.PARAMETER ConceptType
    Type: "character", "clothing", "style", "object".

.PARAMETER TrainingRate
    Number of times each image is repeated during training.

.EXAMPLE
    .\New-LoRA.ps1
.EXAMPLE
    .\New-LoRA.ps1 -ConceptName "my_character" -ConceptType character -SourceImagesPath "C:\Images\character"
#>

param(
    [string]$ConceptName,
    [string]$SourceImagesPath,
    [ValidateSet("character", "clothing", "style", "object", "")]
    [string]$ConceptType,
    [int]$TrainingRate,
    [string]$Instruction = "focus on the subject; ignore background objects"
)

# ─── Config ─────────────────────────────────────────────────────────────────

$BaseDir = "C:\\AI\\lora-dataset-builder\\lora-training"
$FlorenceDir = "C:\\AI\\lora-dataset-builder"
$CaptionScript = Join-Path $FlorenceDir "caption.ps1"
$ReviewScript  = Join-Path $FlorenceDir "run-review-ui.ps1"
$ErrorActionPreference = "Stop"

# ─── Helpers ────────────────────────────────────────────────────────────────

function Prompt-String {
    param([string]$Message, [string]$Default)
    $suffix = if ($Default) { " [$Default]" } else { "" }
    $val = Read-Host "$Message$suffix"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim()
}

function Prompt-Int {
    param([string]$Message, [int]$Default = 0)
    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { "" }
        $val = Read-Host "$Message$suffix"
        if ([string]::IsNullOrWhiteSpace($val) -and $Default) { return $Default }
        $parsed = 0
        if ([int]::TryParse($val, [ref]$parsed) -and $parsed -gt 0) { return $parsed }
        Write-Host "  Please enter a valid number." -ForegroundColor Yellow
    }
}

function Prompt-YesNo {
    param([string]$Message, [bool]$Default = $true)
    $hint = if ($Default) { "[Y]/n" } else { "y/[N]" }
    $val = Read-Host "$Message ($hint)"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return ($val.Trim().ToLower() -in @("y", "yes"))
}

function Show-TrainingRateInfo {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          Understanding Training Rate Per Image            ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The training rate controls how many times each image is seen" -ForegroundColor White
    Write-Host "during training. Think of it as 'repeats per image per epoch'." -ForegroundColor White
    Write-Host ""
    Write-Host "Effects of training rate:" -ForegroundColor Yellow
    Write-Host "  • Too LOW  → Model won't learn the concept properly" -ForegroundColor DarkGray
    Write-Host "               Result: Weak LoRA, inconsistent outputs" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  • Too HIGH → Model becomes inflexible and overfitted" -ForegroundColor DarkGray
    Write-Host "               Result: Won't mix well with other models" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Recommended rates (from EDG's tutorial):" -ForegroundColor Yellow
    Write-Host "  • Simple concepts (clothing, objects)    → 5-8" -ForegroundColor White
    Write-Host "  • Complex concepts (characters, people)  → 10-15" -ForegroundColor White
    Write-Host "  • Art styles                             → 8-12" -ForegroundColor White
    Write-Host ""
    Write-Host "Example: 31 images at rate 5 = 155 training steps per epoch" -ForegroundColor DarkGray
    Write-Host ""
    pause
}

function Show-ImageSelectionGuide {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║            How to Select Good Training Images             ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Key principle: DIVERSE yet HOMOGENEOUS" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "✓ DO include variety in:" -ForegroundColor Green
    Write-Host "  • Poses and angles" -ForegroundColor White
    Write-Host "  • Lighting conditions (bright, dim, natural, artificial)" -ForegroundColor White
    Write-Host "  • Backgrounds (indoor, outdoor, plain, detailed)" -ForegroundColor White
    Write-Host "  • Colors and styles (if applicable to concept)" -ForegroundColor White
    Write-Host "  • Distances (close-up, full body, medium shots)" -ForegroundColor White
    Write-Host ""
    Write-Host "✗ DON'T include:" -ForegroundColor Red
    Write-Host "  • Blurry or low-quality images" -ForegroundColor White
    Write-Host "  • Watermarked images (distracting)" -ForegroundColor White
    Write-Host "  • Images where concept is barely visible" -ForegroundColor White
    Write-Host "  • Completely inconsistent content" -ForegroundColor White
    Write-Host ""
    Write-Host "Recommended image count: 20-40 images" -ForegroundColor Yellow
    Write-Host "  • Minimum: 15 images (limited quality)" -ForegroundColor DarkGray
    Write-Host "  • Sweet spot: 25-35 images" -ForegroundColor DarkGray
    Write-Host "  • More isn't always better!" -ForegroundColor DarkGray
    Write-Host ""
    pause
}

function Analyze-Images {
    param([string]$Path)
    
    $imageFiles = Get-ChildItem -Path $Path -Include *.png,*.jpg,*.jpeg,*.webp,*.bmp -File -Recurse
    $count = $imageFiles.Count
    
    if ($count -eq 0) {
        Write-Host "  No images found in the specified path." -ForegroundColor Red
        return $null
    }
    
    # Load first image to check dimensions
    try {
        Add-Type -AssemblyName System.Drawing
        $firstImg = [System.Drawing.Image]::FromFile($imageFiles[0].FullName)
        $avgWidth = $firstImg.Width
        $avgHeight = $firstImg.Height
        $firstImg.Dispose()
    }
    catch {
        $avgWidth = "Unknown"
        $avgHeight = "Unknown"
    }
    
    return [PSCustomObject]@{
        Count = $count
        Files = $imageFiles
        AvgWidth = $avgWidth
        AvgHeight = $avgHeight
    }
}

# ─── Main Flow ──────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  LoRA Dataset Setup v2                    ║" -ForegroundColor Cyan
Write-Host "║        (Structure, Copy, Florence Caption + Review)       ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will prepare your images for LoRA training." -ForegroundColor White
Write-Host "Includes: folder setup, image copy, Florence-2 autocaption, review UI." -ForegroundColor DarkGray
Write-Host ""

# ─── Step 1: Concept Name ───────────────────────────────────────────────────

if (-not $ConceptName) {
    Write-Host "What concept are you training?" -ForegroundColor White
    Write-Host "  Examples: 'moroccan_caftan', 'edg_character', 'cyberpunk_style'" -ForegroundColor DarkGray
    Write-Host "  Use underscores instead of spaces" -ForegroundColor DarkGray
    Write-Host ""
    $ConceptName = Prompt-String "Concept name"
    if (-not $ConceptName) {
        Write-Host "Concept name is required." -ForegroundColor Red
        pause
        return
    }
}

$ConceptName = $ConceptName.ToLower() -replace '\s+', '_' -replace '[^a-z0-9_-]', ''
Write-Host "  Using concept name: $ConceptName" -ForegroundColor DarkGray

# ─── Step 2: Concept Type ───────────────────────────────────────────────────

if (-not $ConceptType) {
    Write-Host ""
    Write-Host "What type of concept are you training?" -ForegroundColor White
    Write-Host "  1. Character/Person    (Recommended rate: 12)" -ForegroundColor White
    Write-Host "  2. Clothing/Fashion    (Recommended rate: 6)" -ForegroundColor White
    Write-Host "  3. Art Style           (Recommended rate: 10)" -ForegroundColor White
    Write-Host "  4. Object/Item         (Recommended rate: 7)" -ForegroundColor White
    Write-Host ""
    Write-Host "  5. More information about training rates" -ForegroundColor Cyan
    Write-Host ""
    
    while ($true) {
        $choice = Read-Host "Choice (1-5)"
        if ($choice -eq "1") { $ConceptType = "character"; $suggestedRate = 12; break }
        if ($choice -eq "2") { $ConceptType = "clothing"; $suggestedRate = 6; break }
        if ($choice -eq "3") { $ConceptType = "style"; $suggestedRate = 10; break }
        if ($choice -eq "4") { $ConceptType = "object"; $suggestedRate = 7; break }
        if ($choice -eq "5") {
            Show-TrainingRateInfo
            Write-Host "What type of concept are you training?" -ForegroundColor White
            Write-Host "  1. Character/Person  2. Clothing/Fashion" -ForegroundColor White
            Write-Host "  3. Art Style         4. Object/Item" -ForegroundColor White
            Write-Host ""
            continue
        }
        Write-Host "  Please enter 1, 2, 3, 4, or 5." -ForegroundColor Yellow
    }
}
else {
    # Set suggested rate based on type if not interactive
    $suggestedRate = switch ($ConceptType) {
        "character" { 12 }
        "clothing"  { 6 }
        "style"     { 10 }
        "object"    { 7 }
        default     { 8 }
    }
}

Write-Host "  Selected: $ConceptType (suggested training rate: $suggestedRate)" -ForegroundColor DarkGray

# ─── Step 3: Source Images ──────────────────────────────────────────────────

if (-not $SourceImagesPath) {
    Write-Host ""
    Write-Host "Where are your source images?" -ForegroundColor White
    Write-Host "  You can drag and drop the folder here, or paste the path" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Need help selecting good images? Type 'H' for guidance" -ForegroundColor Cyan
    Write-Host ""
    
    while ($true) {
        $input = Read-Host "Image folder path (or H for help)"
        if ($input -eq "H" -or $input -eq "h") {
            Show-ImageSelectionGuide
            Write-Host "Where are your source images?" -ForegroundColor White
            continue
        }
        $SourceImagesPath = $input.Trim('"').Trim("'")
        if (Test-Path $SourceImagesPath) { break }
        Write-Host "  Path not found. Please try again." -ForegroundColor Yellow
    }
}

# ─── Step 4: Analyze Images ─────────────────────────────────────────────────

Write-Host ""
Write-Host "Analyzing images..." -ForegroundColor Cyan

$imageAnalysis = Analyze-Images -Path $SourceImagesPath

if (-not $imageAnalysis) {
    Write-Host "No valid images found. Exiting." -ForegroundColor Red
    pause
    return
}

$imageCount = $imageAnalysis.Count
Write-Host "  ✓ Found $imageCount images" -ForegroundColor Green

if ($imageAnalysis.AvgWidth -ne "Unknown") {
    Write-Host "  ✓ Sample resolution: $($imageAnalysis.AvgWidth)x$($imageAnalysis.AvgHeight)" -ForegroundColor Green
}

# Quality check
if ($imageCount -lt 15) {
    Write-Host ""
    Write-Host "  ⚠ WARNING: Less than 15 images detected" -ForegroundColor Yellow
    Write-Host "  Your LoRA quality will be significantly limited." -ForegroundColor Yellow
    Write-Host "  Recommended minimum: 20 images" -ForegroundColor Yellow
    Write-Host ""
    $continue = Prompt-YesNo "Continue anyway?" -Default $false
    if (-not $continue) {
        Write-Host "Cancelled. Please gather more images." -ForegroundColor Yellow
        pause
        return
    }
}
elseif ($imageCount -gt 100) {
    Write-Host ""
    Write-Host "  ⚠ NOTE: You have $imageCount images" -ForegroundColor Yellow
    Write-Host "  More isn't always better! 25-40 diverse images often work best." -ForegroundColor Yellow
    Write-Host "  Consider curating down to your best, most diverse shots." -ForegroundColor Yellow
    Write-Host ""
    $continue = Prompt-YesNo "Continue with all $imageCount images?" -Default $true
    if (-not $continue) {
        Write-Host "Cancelled. Please curate your image set." -ForegroundColor Yellow
        pause
        return
    }
}

# ─── Step 5: Training Rate ──────────────────────────────────────────────────

if (-not $TrainingRate -or $TrainingRate -le 0) {
    Write-Host ""
    Write-Host "How many times should each image be repeated during training?" -ForegroundColor White
    Write-Host "  Based on '$ConceptType', the recommended rate is: $suggestedRate" -ForegroundColor Cyan
    Write-Host "  This means each image will be seen $suggestedRate times per epoch." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Need more info? Type 'I' for training rate explanation" -ForegroundColor Cyan
    Write-Host ""
    
    while ($true) {
        $input = Read-Host "Training rate per image [$suggestedRate] (or I for info)"
        if ($input -eq "I" -or $input -eq "i") {
            Show-TrainingRateInfo
            Write-Host "Training rate per image [$suggestedRate]:" -ForegroundColor White
            continue
        }
        if ([string]::IsNullOrWhiteSpace($input)) {
            $TrainingRate = $suggestedRate
            break
        }
        $parsed = 0
        if ([int]::TryParse($input, [ref]$parsed) -and $parsed -gt 0) {
            $TrainingRate = $parsed
            break
        }
        Write-Host "  Please enter a valid number." -ForegroundColor Yellow
    }
}

$totalSteps = $imageCount * $TrainingRate
Write-Host "  ✓ Training rate set to: $TrainingRate" -ForegroundColor Green
Write-Host "  ✓ Total training steps per epoch: $totalSteps" -ForegroundColor Green

# ─── Step 6: Summary ────────────────────────────────────────────────────────

$projectDir = Join-Path $BaseDir $ConceptName
$imgDir = Join-Path $projectDir "IMG"
$trainDir = Join-Path $imgDir "${TrainingRate}_${ConceptName}"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor White
Write-Host "║                       SUMMARY                             ║" -ForegroundColor White
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor White
Write-Host ""
Write-Host "  Concept Name:         $ConceptName" -ForegroundColor White
Write-Host "  Concept Type:         $ConceptType" -ForegroundColor White
Write-Host "  Source Images:        $imageCount images" -ForegroundColor White
Write-Host "  Training Rate:        $TrainingRate repeats/image" -ForegroundColor White
Write-Host "  Steps Per Epoch:      $totalSteps" -ForegroundColor White
Write-Host ""
Write-Host "  Output Structure:" -ForegroundColor White
Write-Host "    $projectDir\" -ForegroundColor DarkGray
Write-Host "    └─ IMG\" -ForegroundColor DarkGray
Write-Host "       └─ ${TrainingRate}_${ConceptName}\" -ForegroundColor DarkGray
Write-Host "          ├─ 1.png" -ForegroundColor DarkGray
Write-Host "          ├─ 2.png" -ForegroundColor DarkGray
Write-Host "          └─ ... ($imageCount total)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  (Caption files will be added in v2)" -ForegroundColor DarkGray
Write-Host ""

$confirm = Prompt-YesNo "Proceed with dataset preparation?" -Default $true
if (-not $confirm) {
    Write-Host ""
    Write-Host "Cancelled." -ForegroundColor Yellow
    pause
    return
}

# ─── Step 7: Create Folder Structure ────────────────────────────────────────

Write-Host ""
Write-Host "Creating folder structure..." -ForegroundColor Cyan

if (Test-Path $projectDir) {
    Write-Host ""
    Write-Host "  ⚠ Project directory already exists: $projectDir" -ForegroundColor Yellow
    $overwrite = Prompt-YesNo "Overwrite existing dataset?" -Default $false
    if (-not $overwrite) {
        Write-Host "Cancelled. Please choose a different concept name." -ForegroundColor Yellow
        pause
        return
    }
    Remove-Item -Path $projectDir -Recurse -Force
    Write-Host "  ✓ Removed existing directory" -ForegroundColor Green
}

New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
New-Item -ItemType Directory -Path $imgDir -Force | Out-Null
New-Item -ItemType Directory -Path $trainDir -Force | Out-Null

Write-Host "  ✓ Created $projectDir" -ForegroundColor Green
Write-Host "  ✓ Created $imgDir" -ForegroundColor Green
Write-Host "  ✓ Created $trainDir" -ForegroundColor Green

# ─── Step 8: Copy and Rename Images ─────────────────────────────────────────

Write-Host ""
Write-Host "Copying and renaming images..." -ForegroundColor Cyan

$counter = 1
foreach ($imgFile in $imageAnalysis.Files) {
    $extension = $imgFile.Extension
    $newName = "$counter$extension"
    $destPath = Join-Path $trainDir $newName
    
    Copy-Item -Path $imgFile.FullName -Destination $destPath -Force
    
    if ($counter % 10 -eq 0) {
        Write-Host "  ✓ Processed $counter / $imageCount images..." -ForegroundColor DarkGray
    }
    
    $counter++
}

Write-Host "  ✓ All $imageCount images copied and renamed" -ForegroundColor Green

# ─── Step 9: Caption with Florence-2 ────────────────────────────────────────

Write-Host ""
Write-Host "Running Florence-2 autocaptioning..." -ForegroundColor Cyan

if (-not (Test-Path $CaptionScript)) {
    throw "caption.ps1 not found at $CaptionScript"
}

& pwsh -File $CaptionScript `
    -ImageDir $trainDir `
    -Concept $ConceptName `
    -Tagify `
    -Overwrite `
    -Instruction $Instruction

if ($LASTEXITCODE -ne 0) { throw "Captioning failed (exit code $LASTEXITCODE)" }

Write-Host "  ✓ Captions generated: captions.json / captions.csv" -ForegroundColor Green

# ─── Step 10: Launch Review UI (Docker) ─────────────────────────────────────

Write-Host ""
Write-Host "Launching caption review UI (Docker)..." -ForegroundColor Cyan

if (-not (Test-Path $ReviewScript)) {
    throw "run-review-ui.ps1 not found at $ReviewScript"
}

& pwsh -File $ReviewScript `
    -ImageDir $trainDir `
    -Concept $ConceptName `
    -Port 7861

if ($LASTEXITCODE -ne 0) {
    throw "Review UI failed to start (exit code $LASTEXITCODE)"
}

# ─── Step 9: Create Info File ───────────────────────────────────────────────

$infoContent = @"
LoRA Dataset: $ConceptName
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Configuration:
- Concept Type: $ConceptType
- Image Count: $imageCount
- Training Rate: $TrainingRate
- Steps Per Epoch: $totalSteps

Source Images: $SourceImagesPath

Next Steps:
1. Captions generated automatically (captions.json/captions.csv) in $trainDir
2. Review/edit captions in the browser UI (launched automatically)
3. Close the UI when finished; proceed to training (kohya_ss config step)

Notes:
- Captions are tag-based and begin with concept name: $ConceptName
- Validation flags (if any) are recorded in caption_issues.csv
"@

$infoPath = Join-Path $projectDir "dataset_info.txt"
$infoContent | Set-Content -Path $infoPath -Encoding UTF8

Write-Host "  ✓ Created dataset info file" -ForegroundColor Green

# ─── Final Output ───────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              Dataset Preparation Complete!                ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Your dataset is ready at:" -ForegroundColor White
Write-Host "  $projectDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "What's been set up:" -ForegroundColor White
Write-Host "  ✓ Folder structure created" -ForegroundColor Green
Write-Host "  ✓ $imageCount images copied and renamed (1.png, 2.png, ...)" -ForegroundColor Green
Write-Host "  ✓ Training rate: $TrainingRate ($totalSteps steps/epoch)" -ForegroundColor Green
Write-Host "  ✓ Captions generated: $trainDir\\captions.json / captions.csv" -ForegroundColor Green
Write-Host "  ✓ Review UI launched at the chosen port (ctrl+c to stop when done)" -ForegroundColor Green
Write-Host ""

$openExplorer = Prompt-YesNo "Open dataset folder in Explorer?" -Default $true
if ($openExplorer) {
    explorer $trainDir
}

Write-Host ""
Write-Host "Dataset preparation complete! 🎉" -ForegroundColor Green
Write-Host ""
pause
