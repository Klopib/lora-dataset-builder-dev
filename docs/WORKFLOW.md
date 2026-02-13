# Workflow

This doc describes the typical end-to-end flow for captioning and reviewing a dataset.

## 1) Start the Florence-2 API

```
./start.ps1
```

Confirm health:
```
curl http://localhost:8080/health
```

## 2) Caption a dataset folder

```
./caption.ps1 \
  -ImageDir "C:\AI\lora-dataset-builder\lora-training\mikey\IMG\12_mikey" \
  -Concept "mikey" \
  -Tagify \
  -Overwrite \
  -Instruction "focus on the subject; ignore background objects"
```

Outputs written into the image folder:
- `captions.json`
- `captions.csv`
- `caption_issues.csv` (only if validation flags occur)

## 3) Review and edit captions

```
./run-review-ui.ps1 \
  -ImageDir "C:\AI\lora-dataset-builder\lora-training\mikey\IMG\12_mikey" \
  -Concept "mikey" \
  -Port 7861
```

The UI saves on every navigation action. Use **End Task** when you’re done.

## 4) Continue downstream training

Use the updated `captions.json/csv` for training (kohya_ss or other).

## Notes

- If the Florence API is already running, `caption.ps1` will reuse it.
- `run-review-ui.ps1` builds a small review UI image locally and runs it with the dataset mounted at `/data`.
- If you see port conflicts, change `-Port`.
