# LoRA Dataset Builder (dev)

Local tooling to build and review LoRA training datasets using a Florence-2 captioning API and a lightweight browser review UI. This repo is intentionally dev-focused so the code can be shared and iterated quickly.

## What this repo does

- Starts a Florence-2 caption API in Docker.
- Batch captions image folders and writes `captions.json` + `captions.csv`.
- Opens a local review UI so you can step through images and edit captions.
- Preps outputs for downstream training (kohya_ss, etc.).

## Quickstart

Prereqs:
- Windows 10/11
- PowerShell 7+ (pwsh)
- Docker Desktop (Linux containers)

1) Start Florence-2 API:
```
./start.ps1
```

2) Caption a folder:
```
./caption.ps1 -ImageDir "C:\AI\lora-dataset-builder\lora-training\mikey\IMG\12_mikey" -Concept "mikey" -Tagify -Overwrite -Instruction "focus on the subject; ignore background objects"
```

3) Review captions in the UI (Dockerized):
```
./run-review-ui.ps1 -ImageDir "C:\AI\lora-dataset-builder\lora-training\mikey\IMG\12_mikey" -Concept "mikey" -Port 7861
```

Outputs:
- `captions.json`
- `captions.csv`
- `caption_issues.csv` (only if validation flags occur)

## Repository layout

```
/ docker/                # Florence API + review UI Dockerfiles/compose
/ docs/                  # Architecture and workflow notes
/ lora-training/         # Local datasets (ignored by git)
caption.ps1              # Batch captioning with Florence-2
review_ui.py             # Gradio review UI
run-review-ui.ps1        # Dockerized review UI runner
start.ps1                # Start Florence-2 API via docker compose
stop.ps1                 # Stop Florence-2 API
rebuild.ps1              # Rebuild Florence-2 API image
logs.ps1                 # Tail Florence-2 API logs
New-LoRA.ps1             # End-to-end orchestration (calls caption + review)
```

## Notes

- `run-review-ui.ps1` can reserve the port in `C:\AI\.registry.json` if that file exists.
- The review UI mounts the dataset folder at `/data` inside the container.
- Captions are written alongside the images in the dataset folder.

## Troubleshooting

- Port already in use: stop the existing container or use a different `-Port`.
- Florence API not responding: run `./start.ps1` and check `./logs.ps1`.
- Images not loading in UI: confirm the image folder is mounted and `captions.json` points to the right files.

## Architecture

See `docs/ARCHITECTURE.md` for components and data flow.
