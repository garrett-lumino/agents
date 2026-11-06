import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "evals"))
import eval as ev  # evals/ is a script dir, not a package


def test_verify_frozen_accepts_matching_hash(tmp_path: Path) -> None:
    data = tmp_path / "t.jsonl"
    data.write_text('{"input": "a", "expected": "b"}\n')
    hash_file = tmp_path / "t.sha256"
    hash_file.write_text(ev.file_sha256(data) + "  t.jsonl\n")
    ev.verify_frozen(data, hash_file)


def test_verify_frozen_rejects_changed_set(tmp_path: Path) -> None:
    data = tmp_path / "t.jsonl"
    data.write_text("original\n")
    hash_file = tmp_path / "t.sha256"
    hash_file.write_text(ev.file_sha256(data))
    data.write_text("tampered\n")
    with pytest.raises(SystemExit):
        ev.verify_frozen(data, hash_file)


def test_exact_match_strips_whitespace() -> None:
    assert ev.exact_match([" a", "b", "x"], ["a", "b ", "c"]) == pytest.approx(2 / 3)
