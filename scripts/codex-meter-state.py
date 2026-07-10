#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

VALID = {"waiting", "working", "done", "idle"}


def main() -> int:
    status = sys.argv[1] if len(sys.argv) > 1 else ""
    if status not in VALID:
        return 0

    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0

    thread_id = payload.get("session_id") or payload.get("thread_id")
    if (
        not isinstance(thread_id, str)
        or len(thread_id) != 36
        or any(character not in "0123456789abcdefABCDEF-" for character in thread_id)
    ):
        return 0

    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    state_dir = codex_home / "codex-meter" / "activity"
    state_dir.mkdir(parents=True, exist_ok=True)
    destination = state_dir / f"{thread_id}.json"
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(
        json.dumps({
            "threadId": thread_id,
            "status": status,
            "updatedAtMs": int(time.time() * 1000),
        }, separators=(",", ":")),
        encoding="utf-8",
    )
    temporary.replace(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
