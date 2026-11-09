"""agents-hooks Hermes plugin: Hermes tool calls reach the real hooks in Claude Code's shape."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "hermes" / "plugins"))
plugin = __import__("agents-hooks")  # package name has a dash, as Hermes' plugin key does
translate = plugin.translate

# Point the plugin at this checkout's settings and hooks, not whatever ~/agents links to.
SETTINGS = json.loads((ROOT / "claude" / "settings.json").read_text())
TMP = Path(tempfile.mkdtemp())
for groups in SETTINGS["hooks"].values():
    for group in groups:
        for h in group["hooks"]:
            h["command"] = h["command"].replace("$HOME/agents", str(ROOT))
(TMP / "settings.json").write_text(json.dumps(SETTINGS))
plugin._SETTINGS = TMP / "settings.json"
plugin._cwd = lambda task_id: str(TMP)


def git(*args, cwd):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


class Translate(unittest.TestCase):
    def test_terminal_is_bash(self):
        self.assertEqual(translate.tool_calls("terminal", {"command": "ls"}, "/x"), [("Bash", {"command": "ls"})])

    def test_relative_write_path_is_absolute(self):
        [(name, inp)] = translate.tool_calls("write_file", {"path": "a/b.go", "content": "c"}, "/repo")
        self.assertEqual((name, inp["file_path"], inp["content"]), ("Write", "/repo/a/b.go", "c"))

    def test_v4a_patch_splits_per_file_with_added_lines(self):
        patch = "\n".join(["*** Begin Patch", "*** Update File: x.go", "@@", "-old", "+new1", " ctx", "+new2",
                           "*** Add File: y.py", "+hello", "*** Delete File: z.ts", "*** End Patch"])
        calls = translate.tool_calls("patch", {"mode": "patch", "patch": patch}, "/r")
        self.assertEqual(calls, [("Edit", {"file_path": "/r/x.go", "new_string": "new1\nnew2"}),
                                 ("Edit", {"file_path": "/r/y.py", "new_string": "hello"})])

    def test_mcp_names_pass_through(self):
        self.assertEqual(translate.tool_calls("mcp__supabase__execute_sql", {"query": "q"}, "/")[0][0],
                         "mcp__supabase__execute_sql")

    def test_async_hooks_are_skipped(self):
        hooks, skipped = translate.load_hooks(plugin._SETTINGS, "PostToolUse")
        self.assertTrue(any(c.endswith("ci-watch.sh") for c in skipped))
        self.assertFalse(any(h.command.endswith("ci-watch.sh") for h in hooks))


class PreToolCall(unittest.TestCase):
    def test_destructive_command_blocked(self):
        out = plugin._on_pre_tool_call(tool_name="terminal", args={"command": "rm -rf ~"})
        self.assertEqual(out["action"], "block")
        self.assertIn("guard-bash", out["message"])

    def test_safe_command_allowed(self):
        self.assertIsNone(plugin._on_pre_tool_call(tool_name="terminal", args={"command": "ls -la"}))

    def test_mcp_sql_blocked(self):
        out = plugin._on_pre_tool_call(tool_name="mcp__supabase__execute_sql", args={"query": "DROP TABLE users"})
        self.assertEqual(out["action"], "block")

    def test_file_tools_have_no_pre_hooks(self):
        self.assertIsNone(plugin._on_pre_tool_call(tool_name="write_file", args={"path": "x", "content": "rm -rf ~"}))


class TransformToolResult(unittest.TestCase):
    def test_float_money_feedback_appended(self):
        args = {"path": "pay.go", "content": "type Charge struct { Amount float64 }"}
        out = plugin._on_transform_tool_result(tool_name="write_file", args=args, result='{"bytes_written": 1}')
        self.assertTrue(out.startswith('{"bytes_written": 1}'))
        self.assertIn("Float money", out)

    def test_v4a_patch_checked(self):
        patch = "*** Begin Patch\n*** Update File: pay.go\n@@\n+var totalPrice float32\n*** End Patch"
        out = plugin._on_transform_tool_result(tool_name="patch", args={"patch": patch}, result="{}")
        self.assertIn("Float money", out)

    def test_clean_write_unchanged(self):
        args = {"path": "pay.go", "content": "type Charge struct { AmountMinor int64 }"}
        self.assertIsNone(plugin._on_transform_tool_result(tool_name="write_file", args=args, result="{}"))

    def test_failed_call_not_checked(self):
        args = {"path": "pay.go", "content": "var totalPrice float32"}
        self.assertIsNone(plugin._on_transform_tool_result(tool_name="write_file", args=args, result="{}",
                                                           status="error"))

    def test_terraform_plan_output_reaches_hook(self):
        result = json.dumps({"output": "  # aws_db_instance.main will be destroyed\nPlan: 0 to add, 0 to change, 1 to destroy.",
                             "exit_code": 0})
        out = plugin._on_transform_tool_result(tool_name="terminal", args={"command": "terraform plan"}, result=result)
        self.assertIn("aws_db_instance.main", out)


class PreVerify(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        git("init", "-q", cwd=self.repo)
        self.edited = [str(self.repo / "x.txt")]

    def test_failing_check_keeps_turn_going(self):
        (self.repo / "Makefile").write_text("check:\n\t@echo broken; exit 1\n")
        out = plugin._on_pre_verify(changed_paths=self.edited, attempt=0)
        self.assertEqual(out["action"], "continue")
        self.assertIn("make check failed", out["message"])

    def test_one_check_per_repo(self):
        (self.repo / "sub").mkdir()
        (self.repo / "Makefile").write_text("check:\n\t@echo run >> runs.log; exit 1\n")
        plugin._on_pre_verify(changed_paths=self.edited + [str(self.repo / "sub" / "y.txt")], attempt=0)
        self.assertEqual((self.repo / "runs.log").read_text(), "run\n")

    def test_second_attempt_lets_turn_finish(self):
        (self.repo / "Makefile").write_text("check:\n\t@exit 1\n")
        self.assertIsNone(plugin._on_pre_verify(changed_paths=self.edited, attempt=1))

    def test_passing_check_finishes(self):
        (self.repo / "Makefile").write_text("check:\n\t@true\n")
        self.assertIsNone(plugin._on_pre_verify(changed_paths=self.edited, attempt=0))


class Register(unittest.TestCase):
    def test_registers_three_hooks(self):
        seen = []
        plugin.register(type("Ctx", (), {"register_hook": lambda self, name, cb: seen.append(name)})())
        self.assertEqual(seen, ["pre_tool_call", "transform_tool_result", "pre_verify"])


if __name__ == "__main__":
    os.environ.pop("AGENTS_HOOK_DEBUG", None)
    unittest.main(verbosity=1)
