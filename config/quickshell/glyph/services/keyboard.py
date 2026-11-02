#!/usr/bin/python3 -I
# local: the NuPhy Halo75 V2's backlight for services/Rgb.qml — it follows the case lights. VIA over QMK's raw HID
# (usage page 0xFF60), so wired only: the 2.4 GHz dongle doesn't carry it. Access: ~/dev/glyph-desktop-install/keyboard.sh
# (uaccess on that one interface). Everything goes through VIA's rgb_matrix channel with QMK's *_noeeprom setters
# (nuphy-src/qmk_firmware quantum/via.c): RAM only, no flash wear, and never id_custom_save — a power cycle brings back
# the keyboard's own saved look. Side lights are NuPhy's own (side.c), not VIA's, and are left alone.
# A solid colour: screen sRGB through the 2.2 curve (LEDs are linear), as QMK's hue/sat; the level through the same
# curve as the brightness. Dark = the "All Off" effect. On (re)connect it reads what the keyboard shows and writes only
# what differs, so a reload with nothing changed writes nothing.
#
# stdin, JSON lines:  {"on": bool, "level": 0-100, "rgb": "RRGGBB"}
# stdout, JSON lines: {"found": true, "via": protocol} | {"lost": true} | {"denied": true}  (no access: run keyboard.sh)
import glob, json, os, select, sys, time

VID, PID = "19F5", "32F5"
LOOK = 3                      # s between looks for the keyboard while it isn't there (or isn't ours)
CH = 3                        # id_qmk_rgb_matrix_channel
BRIGHT, EFFECT, COLOR = 1, 2, 4
OFF, SOLID = 0, 1             # VIA's effect list: All Off, Solid Color
GET, SET, VERSION = 0x08, 0x07, 0x01


def out(**m):
    print(json.dumps(m), flush=True)


def log(*a):
    print("keyboard:", *a, file=sys.stderr, flush=True)


def find():
    """The hidraw node of the keyboard's VIA interface, or None."""
    for d in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(d + "/device/uevent") as f:
                if f"HID_ID=0003:0000{VID}:0000{PID}" not in f.read().upper():
                    continue
            with open(d + "/device/report_descriptor", "rb") as f:
                if b"\x06\x60\xff" not in f.read():
                    continue
        except OSError:
            continue
        return "/dev/" + os.path.basename(d)
    return None


def hue_sat(hexrgb):
    """Screen sRGB → QMK hue and saturation (0-255) of what the LEDs should show."""
    c = [(int(hexrgb[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4)]
    hi, lo = max(c), min(c)
    if hi <= 0:
        return 0, 0
    d = hi - lo
    if d == 0:
        h = 0.0
    elif hi == c[0]:
        h = ((c[1] - c[2]) / d) % 6
    elif hi == c[1]:
        h = (c[2] - c[0]) / d + 2
    else:
        h = (c[0] - c[1]) / d + 4
    return round(h * 255 / 6) % 256, round(255 * d / hi)


def target(w):
    level = max(0, min(100, int(w.get("level") or 0)))
    v = round(255 * (level / 100) ** 2.2)
    v = max(1, v) if level else 0
    lit = bool(w.get("on")) and v > 0
    return {"effect": SOLID if lit else OFF, "color": list(hue_sat(w.get("rgb") or "FFFFFF")), "bright": v}


class Kbd:
    def __init__(self, fd):
        self.fd = fd

    def ask(self, *b):
        # hidraw hands every answer to every open handle: what's waiting is someone else's (VIA in a browser, a probe)
        while select.select([self.fd], [], [], 0)[0]:
            os.read(self.fd, 64)
        os.write(self.fd, b"\x00" + bytes(b) + bytes(32 - len(b)))  # report id 0: VIA's report has none
        end = time.monotonic() + 0.5
        while True:
            left = end - time.monotonic()
            if left <= 0 or not select.select([self.fd], [], [], left)[0]:
                raise TimeoutError("no answer")
            r = os.read(self.fd, 64)
            if r and r[0] == 0xFF:
                raise ValueError(f"not handled: {bytes(b[:3]).hex()}")
            if r and r[0] == b[0] and (b[0] == VERSION or r[1:3] == bytes(b[1:3])):
                return r

    def state(self):
        e = self.ask(GET, CH, EFFECT)[3]
        c = self.ask(GET, CH, COLOR)
        return {"effect": e, "color": [c[3], c[4]], "bright": self.ask(GET, CH, BRIGHT)[3]}

    def put(self, f, v):
        if f == "color":
            self.ask(SET, CH, COLOR, v[0], v[1])
        elif f == "bright":
            self.ask(SET, CH, BRIGHT, v)
        else:
            self.ask(SET, CH, EFFECT, v)


def main():
    stdin = sys.stdin.fileno()
    test_fd = os.environ.get("KBD_FD")  # tests: a fake keyboard on an inherited socket
    kbd, path, have, want, denied = None, None, None, None, False
    look_at, buf = 0.0, b""
    out(ready=True)

    def apply():
        """Write what the keyboard shows differently from what's wanted: colour and brightness before the effect."""
        nonlocal have
        if not kbd or not want:
            return
        t = target(want)
        for f in ("color", "bright", "effect"):
            if t["effect"] == OFF and f != "effect":
                continue  # dark: the colour and level wait for it to light
            if have.get(f) != t[f]:
                kbd.put(f, t[f])
                have[f] = t[f]

    def drop(why):
        nonlocal kbd, path, have
        if kbd and not test_fd:
            try:
                os.close(kbd.fd)
            except OSError:
                pass
        if kbd:
            log("lost", why)
            out(lost=True)
        kbd, path, have = None, None, None

    while True:
        r, _, _ = select.select([stdin], [], [], 1.0)
        if r:
            chunk = os.read(stdin, 65536)
            if not chunk:
                return  # the shell is gone
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    w = json.loads(line)
                    target(w)
                except (ValueError, TypeError, AttributeError):
                    continue
                want = w
                try:
                    apply()
                except (OSError, TimeoutError, ValueError) as e:
                    drop(e)

        now = time.monotonic()
        if now < look_at:
            continue
        look_at = now + LOOK
        if kbd:
            if not test_fd and not os.path.exists(path):
                drop("unplugged")
            continue
        p = "fd" if test_fd else find()
        if not p:
            continue
        try:
            fd = int(test_fd) if test_fd else os.open(p, os.O_RDWR)
        except PermissionError:
            if not denied:
                log("no access to", p, "- run ~/dev/glyph-desktop-install/keyboard.sh")
                out(denied=True)
                denied = True
            continue
        except OSError as e:
            log("open", p, e)
            continue
        denied = False
        k = Kbd(fd)
        try:
            v = k.ask(VERSION)
            st = k.state()
        except (OSError, TimeoutError, ValueError) as e:
            log("not answering on", p, "-", e)
            if not test_fd:
                os.close(fd)
            continue
        kbd, path, have = k, p, st
        out(found=True, via=v[1] << 8 | v[2])
        try:
            apply()
        except (OSError, TimeoutError, ValueError) as e:
            drop(e)


if __name__ == "__main__":
    main()
