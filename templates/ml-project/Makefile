# `make check` is the definition of done. The global Stop hook runs it.
PAN_SCAN ?= $(HOME)/agents/hooks/pan-scan.sh
MODEL ?=
RUN ?= run-001
ITERS ?= 600

.PHONY: check lint test pan-scan eval-smoke train-local overfit eval export

check: lint test pan-scan eval-smoke

lint:
	uv run --group dev ruff check .
	uv run --group dev ruff format --check .

test:
	uv run --group dev pytest -q

# Any Luhn-valid card number in data/ or evals/ fails the build.
pan-scan:
	@files=$$(find data evals -type f \( -name '*.jsonl' -o -name '*.csv' -o -name '*.json' -o -name '*.txt' \) 2>/dev/null); \
	if [ -n "$$files" ]; then $(PAN_SCAN) $$files; else echo "pan-scan: no data files"; fi

# Tiny end-to-end eval on the frozen test set (skips until one exists).
eval-smoke:
	uv run --group dev python evals/eval.py --smoke

# --- Training (MLX, Apple Silicon). See finetune-runbook.
overfit:
	@test -n "$(MODEL)" || { echo "usage: make overfit MODEL=<mlx 4-bit model>"; exit 1; }
	uv run --extra train mlx_lm.lora --model $(MODEL) --train --data data/overfit \
		--iters 60 --adapter-path adapters/overfit --seed 42

train-local:
	@test -n "$(MODEL)" || { echo "usage: make train-local MODEL=<mlx 4-bit model> RUN=<name>"; exit 1; }
	uv run --extra train mlx_lm.lora --model $(MODEL) --train --data data/processed \
		--iters $(ITERS) --adapter-path adapters/$(RUN) --grad-checkpoint --seed 42

eval:
	uv run --extra train python evals/eval.py

export:
	uv run --extra train mlx_lm.fuse --model $(MODEL) --adapter-path adapters/$(RUN) --save-path models/$(RUN)
