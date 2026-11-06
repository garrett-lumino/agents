# .ml/ gate files

The global `ml-launch-gate` hook reads these before any paid GPU launch (`hf jobs`, the HF MCP `hf_jobs` tool, `modal run/deploy`, `runpodctl create`, `together fine-tuning create`, `sky launch`) or `hf upload`. Missing or invalid files block the command.

## cost-estimate.json
Required for launches. It must be **less than 24h old**, because prices and plans change. See the `gpu-cost-gate` skill.
```json
{
  "provider": "hf",
  "flavor": "l4x1",
  "usd_per_hour": 0.80,
  "est_hours": 2.5,
  "est_usd": 2.60,
  "max_usd": 5,
  "timeout": "3h"
}
```
- `est_usd` must be `<= max_usd`.
- `max_usd` is set by a human. An agent must never raise it.

## data-attestation.json
Required for launches and uploads. See the `training-data-hygiene` skill.
```json
{
  "dataset_sha256": "<shasum -a 256 of the exact file uploaded>",
  "scanner": "pan-scan.sh",
  "pan_hits": 0,
  "date": "YYYY-MM-DD"
}
```
- `pan_hits` must be `0`.

Commit neither file if it holds anything sensitive. Both are safe as written above.
