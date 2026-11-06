"""Evaluate a model on the frozen test set and write runs/metrics.json.

Test set: evals/test_set.jsonl, one {"input": ..., "expected": ...} per line.
Its SHA-256 lives in evals/test_set.sha256; a mismatch means the set changed and the run stops.

  python evals/eval.py           full eval (replace `predict` with your model call)
  python evals/eval.py --smoke   first 10 examples with an echo predictor, to prove the pipeline runs
"""

import argparse
import hashlib
import json
import pathlib
import sys

TEST_SET = pathlib.Path("evals/test_set.jsonl")
HASH_FILE = pathlib.Path("evals/test_set.sha256")
METRICS = pathlib.Path("runs/metrics.json")
SMOKE_SIZE = 10


def file_sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_frozen(path: pathlib.Path, hash_file: pathlib.Path) -> None:
    expected = hash_file.read_text().split()[0] if hash_file.exists() else ""
    actual = file_sha256(path)
    if expected != actual:
        raise SystemExit(f"test set hash mismatch: {hash_file} has {expected!r}, file is {actual}")


def load_examples(path: pathlib.Path, limit: int | None = None) -> list[dict]:
    lines = [line for line in path.read_text().splitlines() if line.strip()]
    return [json.loads(line) for line in lines[:limit]]


def exact_match(predictions: list[str], expected: list[str]) -> float:
    if not expected:
        return 0.0
    hits = sum(p.strip() == e.strip() for p, e in zip(predictions, expected, strict=True))
    return hits / len(expected)


def predict(examples: list[dict], smoke: bool) -> list[str]:
    if smoke:
        return [str(ex["expected"]) for ex in examples]
    raise NotImplementedError("call your model here (Ollama / mlx_lm.server / Claude API)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    if not TEST_SET.exists():
        if args.smoke:
            print(f"eval-smoke: no {TEST_SET} yet, skipping")
            return 0
        raise SystemExit(f"missing {TEST_SET}")
    verify_frozen(TEST_SET, HASH_FILE)
    examples = load_examples(TEST_SET, SMOKE_SIZE if args.smoke else None)
    predictions = predict(examples, args.smoke)
    metrics = {
        "n": len(examples),
        "exact_match": exact_match(predictions, [str(e["expected"]) for e in examples]),
    }
    METRICS.parent.mkdir(exist_ok=True)
    METRICS.write_text(json.dumps(metrics, indent=2))
    print(json.dumps(metrics))
    return 0


if __name__ == "__main__":
    sys.exit(main())
