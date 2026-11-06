---
name: gpu-cost-gate
description: Use before launching any paid remote GPU job - hf jobs, the Hugging Face MCP hf_jobs tool, modal run/deploy, runpodctl, Lambda, Together fine-tuning, sky launch.
---

# GPU cost gate

The ml-launch-gate hook blocks launches until steps 5 and 7 are done.

1. **Tokens:**
   - SFT/DPO: examples × mean tokens × epochs;
   - GRPO: rollouts × group size × completion length (this is the term that blows budgets).
2. **Throughput** for the chosen GPU comes from a measured local or short-run figure, not a guess.
3. **Cost.** GPU-hours × the live $/h from the provider's price page, plus 30% headroom for retries and preemption.
4. **Budget.** Compare against the remaining monthly budget. Any single run above 50% of it needs the user's explicit approval.
5. **Write `.ml/cost-estimate.json`** (it must be under 24h old at launch):
   ```json
   {"provider":"hf","flavor":"l4x1","usd_per_hour":0.80,"est_hours":2.5,
    "est_usd":2.60,"max_usd":5,"timeout":"3h"}
   ```
   `max_usd` is a number **the user approved**. Never fill it in yourself.
6. **Always set a hard timeout** on the job itself, as well as in the file.
7. **Attestation.** `.ml/data-attestation.json` must exist for the exact dataset hash being uploaded, with `pan_hits: 0` (see training-data-hygiene).
8. **Never** use RunPod Community Cloud or other marketplace hosts for anything derived from customer data.
9. **Afterwards,** record the actual cost next to the estimate in the run record.

Overlaps: finetune-runbook (when to go to the cloud at all).
