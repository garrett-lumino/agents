---
name: ml-experiment-discipline
description: Use when training, tuning or comparing any ML model (gradient boosting, PyTorch, LLM fine-tune) or when reporting a model metric. Not for inference-only or application code.
---

# ML experiment discipline

1. **Decision first.** Before any code, state the decision this experiment informs and the metric that decides it.
2. **Two baselines first:** a trivial one (majority class, last value, rules) and a strong simple one (gradient boosting, or the base LLM zero/few-shot).
3. **Reproducibility.**
   - Fix seeds (Python, NumPy, torch/MLX) and record library versions (`uv.lock`).
   - Write the full config to `runs/<id>/config.yaml` before training starts.
   - Hash the train/val/test files (SHA-256) and record the hashes with the git commit SHA. Refuse to run on a dirty tree.
4. **Smoke before scale.**
   - Overfit about 50 examples or one batch first; loss should approach zero. If it doesn't, the pipeline is broken.
   - Then do a short full-data run, and check that loss and the validation metric move the right way.
5. **One variable at a time.** Name each run after what changed.
6. **Clean metrics.** Never report a metric computed on data used for training, early stopping, or prompt/hyperparameter selection.
7. **Small wins need proof.** Claimed improvements under about 2 points need bootstrap confidence intervals or several seeds.
8. **Record every run** in MLflow: config, data hashes, commit SHA, metrics, artifact path, wall-clock time, and cost.
9. **Close with a written decision:** ship, iterate, or abandon, and why.

Overlaps: superpowers verification-before-completion and the Karpathy guidelines (general discipline; this skill is the ML-specific part). Defer to eval-design for test-set construction and training-data-hygiene for data preparation.
