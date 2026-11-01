#!/usr/bin/python3 -I
# local: tests for config/quickshell/glyph/services/kraken.py — the Kraken Z's owner (services/Rgb.qml).
#
#   python3 -I -B tests/test_kraken.py        all of them, ~15 s
#
# kraken.py runs as a child with a fake liquidctl (a Kraken Z that records what it's told and can be made to fail),
# fake sensors, short timers and its frame/GIF files in a temp dir — the real cooler and the shell's frame are never
# touched. The one exception reads the real GPU through NVML (skipped without an NVIDIA driver).
# `test_kraken.py run PLAN` is the child side: PLAN (JSON) says how the fake cooler behaves.
import ctypes, importlib.util, json, logging, os, queue, random, subprocess, sys, tempfile, threading, time, types
import unittest

KRAKEN = os.environ.get("KRAKEN_PY") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config",
                                                     "quickshell", "glyph", "services", "kraken.py")  # KRAKEN_PY: another copy
COLORS = ["F2F2F2", "2A2A2A", "8C8C8C", "D71921", "D71921"]


def load():
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("kraken", KRAKEN)
    k = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(k)
    return k


# ---- the child: kraken.main() against a fake cooler ----

def child(plan):
    k = load()
    k.TICK, k.RETRY, k.RESCAN = plan.get("tick", 0.2), 0.3, 0.5
    k.FRAME, k.GIF = os.path.join(plan["tmp"], "frame.png"), os.path.join(plan["tmp"], "kraken.gif")
    stats = {"select": 0}

    def ev(name, **kw):
        print("fake " + json.dumps({"ev": name, **kw}), file=sys.stderr, flush=True)

    class Sensors:  # fixed numbers, or a CPU that climbs a degree a frame
        n = 40

        def read(self):
            if plan.get("climb"):
                Sensors.n += 1
            return {"cpu": Sensors.n, "cpuLoad": 5, "gpu": 50, "gpuLoad": 10, "liquid": 28}

    class Kraken:
        description = "NZXT Kraken Z (Z53)"

        def connect(self):
            ev("connect")

        def initialize(self):
            ev("init")
            if plan.get("warn"):
                logging.getLogger("liquidctl.driver.kraken3").warning("forcing re-initialization despite nzxt_kraken3")
            return [("LED accessory 1", 1, ""), ("LED accessory 2", 1, "")]

        def disconnect(self):
            ev("disconnect")

        def set_color(self, ch, mode, colors):
            ev("color", mode=mode)

        def set_screen(self, ch, mode, value):
            if mode == "gif" and plan.get("gif_fails", 0) > 0:
                plan["gif_fails"] -= 1
                ev("upload", mode=mode, ok=False)
                raise OSError("usb hiccup")
            if mode == "static" and plan.get("wedge", 0) > 0:  # what liquidctl does when the LCD's memory is wedged
                plan["wedge"] -= 1
                logging.getLogger("liquidctl.driver.kraken3").error("Failed to setup bucket for data transfer")
                ev("upload", mode=mode, ok=False)
                return
            ev("upload" if mode in ("static", "gif") else "screen", mode=mode, ok=True)

    fake = types.ModuleType("liquidctl")
    fake.find_liquidctl_devices = lambda: iter([] if plan.get("absent") else [Kraken()])
    sys.modules["liquidctl"] = fake
    k.Sensors = Sensors
    if plan.get("draw_fails"):
        def draw_dial(*a):
            raise RuntimeError("no ink")
        k.draw_dial = draw_dial
    real = k.select.select

    def counted(*a):
        stats["select"] += 1
        return real(*a)

    k.select.select = counted
    try:
        k.main()
    finally:
        print("stats " + json.dumps(stats), file=sys.stderr, flush=True)


class Run:
    """kraken.py as the shell runs it, fed JSON lines; collects its stdout, its log and the fake cooler's events."""

    def __init__(self, tmp, **plan):
        plan["tmp"] = tmp
        self.p = subprocess.Popen([sys.executable, "-I", "-B", __file__, "run", json.dumps(plan)], text=True,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.out, self.log, self.events, self.stats = [], [], [], None
        threading.Thread(target=self._read, args=(self.p.stdout, True), daemon=True).start()
        threading.Thread(target=self._read, args=(self.p.stderr, False), daemon=True).start()

    def _read(self, f, out):
        for line in f:
            line = line.rstrip("\n")
            if out:
                self.out.append(json.loads(line))
            elif line.startswith("fake "):
                self.events.append(json.loads(line[5:]))
            elif line.startswith("stats "):
                self.stats = json.loads(line[6:])
            else:
                self.log.append(line)

    def send(self, **msg):
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()

    def want(self, **kw):
        self.send(**{"fans": "AF0203", "bright": 100, "screen": "dial", "gif": "", "colors": COLORS, **kw})

    def until(self, ok, timeout=4.0):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if ok():
                return True
            time.sleep(0.02)
        return ok()

    def count(self, ev, **kw):
        return sum(1 for e in list(self.events) if e["ev"] == ev and all(e.get(a) == b for a, b in kw.items()))

    def close(self):
        self.p.stdin.close()
        self.p.wait(5)
        self.until(lambda: self.stats is not None, 2)
        return self.stats


def put(path, data):
    with open(path, "wb") as f:
        f.write(data)


def write_gif(path, n=3, size=64, noise=False):
    from PIL import Image
    frames = []
    for i in range(n):
        if noise:
            frames.append(Image.frombytes("RGB", (size, size), random.randbytes(size * size * 3)))
        else:
            frames.append(Image.new("RGB", (size, size), (40 * i % 255, 80, 120)))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=50, loop=0)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="kraken-test-")
        self.dir = self.tmp.name
        self.runs = []

    def tearDown(self):
        for r in self.runs:
            if r.p.poll() is None:
                r.p.kill()
                r.p.wait()
            for f in (r.p.stdin, r.p.stdout, r.p.stderr):
                try:
                    f.close()
                except (OSError, ValueError):
                    pass
        self.tmp.cleanup()

    def run_kraken(self, **plan):
        r = Run(self.dir, **plan)
        self.runs.append(r)
        return r


