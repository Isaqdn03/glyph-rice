#!/usr/bin/python3 -I
# local: the NZXT Kraken Z for services/Rgb.qml. One process owns the cooler through liquidctl's driver, kept open so
# nothing fights over it: the Aer fans' colour, the LCD's brightness, and what the LCD shows — Glyph's dial (CPU and GPU
# temperature as 5x7 dots, their load as the ring's two halves, coolant under), a GIF, or NZXT's own liquid screen.
# The dial is redrawn every TICK s while the screen is lit and re-sent only when something on it changed. The Kraken's
# display memory is volatile (a power cycle brings the stock screen back), so uploads don't wear anything; OpenKraken
# runs the same full upload per frame on this firmware (5.11) for hours.
#
# stdin, JSON lines from Rgb.qml — the wanted state, whole or in part:
#   {"fans": "RRGGBB", "bright": 0-100, "screen": "dial"|"gif"|"liquid", "gif": path, "colors": [fg, dim, grey, head, red]}
#   {"init": true}  after sleep: initialize again and send everything again
# stdout, JSON lines:
#   {"hello": true, "fans": n}  connected; n — LED accessories on the external channel
#   {"frame": n, "cpu": °C, "cpuLoad": %, "gpu": °C, "gpuLoad": %, "liquid": °C}  a new dial is on the screen (FRAME)
#
#   kraken.py dial OUT.png CPU CPULOAD GPU GPULOAD LIQUID FG DIM GREY HEAD RED   draw one dial and exit ("-" — no reading)
import ctypes, glob, json, math, os, select, subprocess, sys, time
from PIL import Image, ImageDraw, ImageFont, ImageSequence

TICK = 3                # s between dial frames
SIZE, SS = 320, 4       # panel px; drawn 4x and scaled down so the dots come out round
RUN = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
FRAME = os.path.join(RUN, "glyph-kraken.png")   # tmpfs: a frame every few seconds shouldn't hit the disk
GIF = os.path.join(RUN, "glyph-kraken.gif")
HOT = {"cpu": 90, "gpu": 85}                    # °C: the number goes red, like Glyph's meters past 80 %

