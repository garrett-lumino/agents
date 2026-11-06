---
name: finetune-runbook
description: Use when fine-tuning an open-weight LLM (SFT, LoRA/QLoRA, DPO, ORPO, GRPO) locally with MLX-LM or mlx-lm-lora, or remotely on Hugging Face Jobs, Modal or RunPod.
---

# Fine-tune runbook

## Decide
1. **Prove fine-tuning is needed.** Show the task can't be met by prompting or RAG with the Claude API, by measuring it.
2. **Method:**
   - SFT first;
   - DPO/ORPO only with real preference pairs (ORPO needs no reference model, so it's cheaper locally);
   - GRPO only with a programmatic, hard-to-game reward.
3. **Size for this Mac (24 GB):**
   - QLoRA at 1.5–4B is comfortable;
   - 7–8B QLoRA is marginal (batch 1, seq ≤ 1024, `--grad-checkpoint`);
   - anything bigger goes to the cloud.

## Prepare
4. **Data hygiene.** Run training-data-hygiene. The data must have an attestation with 0 PAN hits.
5. **Format.** Validate the JSONL schema and the token-length distribution. Drop or truncate anything past `max_seq_length`.
6. **Chat template.** Render 3 examples through the model's chat template, and confirm loss masking trains on completions only.

## Train
7. **Local:** `make train-local MODEL=<mlx 4-bit model> RUN=<name>`. A quantized model means QLoRA automatically. Fix `--seed`.
8. **Overfit first.** Run about 50 examples for a few dozen iterations and confirm loss falls before the full run.
9. **Cloud:**
   - run gpu-cost-gate first and set a hard `--timeout`;
   - push adapters only to **private** repos (the vendored huggingface-llm-trainer examples are patched for this).
10. **Monitor** loss, validation loss, gradient norm, and tokens/sec. Stop on divergence, NaN, or a flat validation loss.

## Ship
11. **Version.** Keep the adapter separate from the fused model, and record the base model's revision SHA.
12. **Evaluate** with eval-design against the base model on the frozen test set.
13. **Export:**
    - `make export` (`mlx_lm.fuse`), then GGUF via a pinned llama.cpp (llama-cpp skill);
    - record the quant level (Q4_K_M / Q5_K_M);
    - smoke-test in Ollama.
14. **Licences.** Check the licences of the base model and the data before publishing or using it commercially.
15. **Never set `trust_remote_code=True`.** Pick a model that loads without it. Hooks block it.

Overlaps: huggingface-llm-trainer (cloud TRL/Unsloth mechanics), llama-cpp (GGUF/quantization); defer to them for flags and scripts.
