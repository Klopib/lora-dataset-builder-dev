# Architecture

## Goals

- Provide a repeatable, local pipeline to caption LoRA datasets.
- Keep everything containerized where possible.
- Minimize external dependencies and manual steps.

## Components

### Florence-2 API (Docker)
- Defined under `docker/` and launched via `start.ps1`.
- Exposes `http://localhost:8080/caption` and `http://localhost:8080/health`.

### Captioning pipeline (PowerShell)
- `caption.ps1`:
  - Starts the Florence-2 container (unless `-SkipAutoStart`).
  - Sends images to the caption API.
  - Optionally tagifies and normalizes captions (concept/pro-noun replacement).
  - Writes `captions.json` and `captions.csv` into the image folder.
  - Produces `caption_issues.csv` if validation flags are found.

### Review UI (Gradio in Docker)
- `review_ui.py`:
  - Lightweight UI for stepping through images and editing captions.
  - Uses `allowed_paths` set to the dataset directory.
- `run-review-ui.ps1`:
  - Builds the review UI image using `docker/Dockerfile.review`.
  - Mounts the dataset folder to `/data` and launches the UI.
  - Optionally reserves the port in `C:\AI\.registry.json`.

### Orchestration
- `New-LoRA.ps1` integrates captioning and review in a broader workflow.

## Data flow

1) User selects a dataset folder.
2) `caption.ps1` generates captions via Florence-2.
3) `review_ui.py` lets the user edit captions.
4) Final `captions.json/csv` flow into downstream training tools.

## Key paths

- Dataset root (example):
  `C:\AI\lora-dataset-builder\lora-training\<concept>\IMG\<rate>_<concept>`
- Review UI container mount: `/data`

## Ports

- Florence-2 API: 8080
- Review UI: 7861 (default)
