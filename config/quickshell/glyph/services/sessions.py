#!/usr/bin/env python3
# local: Claude Code session states for the bar (services/Sessions.qml).
# Run by Claude Code hooks (~/.claude/settings.json) with the hook's JSON on stdin, or by the shell as
# `sessions.py ack` (seen: done -> idle) and `sessions.py prune` (drop sessions whose claude process is gone).
# State per session: working, ask (permission prompt or a question), done (finished, not seen yet), idle.
# Hooks run async, so an event older than the session's last one is dropped.
import fcntl
import json
import os
import sys
import time

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "glyph")
PATH = os.path.join(CACHE, "claude-sessions.json")
LOCK = PATH + ".lock"


def claude_pid():
    # the hook runs under bash under claude; walk up to the first process named claude
    pid = os.getppid()
    for _ in range(8):
        try:
            with open(f"/proc/{pid}/stat") as f:
                stat = f.read()
        except OSError:
            return 0
        comm = stat[stat.index("(") + 1:stat.rindex(")")]
        if comm == "claude":
            return pid
        pid = int(stat[stat.rindex(")") + 2:].split()[1])
        if pid <= 1:
            return 0
    return 0


def alive(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip() == "claude"
    except OSError:
        return False


def load():
    try:
        with open(PATH) as f:
            return json.load(f).get("sessions", {})
    except (OSError, ValueError):
        return {}


def save(sessions):
    tmp = PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"sessions": sessions}, f)
    os.replace(tmp, PATH)


def hook(sessions, ev, now):
    sid = ev.get("session_id")
    name = ev.get("hook_event_name", "")
    if not sid:
        return False
    if name == "SessionEnd":
        return sessions.pop(sid, None) is not None
    s = sessions.get(sid)
    if s and now < s.get("at", 0):
        return False
    state = {
        "UserPromptSubmit": "working",
        "PostToolUse": "working",
        "PreToolUse": "ask",       # only matched for AskUserQuestion / ExitPlanMode
        "Notification": "ask",     # only matched for permission_prompt / elicitation_dialog
        "Stop": "done",
    }.get(name)
    if not s:
        cwd = ev.get("cwd") or ""
        s = sessions[sid] = {"cwd": cwd, "name": os.path.basename(cwd.rstrip("/")) or "~",
                             "state": "idle", "born": now, "pid": claude_pid()}
    elif name == "SessionStart":
        return False  # resume, clear, compact: keep what it was doing
    if state:
        s["state"] = state
    s["at"] = now
    return True


def main():
    os.makedirs(CACHE, exist_ok=True)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "hook"
    ev = {}
    if cmd == "hook":
        try:
            ev = json.load(sys.stdin)
        except ValueError:
            return
    now = int(time.time() * 1000)
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        sessions = load()
        changed = False
        if cmd == "hook":
            changed = hook(sessions, ev, now)
        elif cmd == "ack":
            for s in sessions.values():
                if s["state"] == "done":
                    s["state"] = "idle"
                    changed = True
        for sid in [k for k, s in sessions.items() if s.get("pid") and not alive(s["pid"])]:
            del sessions[sid]
            changed = True
        if changed or not os.path.exists(PATH):
            save(sessions)


if __name__ == "__main__":
    main()
