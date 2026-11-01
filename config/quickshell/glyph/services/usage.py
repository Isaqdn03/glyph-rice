#!/usr/bin/python3 -I
# local: Claude and Codex plan limits as one JSON line for services/Usage.qml.
# Claude: the OAuth usage endpoint Claude Code's /usage reads (undocumented), with Claude Code's own token,
# skipped while that token is expired (Claude Code refreshes it on its next run). Codex: its app-server's
# account/rateLimits/read, so Codex handles its own token. Tokens never leave this process or reach stdout.
# A failed fetch keeps that agent's last good numbers from the cache, marked stale.
import json, os, subprocess, threading, time, urllib.request
from datetime import datetime

HOME = os.path.expanduser("~")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", HOME + "/.cache"), "glyph", "agents.json")


def ms(v):
    """ISO string or epoch seconds -> epoch ms; 0 when unknown."""
    if not v:
        return 0
    if isinstance(v, (int, float)):
        return int(v * 1000)
    try:
        return int(datetime.fromisoformat(v).timestamp() * 1000)
    except ValueError:
        return 0


def window(mins):
    if mins == 300:
        return "5h"
    if mins == 10080:
        return "week"
    return f"{mins // 1440}d" if mins % 1440 == 0 else f"{mins // 60}h"


def claude():
    cred = json.load(open(HOME + "/.claude/.credentials.json"))["claudeAiOauth"]
    tier = cred.get("rateLimitTier", "")
    plan = cred.get("subscriptionType", "")
    if "_max_" in tier:
        plan += " " + tier.rsplit("_", 1)[-1]  # default_claude_max_20x -> max 20x
    if cred.get("expiresAt", 0) < time.time() * 1000:
        raise RuntimeError("token expired")
    req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers={
        "Authorization": "Bearer " + cred["accessToken"],
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "glyph-agents",
    })
    u = json.load(urllib.request.urlopen(req, timeout=10))
    limits = []
    for l in u.get("limits") or []:
        if l.get("percent") is None:
            continue
        kind = l.get("kind", "")
        name = {"session": "5h", "weekly_all": "week"}.get(kind)
        if not name:
            model = ((l.get("scope") or {}).get("model") or {}).get("display_name")
            name = (model or kind).lower()
        limits.append({"key": name, "pct": round(l["percent"]), "reset": ms(l.get("resets_at"))})
    if not limits:  # older shape
        for k, name in (("five_hour", "5h"), ("seven_day", "week")):
            v = u.get(k) or {}
            if v.get("utilization") is not None:
                limits.append({"key": name, "pct": round(v["utilization"]), "reset": ms(v.get("resets_at"))})
    return {"plan": plan, "limits": limits}


def codex_bin():
    p = HOME + "/.local/share/mise/installs/codex/latest/bin/codex"  # the mise shim prints banners, skip it
    return p if os.access(p, os.X_OK) else "codex"


def codex():
    p = subprocess.Popen([codex_bin(), "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True)
    timer = threading.Timer(15, p.kill)
    timer.start()
    try:
        def send(m):
            p.stdin.write(json.dumps({"jsonrpc": "2.0", **m}) + "\n")
            p.stdin.flush()

        def reply(i):
            for line in p.stdout:
                m = json.loads(line)
                if m.get("id") == i:
                    if "error" in m:
                        raise RuntimeError(m["error"].get("message", "error"))
                    return m["result"]
            raise RuntimeError("app-server closed")

        send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "glyph-agents", "version": "1"}}})
        reply(1)
        send({"method": "initialized", "params": {}})
        send({"id": 2, "method": "account/rateLimits/read", "params": {}})
        r = reply(2)["rateLimits"]
    finally:
        timer.cancel()
        p.kill()
        p.wait()
    limits = []
    for w in (r.get("primary"), r.get("secondary")):
        if w and w.get("usedPercent") is not None:
            limits.append({"key": window(w.get("windowDurationMins") or 0), "pct": round(w["usedPercent"]),
                           "reset": ms(w.get("resetsAt"))})
    return {"plan": r.get("planType") or "", "limits": limits}


def main():
    try:
        old = {a["id"]: a for a in json.load(open(CACHE))["agents"]}
    except (OSError, ValueError, KeyError):
        old = {}
    now = int(time.time() * 1000)
    out = {}

    def run(aid, fn):
        try:
            out[aid] = {"id": aid, **fn(), "at": now, "stale": False, "error": ""}
        except Exception as e:  # keep the last good numbers
            prev = old.get(aid) or {"id": aid, "plan": "", "limits": [], "at": 0}
            out[aid] = {**prev, "stale": True, "error": str(e)[:80]}

    ts = [threading.Thread(target=run, args=a) for a in (("claude", claude), ("codex", codex))]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    res = {"at": now, "agents": [out["claude"], out["codex"]]}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE + ".tmp", "w") as f:
        json.dump(res, f)
    os.replace(CACHE + ".tmp", CACHE)
    print(json.dumps(res))


main()