# ---- fix 2: a GIF's problem never drops the cooler ----

class BadGif(Base):
    def test_broken_file_keeps_the_cooler_and_shows_the_dial(self):
        bad = os.path.join(self.dir, "broken.gif")
        put(bad, b"GIF89a cut short")
        r = self.run_kraken()
        r.want(screen="gif", gif=bad)
        self.assertTrue(r.until(lambda: {"bad": bad} in r.out), r.log)
        self.assertTrue(r.until(lambda: r.count("upload", mode="static", ok=True) >= 1), "the dial didn't take over")
        time.sleep(1.5)  # five RETRY periods: the old code reconnected and re-initialized the Kraken in each
        self.assertEqual(r.count("connect"), 1, r.log)
        self.assertEqual(r.count("upload", mode="gif"), 0)
        self.assertTrue(any("can't play" in l for l in r.log), r.log)
        self.assertEqual(sum(1 for l in r.log if "can't play" in l), 1, "a bad file is tried once, not every loop")

    def test_fixed_file_gets_another_try(self):
        bad = os.path.join(self.dir, "broken.gif")
        put(bad, b"GIF89a cut short")
        r = self.run_kraken()
        r.want(screen="gif", gif=bad)
        self.assertTrue(r.until(lambda: {"bad": bad} in r.out))
        write_gif(bad)  # replaced: new mtime and size
        self.assertTrue(r.until(lambda: r.count("upload", mode="gif", ok=True) == 1), r.log)
        self.assertTrue(r.until(lambda: r.out[-1] == {"bad": ""}), r.out)
        self.assertEqual(r.count("connect"), 1)

    def test_gif_that_fails_to_upload_twice_is_left_alone(self):
        good = os.path.join(self.dir, "good.gif")
        write_gif(good)
        r = self.run_kraken(gif_fails=99)
        r.want(screen="gif", gif=good)
        self.assertTrue(r.until(lambda: {"bad": good} in r.out, 6), r.log)
        self.assertTrue(r.until(lambda: r.count("upload", mode="static", ok=True) >= 1, 3), "the dial didn't take over")
        time.sleep(1.5)
        self.assertEqual(r.count("upload", mode="gif"), 2)
        self.assertEqual(r.count("connect"), 3)  # the first, then one reconnect per failed upload — and no more

    def test_dial_that_can_not_be_drawn_keeps_the_cooler(self):
        r = self.run_kraken(draw_fails=True, climb=True)
        r.want()
        self.assertTrue(r.until(lambda: sum("RuntimeError" in l for l in r.log) >= 3), r.log)
        self.assertEqual(r.count("connect"), 1)
        self.assertEqual(r.count("upload"), 0)

    def test_gif_too_big_for_the_lcd_loses_every_other_frame(self):
        from PIL import Image, ImageSequence
        k = load()
        src, out = os.path.join(self.dir, "noise.gif"), os.path.join(self.dir, "out.gif")
        write_gif(src, n=24, size=320, noise=True)
        k.MAX_GIF = 1_000_000
        k.square_gif(src, out)
        with Image.open(out) as im:
            durations = [fr.info["duration"] for fr in ImageSequence.Iterator(im)]
            size = im.size
        self.assertLessEqual(os.path.getsize(out), k.MAX_GIF)
        self.assertLess(len(durations), 24)
        self.assertEqual(sum(durations), 24 * 50, "thinned, not sped up")
        self.assertEqual(size, (320, 320))

    def test_gif_that_fits_keeps_every_frame(self):
        from PIL import Image
        k = load()
        src, out = os.path.join(self.dir, "small.gif"), os.path.join(self.dir, "out.gif")
        write_gif(src, n=5, size=100)
        k.square_gif(src, out)
        with Image.open(out) as im:
            self.assertEqual(im.n_frames, 5)

    def test_missing_font_draws_the_dial_without_labels(self):
        k = load()
        k.FONT = os.path.join(self.dir, "no-such-font.ttf")
        out = os.path.join(self.dir, "dial.png")
        k.draw_dial({"cpu": 40, "cpuLoad": 5, "gpu": 50, "gpuLoad": 10, "liquid": 28}, COLORS, out)
        self.assertTrue(os.path.getsize(out) > 0)
        self.assertEqual(k.FONT, "")


