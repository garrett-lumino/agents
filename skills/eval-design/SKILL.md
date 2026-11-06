---
name: eval-design
description: Use when designing, running or interpreting an evaluation of an ML model or LLM app, including LLM-as-judge setups and regression comparisons across runs.
---

# Eval design

1. **Before running anything,** write down the metric, the "good enough" threshold, and what you're comparing against (baseline, base model, previous best).
2. **Freeze the test set.**
   - Store its SHA-256 in `evals/test_set.sha256`; `evals/eval.py` verifies it.
   - Never tune prompts or hyperparameters on it.
3. **Time-dependent data:** the test window comes strictly after the training window.
4. **Check for leakage:**
   - exact and near-duplicate overlap between train and test;
   - entity overlap (the same card token, customer, or merchant) where the task needs generalization.
5. **Prefer deterministic metrics** over judges: exact match, field-level F1, PR-AUC, cost-weighted loss.
6. **LLM-as-judge:**
   - anchored rubric examples;
   - 50+ hand labels, and report agreement with them;
   - randomized answer order;
   - a different model family from the model being judged.
7. **Fix sampling** (temperature 0 or fixed settings) and record it.
8. **Report per slice:** merchant category, amount band, new vs returning customer.
9. **Imbalanced data:** report precision and recall at the operating threshold, and PR-AUC. Never accuracy.
10. **Regression table.** Keep one across runs in MLflow. Fail the check if a key slice regresses beyond tolerance.
11. **Tools:**
    - lm-evaluation-harness or Inspect for general-capability checks;
    - promptfoo for app-level prompt regressions in CI.
12. **Store raw predictions,** not just aggregates.

Overlaps: ml-experiment-discipline (run hygiene); defer to training-data-hygiene for splits and leakage in payment data.