GLYPHS = {
    "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def log(*a):
    print("kraken:", *a, file=sys.stderr, flush=True)


# ---- the dial ----

def font_path():
    try:
        return subprocess.run(["fc-match", "-f", "%{file}", "Space Mono:style=Regular"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


FONT = font_path()


def draw_dial(v, colors, out):
    """v: cpu, cpuLoad, gpu, gpuLoad, liquid (None — no reading). colors: fg, dim, grey, head, red as RRGGBB."""
    fg, dim, grey, head, red = (rgb(c) for c in colors)
    s = SIZE * SS
    img = Image.new("RGB", (s, s), (0, 0, 0))
    d = ImageDraw.Draw(img)

    def dot(cx, cy, diam, col):
        r = diam * SS / 2
        d.ellipse((cx * SS - r, cy * SS - r, cx * SS + r, cy * SS + r), fill=col)

    def label(text, cx, y, px, col):
        if not FONT:
            return
        font = ImageFont.truetype(FONT, px * SS)
        track = px * 0.14 * SS * 1.6
        widths = [d.textlength(ch, font=font) for ch in text]
        x = cx * SS - (sum(widths) + track * (len(text) - 1)) / 2
        for ch, cw in zip(text, widths):
            d.text((x, y * SS), ch, font=font, fill=col)
            x += cw + track

    # ring: two halves rising from the bottom — CPU load on the left, GPU on the right. A gap at top and bottom
    # splits them; the head of each is a size up in the lights' colour
    half = 22
    for side, load in ((-1, v["cpuLoad"]), (1, v["gpuLoad"])):
        lit = 0 if load is None else max(1, round(half * load / 100))
        for i in range(half):
            a = math.pi / 2 - side * (i + 1.5) / (half + 2) * math.pi   # angle from 3 o'clock, y down
            x, y = SIZE / 2 + 140 * math.cos(a), SIZE / 2 + 140 * math.sin(a)
            if i == lit - 1:
                dot(x, y, 12, head)
            else:
                dot(x, y, 7, fg if i < lit else dim)

    # two numbers side by side, a label over each and the load under it
    p, g = 6, 3
    gw, sp = 5 * p + 4 * g, 1.9 * p
    nw = 2 * gw + sp
    top = 128
    for cx, key in ((SIZE / 2 - 66, "cpu"), (SIZE / 2 + 66, "gpu")):
        t = v[key]
        text = "--" if t is None else f"{max(0, min(99, round(t))):02d}"
        col = red if t is not None and t >= HOT[key] else fg
        x0 = cx - nw / 2
        for k, ch in enumerate(text):
            for r, row in enumerate(GLYPHS[ch]):
                for c, bit in enumerate(row):
                    if bit == "1":
                        dot(x0 + k * (gw + sp) + c * (p + g) + p / 2, top + r * (p + g) + p / 2, p, col)
        label(key.upper(), cx, top - 26, 12, grey)
        load = v[key + "Load"]
        label("--" if load is None else f"{round(load)}%", cx, top + 7 * p + 6 * g + 12, 12, grey)
    # coolant, small, under both
    if v["liquid"] is not None:
        label(f"LIQUID {round(v['liquid'])}°", SIZE / 2, 238, 10, grey)

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    tmp = out + ".tmp.png"
    img.save(tmp)
    os.replace(tmp, out)


def square_gif(src, out):
    """Crop a GIF to its centre square at 320 px, frames on black — liquidctl would stretch anything not square."""
    im = Image.open(src)
    frames, durations = [], []
    for i, fr in enumerate(ImageSequence.Iterator(im)):
        if i >= 400:
            break
        f = fr.convert("RGBA")
        w, h = f.size
        m = min(w, h)
        f = f.crop(((w - m) // 2, (h - m) // 2, (w - m) // 2 + m, (h - m) // 2 + m)).resize((SIZE, SIZE), Image.LANCZOS)
        bg = Image.new("RGBA", f.size, (0, 0, 0, 255))
        frames.append(Image.alpha_composite(bg, f).convert("RGB"))
        durations.append(fr.info.get("duration", im.info.get("duration", 80)) or 80)
    if not frames:
        raise ValueError("no frames")
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=durations, loop=0, disposal=2)


# ---- sensors ----

def hwmon(name, label=None):
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            if open(h + "/name").read().strip() != name:
                continue
        except OSError:
            continue
        if not label:
            return h + "/temp1_input"
        for lf in glob.glob(h + "/temp*_label"):
            try:
                if open(lf).read().strip() == label:
                    return lf.replace("_label", "_input")
            except OSError:
                pass
    return None


def read_temp(path):
    try:
        return int(open(path).read()) / 1000 if path else None
    except (OSError, ValueError):
        return None


class Nvml:
    """GPU temperature and load straight from libnvidia-ml — no nvidia-smi every few seconds."""

    def __init__(self):
        self.h = None
        try:
            lib = ctypes.CDLL("libnvidia-ml.so.1")
            if lib.nvmlInit_v2() != 0:
                return
            h = ctypes.c_void_p()
            if lib.nvmlDeviceGetHandleByIndex_v2(0, ctypes.byref(h)) != 0:
                return
            self.lib, self.h = lib, h
        except (OSError, AttributeError):
            pass

    def read(self):
        if not self.h:
            return None, None
        t, u = ctypes.c_uint(), (ctypes.c_uint * 2)()
        temp = t.value if self.lib.nvmlDeviceGetTemperature(self.h, 0, ctypes.byref(t)) == 0 else None
        load = u[0] if self.lib.nvmlDeviceGetUtilizationRates(self.h, ctypes.byref(u)) == 0 else None
        return temp, load


class Sensors:
    def __init__(self):
        self.cpu = hwmon("coretemp", "Package id 0") or hwmon("k10temp", "Tctl") or hwmon("zenpower", "Tdie")
        self.liquid = hwmon("z53")
        self.gpu = Nvml()
        self.stat = None
        self.v = {}

    def cpu_load(self):
        try:
            f = [int(x) for x in open("/proc/stat").readline().split()[1:9]]
        except (OSError, ValueError):
            return None
        idle, total = f[3] + f[4], sum(f)
        prev, self.stat = self.stat, (idle, total)
        if not prev or total == prev[1]:
            return None
        return 100 * (1 - (idle - prev[0]) / (total - prev[1]))

    def read(self):
        gt, gl = self.gpu.read()
        now = {"cpu": read_temp(self.cpu), "cpuLoad": self.cpu_load(), "gpu": gt, "gpuLoad": gl,
               "liquid": read_temp(self.liquid)}
        # smoothed over ~6 s: the numbers settle instead of jumping every frame
        for k, x in now.items():
            old = self.v.get(k)
            self.v[k] = x if x is None or old is None else old + 0.5 * (x - old)
        return dict(self.v)


# ---- the cooler ----

def connect():
    from liquidctl import find_liquidctl_devices
    for dev in find_liquidctl_devices():
        if "Kraken Z" in dev.description:
            dev.connect()
            status = dev.initialize()
            return dev, sum(1 for k, *_ in status if str(k).startswith("LED accessory"))
    return None, 0


def main():
    want = {"fans": None, "bright": None, "screen": None, "gif": "", "colors": None}
    have = {}
    dev, fans, retry, frame_at, frames = None, 0, 0, 0, 0
    sensors = Sensors()
    buf = b""
    fd = sys.stdin.fileno()

    while True:
        now = time.monotonic()
        wait = 1.0
        if want["screen"] == "dial" and (want["bright"] or 0) > 0:
            wait = min(wait, max(0.05, frame_at - now))
        r, _, _ = select.select([fd], [], [], wait)
        if r:
            chunk = os.read(fd, 65536)
            if not chunk:
                return  # the shell is gone
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("init") and dev:
                    try:
                        dev.disconnect()
                    except Exception:
                        pass
                    dev, retry = None, 0
                for k in want:
                    if k in msg:
                        want[k] = msg[k]

        now = time.monotonic()
        try:
            if not dev:
                if now < retry:
                    continue
                dev, fans = connect()
                have.clear()
                if not dev:
                    retry = now + 30
                    continue
                print(json.dumps({"hello": True, "fans": fans}), flush=True)

            if fans and want["fans"] and have.get("fans") != want["fans"]:
                c = want["fans"]
                dev.set_color("external", "off" if c == "000000" else "fixed", [] if c == "000000" else [rgb(c)])
                have["fans"] = c
            if want["bright"] is not None and have.get("bright") != want["bright"]:
                dev.set_screen("lcd", "brightness", int(want["bright"]))
                have["bright"] = want["bright"]

            mode = want["screen"]
            if mode == "liquid" and have.get("screen") != "liquid":
                dev.set_screen("lcd", "liquid", None)
                have["screen"] = "liquid"
            elif mode == "gif" and want["gif"] and have.get("screen") != ("gif", want["gif"]):
                have["screen"] = ("gif", want["gif"])  # a broken file isn't retried every second
                square_gif(want["gif"], GIF)
                dev.set_screen("lcd", "gif", GIF)
            elif mode == "dial" and want["colors"] and (want["bright"] or 0) > 0 and now >= frame_at:
                frame_at = now + TICK
                v = sensors.read()
                key = ("dial", tuple(want["colors"])) + tuple(None if x is None else round(x) for x in v.values())
                if have.get("screen") != key:
                    draw_dial(v, want["colors"], FRAME)
                    dev.set_screen("lcd", "static", FRAME)
                    have["screen"] = key
                    frames += 1
                    print(json.dumps({"frame": frames, **{k: None if x is None else round(x) for k, x in v.items()}}), flush=True)
        except Exception as e:  # unplugged, asleep, a USB hiccup: drop it and connect again
            log(type(e).__name__, e)
            try:
                if dev:
                    dev.disconnect()
            except Exception:
                pass
            dev, retry = None, time.monotonic() + 5


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "dial":
        a = sys.argv[2:]
        num = lambda x: None if x == "-" else float(x)
        draw_dial({"cpu": num(a[1]), "cpuLoad": num(a[2]), "gpu": num(a[3]), "gpuLoad": num(a[4]), "liquid": num(a[5])},
                  a[6:11], a[0])
    else:
        main()
