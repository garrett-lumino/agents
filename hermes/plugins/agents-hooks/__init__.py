"""Run this repo's Claude Code hooks (claude/settings.json) inside Hermes.

PreToolUse  -> pre_tool_call: exit 2 blocks the call; stderr is the reason.
PostToolUse -> transform_tool_result: exit 2 stderr is appended to the result, so the
               agent sees what to fix (Claude Code feeds it back the same way).
Stop        -> pre_verify: exit 2 keeps the turn going with stderr as the message.

Hermes tools are renamed for the matchers (terminal=Bash, write_file=Write, patch=Edit)
and their args reshaped into Claude's tool_input. Async hooks (asyncRewake) are skipped.
"""

from __future__ import annotations

import logging
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from . import translate

logger = logging.getLogger(__name__)

_SETTINGS = Path(os.environ.get("AGENTS_HOOKS_SETTINGS", "~/agents/claude/settings.json")).expanduser()
_MAX_MESSAGE = 4000


def _run(hook: translate.Hook, stdin: str, cwd: str) -> Optional[str]:
    """Stderr of a hook that exited 2, else None. Errors and timeouts fail open, as in Claude Code."""
    try:
        proc = subprocess.run([hook.command], input=stdin, capture_output=True, text=True,
                              timeout=hook.timeout, cwd=cwd if os.path.isdir(cwd) else None)
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.warning("agents-hooks: %s did not run: %s", hook.command, exc)
        return None
    if proc.returncode == 2:
        return (proc.stderr.strip() or f"Blocked by {os.path.basename(hook.command)}")[:_MAX_MESSAGE]
    if proc.returncode != 0:
        logger.warning("agents-hooks: %s exited %d: %s", hook.command, proc.returncode, proc.stderr[:400])
    return None


def _fire(event: str, calls: Iterable[tuple], cwd: str, session_id: str,
          response: Optional[Dict[str, Any]] = None) -> List[str]:
    hooks, _skipped = translate.load_hooks(_SETTINGS, event)
    messages: List[str] = []
    for tool, tool_input in calls:
        stdin = translate.payload(event, tool, tool_input, cwd, session_id, response)
        messages += [m for h in hooks if h.matches(tool) and (m := _run(h, stdin, cwd))]
    return messages


def _cwd(task_id: str) -> str:
    """The directory the agent's terminal is in, which is what the hooks call cwd."""
    try:
        from tools.file_tools_paths import _resolve_base_dir
        return str(_resolve_base_dir(task_id or "default"))
    except Exception:  # private Hermes helper: fall back rather than break every tool call
        return os.getcwd()


def _on_pre_tool_call(tool_name: str = "", args: Any = None, task_id: str = "", session_id: str = "",
                      **_: Any) -> Optional[Dict[str, str]]:
    if not isinstance(args, dict):
        return None
    cwd = _cwd(task_id)
    blocked = _fire("PreToolUse", translate.tool_calls(tool_name, args, cwd), cwd, session_id)
    return {"action": "block", "message": "\n\n".join(blocked)} if blocked else None


def _on_transform_tool_result(tool_name: str = "", args: Any = None, result: Any = None, task_id: str = "",
                              session_id: str = "", status: str = "ok", **_: Any) -> Optional[str]:
    if not isinstance(args, dict) or not isinstance(result, str) or status != "ok":
        return None
    cwd = _cwd(task_id)
    calls = translate.tool_calls(tool_name, args, cwd)
    feedback = _fire("PostToolUse", calls, cwd, session_id, translate.tool_response(result))
    if not feedback:
        return None
    return result + "\n\nPostToolUse hook feedback (the call ran; fix this before continuing):\n" + "\n\n".join(feedback)


def _repo_root(directory: str) -> str:
    """One Stop run per repo, however many of its directories the turn edited."""
    proc = subprocess.run(["git", "-C", directory, "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else directory


def _on_pre_verify(changed_paths: Optional[List[str]] = None, attempt: int = 0, session_id: str = "",
                   **_: Any) -> Optional[Dict[str, str]]:
    """Stop hooks, once per repo the turn edited (stop-gate finds the repo from cwd)."""
    hooks, _skipped = translate.load_hooks(_SETTINGS, "Stop")
    messages: List[str] = []
    dirs = {os.path.dirname(p) for p in changed_paths or [] if os.path.isabs(p)}
    for cwd in sorted({_repo_root(d) for d in dirs if os.path.isdir(d)}):
        stdin = translate.stop_payload(session_id, cwd, stop_hook_active=attempt > 0)
        messages += [m for h in hooks if (m := _run(h, stdin, cwd))]
    unique = list(dict.fromkeys(messages))
    return {"action": "continue", "message": "\n\n".join(unique)} if unique else None


def register(ctx: Any) -> None:
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
    ctx.register_hook("transform_tool_result", _on_transform_tool_result)
    ctx.register_hook("pre_verify", _on_pre_verify)
