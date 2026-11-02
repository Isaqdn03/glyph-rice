#!/usr/bin/python3 -I
# local: a Govee light on the LAN for services/Govee.qml — the floor lamp (H6076 here) through Govee's LAN API: UDP, no
# cloud, no account. "LAN Control" has to be on for the light in the Govee Home app. Discovery is a multicast scan
# (239.255.255.250:4001); the light answers on 4002, takes commands on 4003 (turn, brightness, colorwc) and tells its
# state on devStatus — polled every POLL s, since the phone and the lamp's own button change it too.
# What the shell wants goes out per field, and only when that field changes here: a lamp switched off from the phone
# stays off until something about it changes in the shell (a colour picked, the night hours ending…). A reload sends
# nothing either — the last wanted state is kept in $XDG_RUNTIME_DIR (gone after a reboot, so a login sends it all).
# Colours come in as screen sRGB and go out through the 2.2 curve, scaled so the brightest channel is full (brightness
# is the level): LEDs are linear, #D71921 straight would show pink. Whites are the lamp's own white LEDs, 2000-9000 K.
#
# stdin, JSON lines:  {"want": {"on": bool, "level": 1-100, "rgb": "RRGGBB" | null, "kelvin": n | null}, "device": id}
# stdout, JSON lines:
#   {"ready": true}
#   {"found": {"ip": ..., "device": ..., "sku": ...}}
#   {"status": {"on": bool, "level": n, "rgb": "RRGGBB" | null, "kelvin": n | null}, "external": ["on", "level", "color"]}
#       external — what changed between two polls that wasn't sent from here: the phone, the button
#   {"lost": true}  stopped answering; scanning again
# stdin also takes {"stream": {"rgb": "RRGGBB", "v": 0-1, "level": 1-100, "z": [["RRGGBB", drive], ...] bottom first}} —
# the screen's colour (services/ambi.py; with z the lamp's zones get a band each, in the lamp's stream mode), sent
# at most every STREAM_GAP s, newest wins, its drive v folded straight into the colour, the lamp's brightness at the
# stream's own level; the memo isn't touched — and {"stream": null}: the wanted colour and level go back on.
import base64, json, os, select, socket, sys, time

SCAN = (os.environ.get("GOVEE_SCAN_HOST") or "239.255.255.250", int(os.environ.get("GOVEE_SCAN_PORT") or 4001))
LISTEN = int(os.environ.get("GOVEE_LISTEN_PORT") or 4002)
CMD = int(os.environ.get("GOVEE_CMD_PORT") or 4003)
POLL = float(os.environ.get("GOVEE_POLL") or 10)  # s between status polls
SETTLE = 0.6                # s after a command before asking what it did
LOST = 3                    # unanswered polls in a row
GAPS = [1, 3, 8, 15, 30]    # s between scans while nothing answers; then 30, or 300 after 5 min with no lamp ever seen
MEMO = os.environ.get("GOVEE_MEMO") or os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "glyph-govee.json")
KMIN, KMAX = 2000, 9000     # the H6076's whites; it ignores a colorwc outside them
STREAM_GAP = 0.05           # s between streamed whole-lamp colours (20 a second); the lamp fades between those itself
ZONE_GAP = 1 / 30           # s between stream-mode frames (zones): they don't fade
KEEP = 1.0                  # s: a still picture's frame goes again, so stream mode never lapses
STREAM_POLL = 30.0          # s between status polls while it streams zones (LedFx doesn't poll at all)
# stream mode is switched on once: at the start, when the lamp turns up again, or when the phone changed it. Re-arming
# it every 10 s blanked the lamp for a moment each time — the flicker "now and then"


def out(**m):
    print(json.dumps(m), flush=True)


def log(*a):
    print("govee:", *a, file=sys.stderr, flush=True)


