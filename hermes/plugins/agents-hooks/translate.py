"""Translate Hermes tool calls into the Claude Code hook payloads that hooks/*.sh read.

Pure functions only: no Hermes imports, so tests run with any python3.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Pattern, Tuple

# Hermes tool -> the Claude Code tool name the settings.json matchers use. MCP tools
# are named mcp__<server>__<tool> in both harnesses, so they pass through unchanged.
CLAUDE_NAMES = {"terminal": "Bash", "write_file": "Write", "patch": "Edit"}

_V4A_FILE = re.compile(r"^\*\*\*\s*(Update|Add|Delete) File:\s*(.+?)\s*$")
_V4A_MOVE = re.compile(r"^\*\*\*\s*Move to:\s*(.+?)\s*$")


@dataclass(frozen=True)
class Hook:
    command: str
    timeout: int
    matcher: Optional[Pattern[str]]

    def matches(self, tool: str) -> bool:
        return self.matcher is None or self.matcher.fullmatch(tool) is not None


def load_hooks(settings: Path, event: str) -> Tuple[List[Hook], List[str]]:
    """(runnable hooks, skipped commands) for a Claude Code event in settings.json.

    Async hooks are skipped: Hermes has no way to wake the agent when they finish.
    """
    data = json.loads(settings.read_text(encoding="utf-8"))
    hooks: List[Hook] = []
    skipped: List[str] = []
    for group in data.get("hooks", {}).get(event, []):
        matcher = group.get("matcher")
        pattern = re.compile(matcher) if matcher else None
        for spec in group.get("hooks", []):
            command = os.path.expandvars(spec.get("command", ""))
            if spec.get("type", "command") != "command" or not command:
                continue
            if spec.get("async") or spec.get("asyncRewake"):
                skipped.append(command)
                continue
            hooks.append(Hook(command, int(spec.get("timeout", 60)), pattern))
    return hooks, skipped


def _abs(path: str, cwd: str) -> str:
    return os.path.normpath(os.path.join(cwd, os.path.expanduser(path)))


def v4a_files(patch: str) -> Dict[str, str]:
    """Target path -> added lines, for each file a V4A patch updates or adds."""
    files: Dict[str, List[str]] = {}
    current: Optional[str] = None
    for line in patch.splitlines():
        header, move = _V4A_FILE.match(line), _V4A_MOVE.match(line)
        if header:
            current = None if header.group(1) == "Delete" else header.group(2)
            if current is not None:
                files.setdefault(current, [])
        elif move and current is not None:
            files[move.group(1)] = files.pop(current)
            current = move.group(1)
        elif current is not None and line.startswith("+"):
            files[current].append(line[1:])
    return {path: "\n".join(lines) for path, lines in files.items()}


def tool_calls(tool: str, args: Dict[str, Any], cwd: str) -> List[Tuple[str, Dict[str, Any]]]:
    """(Claude tool name, Claude tool_input) for each hook run one Hermes call needs."""
    name = CLAUDE_NAMES.get(tool, tool)
    if tool == "terminal":
        return [(name, {"command": args.get("command") or ""})]
    if tool == "write_file":
        return [(name, {"file_path": _abs(args.get("path") or "", cwd), "content": args.get("content") or ""})]
    if tool == "patch" and args.get("patch"):
        return [(name, {"file_path": _abs(p, cwd), "new_string": s}) for p, s in v4a_files(args["patch"]).items()]
    if tool == "patch":
        edit = {"file_path": _abs(args.get("path") or "", cwd)}
        edit.update({k: args.get(k) or "" for k in ("old_string", "new_string")})
        return [(name, edit)]
    return [(name, args)]


def payload(event: str, tool: str, tool_input: Dict[str, Any], cwd: str, session_id: str,
            tool_response: Optional[Dict[str, Any]] = None) -> str:
    body: Dict[str, Any] = {"hook_event_name": event, "session_id": session_id, "cwd": cwd,
                            "tool_name": tool, "tool_input": tool_input}
    if tool_response is not None:
        body["tool_response"] = tool_response
    return json.dumps(body)


def stop_payload(session_id: str, cwd: str, stop_hook_active: bool) -> str:
    """stop_hook_active tells stop-gate the agent already kept going once for it."""
    return json.dumps({"hook_event_name": "Stop", "session_id": session_id, "cwd": cwd,
                       "stop_hook_active": stop_hook_active})


def tool_response(result: str) -> Dict[str, Any]:
    """Hermes results are JSON strings; terminal's carries `output`, which tf-plan-summary reads."""
    try:
        parsed = json.loads(result)
    except (TypeError, ValueError):
        return {"output": result}
    return parsed if isinstance(parsed, dict) else {"output": result}