# ---- fix 3: no busy loop ----

class Sleeps(Base):
    def test_no_kraken_wakes_once_a_second(self):
        r = self.run_kraken(absent=True)
        r.want()
        time.sleep(2)
        stats = r.close()
        self.assertLessEqual(stats["select"], 6, f"{stats['select']} wakeups in 2 s (the old code: ~40)")

    def test_dial_before_its_colours_wakes_once_a_second(self):
        r = self.run_kraken()
        r.send(fans="AF0203", bright=100, screen="dial")  # no colours yet: nothing to draw
        time.sleep(2)
        stats = r.close()
        self.assertLessEqual(stats["select"], 6, f"{stats['select']} wakeups in 2 s")

    def test_dial_still_ticks(self):
        r = self.run_kraken(climb=True)  # a new reading each frame
        r.want()
        time.sleep(1.5)
        self.assertGreaterEqual(r.count("upload", mode="static", ok=True), 4)  # TICK 0.2 s


# ---- fix 4: a transfer liquidctl only logged as failed counts as failed ----

class Wedge(Base):
    def test_wedged_upload_reconnects_and_the_frame_is_not_claimed(self):
        r = self.run_kraken(wedge=1)
        r.want()
        self.assertTrue(r.until(lambda: any("frame" in m for m in r.out)), r.log)
        self.assertEqual(r.count("connect"), 2)
        self.assertEqual(r.count("upload", mode="static", ok=False), 1)
        self.assertTrue(any("Wedged" in l and "Failed to setup bucket" in l for l in r.log), r.log)
        frames = [m for m in r.out if "frame" in m]
        self.assertEqual(frames[0]["frame"], 1, "the wedged upload wasn't counted as a frame")

    def test_liquidctl_warnings_still_reach_the_log(self):
        r = self.run_kraken(warn=True)
        r.want()
        self.assertTrue(r.until(lambda: any("liquidctl: forcing re-initialization" in l for l in r.log)), r.log)


# ---- fix 5: GPU temperature through nvmlDeviceGetTemperatureV ----

class FakeNvml:
    """libnvidia-ml as ctypes would show it; `v` — a driver that has nvmlDeviceGetTemperatureV."""

    def __init__(self, v=True, legacy=0):
        self.legacy, self.calls = legacy, []
        if v:
            self.nvmlDeviceGetTemperatureV = self._v

    def nvmlInit_v2(self):
        return 0

    def nvmlDeviceGetHandleByIndex_v2(self, i, h):
        h._obj.value = 1
        return 0

    def _v(self, h, t):
        self.calls.append("V")
        t = t._obj
        if t.version != (12 | 1 << 24) or t.sensorType != 0:
            return 25  # NVML_ERROR_ARGUMENT_VERSION_MISMATCH
        t.temperature = 61
        return 0

    def nvmlDeviceGetTemperature(self, h, sensor, t):
        self.calls.append("legacy")
        if self.legacy:
            return self.legacy  # CUDA 14 drivers: NVML_ERROR_DEPRECATED
        t._obj.value = 55
        return 0

    def nvmlDeviceGetUtilizationRates(self, h, u):
        u._obj[0] = 30
        return 0


class Gpu(unittest.TestCase):
    def test_uses_V_when_the_old_call_is_gone(self):
        k = load()
        lib = FakeNvml(v=True, legacy=26)
        self.assertEqual(k.Nvml(lib).read(), (61, 30))
        self.assertEqual(lib.calls, ["V"])

    def test_old_driver_without_V_uses_the_old_call(self):
        k = load()
        lib = FakeNvml(v=False)
        self.assertEqual(k.Nvml(lib).read(), (55, 30))

    def test_V_on_this_gpu_matches_the_old_call(self):
        try:
            lib = ctypes.CDLL("libnvidia-ml.so.1")
        except OSError:
            self.skipTest("no NVIDIA driver")
        k = load()
        n = k.Nvml()
        if not n.h or not n.v:
            self.skipTest("no GPU, or a driver older than nvmlDeviceGetTemperatureV")
        t = k.Temp(k.TEMP_V1, 0, -1)
        self.assertEqual(lib.nvmlDeviceGetTemperatureV(n.h, ctypes.byref(t)), 0, "struct version rejected")
        old = ctypes.c_uint()
        self.assertEqual(lib.nvmlDeviceGetTemperature(n.h, 0, ctypes.byref(old)), 0)
        self.assertLessEqual(abs(n.temp() - old.value), 3)
        self.assertTrue(10 < n.temp() < 110, n.temp())


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "run":
        child(json.loads(sys.argv[2]))
    else:
        unittest.main(verbosity=2)