def led(hexrgb):
    """Screen sRGB → what the LEDs get: each channel through the curve, the brightest one full. None for black."""
    c = [(int(hexrgb[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4)]
    m = max(c)
    return [round(255 * x / m) for x in c] if m > 0 else None


def screen(rgb):
    """The LEDs' colour back as screen sRGB, for prefs to show (at full brightness)."""
    m = max(rgb)
    return "".join(f"{round(255 * (x / m) ** (1 / 2.2)):02X}" for x in rgb) if m > 0 else None


def norm(w):
    """The wanted state as the lamp would report it: on, level, color = ["k", kelvin] | ["rgb", [r, g, b]]."""
    k, rgb = w.get("kelvin"), led(w.get("rgb") or "000000")
    color = ["k", max(KMIN, min(KMAX, int(k)))] if k or not rgb else ["rgb", rgb]
    return {"on": bool(w.get("on")), "level": max(1, min(100, int(w.get("level") or 1))), "color": color}


def parse(d):
    c, k = d.get("color") or {}, d.get("colorTemInKelvin") or 0
    return {"on": bool(d.get("onOff")), "level": int(d.get("brightness") or 0),
            "color": ["k", int(k)] if k else ["rgb", [int(c.get(x) or 0) for x in "rgb"]]}


def shown(s):
    kind, v = s["color"]
    return {"on": s["on"], "level": s["level"], "rgb": screen(v) if kind == "rgb" else None, "kelvin": v if kind == "k" else None}


RAZER_ON, RAZER_OFF = "uwABsQEK", "uwABsQAL"  # BB 00 01 B1 01|00 XOR — the lamp's stream mode on / off


def razer(zones):
    """[[r, g, b] per zone, bottom first] → one stream-mode frame: BB 00 len B0 00 N (R G B)*N XOR, len = 2 + 3N.
    Govee's DreamView/"razer" channel (LedFx, GoveeDreamView): frames land at once, no fade. Not in Govee's LAN docs;
    an H6076 report says it doesn't work — on this one it does (2026-11-01: 8 zones, halves swapping red/blue snapped)."""
    b = [0xBB, 0x00, 2 + 3 * len(zones), 0xB0, 0x00, len(zones)] + [c for z in zones for c in z]
    x = 0
    for v in b:
        x ^= v
    return "razer", {"pt": base64.b64encode(bytes(b + [x])).decode()}


def command(f, w):
    if f == "on":
        return "turn", {"value": 1 if w["on"] else 0}
    if f == "level":
        return "brightness", {"value": w["level"]}
    kind, v = w["color"]
    if kind == "k":
        return "colorwc", {"color": {"r": 0, "g": 0, "b": 0}, "colorTemInKelvin": v}
    return "colorwc", {"color": {"r": v[0], "g": v[1], "b": v[2]}, "colorTemInKelvin": 0}


def load_memo():
    try:
        with open(MEMO) as f:
            m = json.load(f)
        return m if isinstance(m, dict) else {}
    except (OSError, ValueError):
        return {}


def save_memo(m):
    try:
        tmp = MEMO + ".tmp"
        with open(tmp, "w") as f:
            json.dump(m, f)
        os.replace(tmp, MEMO)
    except OSError as e:
        log("memo", e)


def main():
    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    rx.bind(("", LISTEN))
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    fd = sys.stdin.fileno()

    memo = load_memo()   # {"device", "want", "pending"}: what was last wanted from which lamp
    want, hint = None, ""
    dev, have = None, None
    started, scans, scan_at = time.monotonic(), 0, 0.0
    poll_at, asked, misses, fresh = 0.0, False, 0, False
    quiet = {}  # field → until when a change in it is our own command landing, not the phone
    stream, stream_sent, stream_at = None, None, 0.0  # the screen's colour while it streams
    armed = 0.0                                       # when stream mode was last switched on; 0 — it's off
    buf = b""
    out(ready=True)

    def send(cmd, data):
        try:
            tx.sendto(json.dumps({"msg": {"cmd": cmd, "data": data}}).encode(), (dev["ip"], CMD))
        except OSError as e:
            log("send", cmd, e)

    def apply():
        """Send what changed in the wanted state since it was last wanted — and isn't on the lamp already."""
        nonlocal memo, poll_at
        last = memo.get("want") if memo.get("device") == dev["device"] else None
        pending = set(memo.get("pending") or []) if last else set()
        last = last or {}
        todo = []
        if want["on"] != last.get("on") and have["on"] != want["on"]:
            todo.append("on")
        for f in ("color", "level"):
            if want[f] == last.get(f) and f not in pending or stream:
                continue  # while the screen streams, its colour wins; restore() puts the wanted one back
            if want["on"]:
                pending.discard(f)
                if have[f] != want[f]:
                    todo.append(f)
            else:
                pending.add(f)  # a colour or level picked while it's dark lands when it lights up
        memo = {"device": dev["device"], "want": want, "pending": sorted(pending)}
        save_memo(memo)
        for i, f in enumerate(todo):
            if i:
                time.sleep(0.05)
            send(*command(f, want))
        if todo:
            now = time.monotonic()
            for f in todo:
                quiet[f] = now + SETTLE + 0.3
            poll_at = min(poll_at, now + SETTLE)

    def restore():
        """After a stream: the wanted colour and level, whatever the memo says."""
        nonlocal poll_at
        # the colour always: after zones its one reported colour says nothing about the segments
        todo = [f for f in ("color", "level") if want and want["on"] and (f == "color" or have[f] != want[f])]
        for i, f in enumerate(todo):
            if i:
                time.sleep(0.05)
            send(*command(f, want))
            quiet[f] = time.monotonic() + SETTLE + 0.3
        if todo:
            poll_at = min(poll_at, time.monotonic() + SETTLE)

    while True:
        now = time.monotonic()
        wait = max(0.0, min(1.0, (poll_at if dev else scan_at) - now))
        if stream:
            gap = ZONE_GAP if stream[0] == "zones" else STREAM_GAP
            due = stream_at + (gap if stream != stream_sent else KEEP if stream[0] == "zones" else 1e9)
            wait = min(wait, max(0.005, due - now))
        r, _, _ = select.select([fd, rx], [], [], wait)

        if fd in r:
            chunk = os.read(fd, 65536)
            if not chunk:
                return  # the shell is gone
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                    if "stream" in msg:
                        st = msg["stream"]
                        if st:
                            c, k = led(st.get("rgb") or "FFFFFF") or [255, 255, 255], max(0.0, min(1.0, float(st.get("v", 1))))
                            c = [round(x * k) for x in c]
                            if max(c) < 3:  # all zero would be no colour at all; keep a glow
                                c = [round(3 * x / max(1, max(c))) if max(c) else 3 for x in c]
                            stream = ["rgb", c]
                            if st.get("z"):  # a lamp with zones: the screen top to bottom up its height
                                zs = []
                                for zh, zd in st["z"]:
                                    zc = led(zh) or [255, 255, 255]
                                    zk = max(0.0, min(1.0, float(zd)))
                                    zs.append([max(1, round(x * zk)) if x else 0 for x in zc])
                                stream = ["zones", zs]
                            lv = max(1, min(100, int(st.get("level") or (want or {}).get("level") or 100)))
                            if dev and have and have["level"] != lv:
                                send(*command("level", {"level": lv}))  # the stream's own ceiling
                                have["level"] = lv
                                quiet["level"] = time.monotonic() + SETTLE + 0.3
                        elif stream:
                            stream, stream_sent = None, None
                            if armed and dev:
                                send("razer", {"pt": RAZER_OFF})
                                time.sleep(0.05)
                            armed = 0.0
                            if dev and have:
                                restore()
                        continue
                    w = norm(msg["want"])
                except (ValueError, KeyError, TypeError):
                    continue
                hint = msg.get("device") or hint
                if w != want:
                    want = w
                    if dev and have:
                        apply()

        if rx in r:
            try:
                data, addr = rx.recvfrom(4096)
                m = json.loads(data)["msg"]
                cmd, d = m["cmd"], m["data"]
            except (OSError, ValueError, KeyError, TypeError):
                cmd = None
            if cmd == "scan" and not dev and d.get("ip") and d.get("device"):
                # the lamp seen before, or any once nothing's been seen or it hasn't turned up for 2 min
                if not hint or d["device"] == hint or time.monotonic() - started > 120:
                    dev = {"ip": d["ip"], "device": d["device"], "sku": d.get("sku") or ""}
                    out(found=dev)
                    have, fresh, asked, misses, poll_at = None, True, False, 0, 0.0
            elif cmd == "devStatus" and dev and addr[0] == dev["ip"]:
                s = parse(d)
                now = time.monotonic()
                ext = [f for f in s if have and s[f] != have[f] and now > quiet.get(f, 0)]
                if s != have:
                    out(status=shown(s), external=ext)
                if ext and stream:
                    armed = 0.0  # the phone touched it: stream mode may be off — on again with the next frame
                have, asked, misses = s, False, 0
                if fresh:
                    fresh = False
                    if want:
                        apply()

        now = time.monotonic()
        if stream and dev and have and have["on"]:
            zones = stream[0] == "zones"
            new = stream != stream_sent and now - stream_at >= (ZONE_GAP if zones else STREAM_GAP)
            if zones and (new or now - stream_at >= KEEP):
                if not armed:
                    send("razer", {"pt": RAZER_ON})
                    armed = now
                send(*razer(stream[1]))
                have["color"], stream_sent, stream_at = stream, stream, now
            elif not zones and new:
                send(*command("color", {"color": stream}))
                have["color"], stream_sent, stream_at = stream, stream, now
            quiet["color"] = now + SETTLE + 0.3
        if not dev and now >= scan_at:
            try:
                tx.sendto(b'{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}', SCAN)
            except OSError as e:
                log("scan", e)  # no network yet
            gap = GAPS[min(scans, len(GAPS) - 1)]
            if scans >= len(GAPS) and not hint and now - started > 300:
                gap = 300
            scans += 1
            scan_at = now + gap
        elif dev and now >= poll_at:
            if asked:
                misses += 1
            if misses >= LOST:
                log("lost", dev["ip"])
                out(lost=True)
                dev, have, scans, scan_at, armed = None, None, 0, now, 0.0  # found again: stream mode on again
                continue
            send("devStatus", {})
            asked, poll_at = True, now + (STREAM_POLL if stream and stream[0] == "zones" else POLL)


if __name__ == "__main__":
    main()
