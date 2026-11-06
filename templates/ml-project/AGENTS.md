# <Project name>: ML Agent Rules

Global rules live in `~/agents/AGENTS.md`. This repo is an ML project (`[tool.ml]` in pyproject.toml).

## Skills to use
- `ml-experiment-discipline`: every training or comparison run.
- `training-data-hygiene`: before data enters `data/` or leaves this machine.
- `eval-design`: the test set and metrics.
- `finetune-runbook`: LLM fine-tunes (MLX locally, HF Jobs in the cloud).
- `gpu-cost-gate`: before any paid GPU job. Write `.ml/cost-estimate.json` and let the user set `max_usd`.

## Commands
- `make check`: lint, tests, PAN scan of data/ and evals/, and the eval smoke test. Done means this passes.
- `make overfit MODEL=...`, then `make train-local MODEL=... RUN=...`, then `make eval`, then `make export`.

## Layout
```
data/raw/         never committed; source extracts (scrubbed before use)
data/processed/   never committed; train/valid JSONL produced by scripts
evals/            frozen test set + hash, eval.py (committed, scrubbed, small)
adapters/ models/ never committed; weights
runs/             metrics and run records (MLflow at http://localhost:5000)
.ml/              cost-estimate.json and data-attestation.json gate files
```

## Project specifics
- Task: <one sentence>. Decision metric: <metric + threshold>. Baselines: <rules>, <base model>.
- Time split: train ≤ <date>, valid ≤ <date>, test after.
