---
name: training-data-hygiene
description: Use when preparing, uploading or sharing any dataset for training or evaluation, especially payment, customer or transaction data.
---

# Training data hygiene

## Sensitive data
1. **Classify** before using anything: cardholder data? PII? customer content? What's the licence of each source?
2. **Scan for PANs.** Run `~/agents/hooks/pan-scan.sh <files>`: Luhn-valid 13–19 digit runs, which it prints masked. Any hit stops the pipeline. Hooks also scan writes to `data/` and `evals/`.
3. **Scan for neighbours.** Also look for CVV/expiry patterns next to PAN-like strings, and for emails, phone numbers, IBANs, and names. Redact or tokenize them.
4. **Keep joins working** by replacing identifiers with keyed hashes (HMAC with a secret that never enters the repo).
5. **PCI scope.** Unredacted cardholder data sent to any third-party GPU, hosted notebook, or LLM API brings that service into PCI DSS scope. By default, only scrubbed or synthetic data leaves your machine.
6. **No marketplace GPUs** (e.g. RunPod Community Cloud) for anything derived from customer data.

## Splits and labels
7. **Fraud and forecasting split by time:** train ≤ T, validation (T, T+Δ], test after that. Never shuffle across time.
8. **Group by entity** (card token, customer, merchant) so the same entity doesn't appear on both sides, when the task needs generalization.
9. **Chargeback delay.** Labels mature late, so exclude the most recent window.
10. **Decision-time features only.** Remove anything not known at decision time (post-authorization fields, dispute outcomes).

## Record
11. **Provenance.** Record each dataset's licence and source, and exclude data whose licence forbids training.
12. **Write `.ml/data-attestation.json`:**
    ```json
    {"dataset_sha256":"<sha256 of the exact upload>","scanner":"pan-scan.sh","pan_hits":0,"date":"YYYY-MM-DD"}
    ```

Overlaps: eval-design (test-set leakage); defer to gpu-cost-gate before any upload.
