#!/usr/bin/python3 -I
# local: the screen → the lights, for services/Rgb.qml (prefs → LIGHTS, colour: screen). gpu-screen-recorder captures a
# monitor through KMS (its gsr-kms-server has cap_sys_admin: no compositor copy, so a fullscreen game keeps direct
# scanout), scales it on the GPU and encodes it with NVENC; ffmpeg decodes that tiny video to 64x27 RGB. Measured
# 2026-11-01: 30 fps for ~2.5 % of one core, latency within a frame of a direct grim capture.
# Each frame becomes one colour — the vivid parts weighted up, a grey scene going white — and an intensity: dark scenes
# dim the lights, letterbox bars don't count. Both smoothed (fast up, slower down). The case's OpenRGB devices are
# written here, over the SDK (127.0.0.1:6742), each frame followed by a request the server answers only after the
# frame is applied — so updates never pile up behind slow SMBus RAM. Everything else (keyboard, Kraken fans, the lamp)
# gets the colour from stdout through the shell.
#
# stdin, JSON lines: {"monitor": "DP-2", "case": {"on": bool, "level": 0-100, "devs": [openrgb index, ...]}}
# stdout, JSON lines: {"c": "RRGGBB", "v": drive 0.35-1, a straight LED multiplier,
#                     "z": [["RRGGBB", drive], ...] — BANDS bands of the frame, bottom first} (≤ 30 Hz, on change)
#                    | {"up": monitor} first frame | {"error": text}
import ctypes, json, math, os, re, select, signal, socket, struct, subprocess, sys, threading, time
import numpy as np

W, H = 64, 27
FPS = 30
FLOOR, SOFT = 0.35, 0.6      # drive = FLOOR + (1 - FLOOR) * intensity ** SOFT: a dark scene dims the lights to about a
                             # third, never off; applied once, straight onto the LEDs (no 2.2 on top: that was far too dim)
# adaptive smoothing (One Euro filter, Casiez et al. 2012): heavy while the picture holds — compression noise and two
# similar areas trading places flickered with a plain fast filter — and out of the way when it moves (cuts, flashes).
# Fixed time constants were either sluggish (0.1/0.2 s) or flickery (0.03/0.06 s)
CUT_C, BETA_C = 1.2, 1.5     # colour: Hz at rest, how fast the cut-off rises with the speed of change
CUT_V, BETA_V = 1.5, 2.0     # intensity
ORGB = ("127.0.0.1", 6742)
BANDS = 8                    # horizontal bands, bottom to top, for lights with zones up their height (the H6076 lamp)
LOG = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "glyph-ambi.log")  # gpu-screen-recorder's own words


def out(**m):
    print(json.dumps(m), flush=True)


def log(*a):
    print("ambi:", *a, file=sys.stderr, flush=True)


def scene(px):
    """A frame (H, W, 3) uint8 → (colour at full intensity as 0-1 rgb, intensity 0-1)."""
    a = px.astype(np.float32) / 255
    mx, mn = a.max(2), a.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    w = sat * sat * mx * mx + 0.015 * mx  # vivid and bright counts most; greys only a little
    lit = mx[mx > 0.03]
    if w.sum() < 1e-4 or lit.size == 0:
        return None, 0.0

    def full(c):
        m = float(c.max())
        return c / m if m > 1e-4 else np.ones(3, np.float32)

    vivid = (a * w[..., None]).sum((0, 1)) / w.sum()
    colourful = min(1.0, float((sat * mx).mean()) * 5)
    c = full(full(vivid) * colourful + full(a.mean((0, 1))) * (1 - colourful))
    v = float(np.percentile(mx, 75))  # the brighter part of the frame: bars and shadows don't drag it down
    return c, min(1.0, v * 1.25)


class Euro:
    """One Euro filter over a numpy array, element by element."""

    def __init__(self, cut, beta, dcut=1.0):
        self.cut, self.beta, self.dcut = cut, beta, dcut
        self.x, self.dx = None, None

    @staticmethod
    def alpha(dt, cut):
        return 1 / (1 + 1 / (2 * math.pi * cut * dt))

    def __call__(self, x, dt):
        x = np.asarray(x, np.float64)
        if self.x is None:
            self.x, self.dx = x.copy(), np.zeros_like(x)
            return self.x
        self.dx += self.alpha(dt, self.dcut) * ((x - self.x) / dt - self.dx)
        self.x += self.alpha(dt, self.cut + self.beta * np.abs(self.dx)) * (x - self.x)
        return self.x


def die_with_parent():
    ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG: no orphaned capture if we're killed


def capture(mon):
    gsr = subprocess.Popen(
        ["gpu-screen-recorder", "-w", mon, "-s", "256x108", "-f", str(FPS), "-fm", "cfr", "-c", "mpegts", "-k", "h264",
         "-q", "medium", "-tune", "performance", "-cursor", "no", "-v", "no",
         "-ffmpeg-opts", "pes_payload_size=0;max_delay=0;flush_packets=1", "-ffmpeg-video-opts", "zerolatency=1;delay=0;bf=0",
         "-o", "/dev/stdout"], stdout=subprocess.PIPE, stderr=open(LOG, "wb"), preexec_fn=die_with_parent)
    ff = subprocess.Popen(
        ["ffmpeg", "-loglevel", "error", "-fflags", "nobuffer", "-flags", "low_delay", "-probesize", "32",
         "-analyzeduration", "0", "-threads", "1", "-f", "mpegts", "-i", "-", "-fps_mode", "passthrough",
         "-vf", f"scale={W}:{H}:flags=area", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdin=gsr.stdout, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, preexec_fn=die_with_parent)
    gsr.stdout.close()
    return gsr, ff


def stop(procs):
    for p in procs or ():
        if p.poll() is None:
            p.terminate()
    for p in procs or ():
        try:
            p.wait(2)
        except subprocess.TimeoutExpired:
            p.kill()


def led_counts(devs):
    """LEDs per OpenRGB device, from `openrgb -ld` (client only: --nodetect)."""
    try:
        txt = subprocess.run(["openrgb", "--nodetect", "-ld"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    n = {}
    for block in re.split(r"\n(?=\d+: )", txt):
        m, leds = re.match(r"(\d+): ", block), re.search(r"^\s+LEDs:\s*(.*)$", block, re.M)
        if m and leds and int(m[1]) in devs:
            q = re.findall(r"'[^']*'", leds[1])
            n[int(m[1])] = len(q) or (1 if leds[1].strip() else 0)
    return n


class Case(threading.Thread):
    """The case's OpenRGB devices over the SDK: the newest colour wins, one frame in flight at a time."""

    def __init__(self):
        super().__init__(daemon=True)
        self.cv = threading.Condition()
        self.devs, self.want, self.sent = [], None, None

    def set(self, devs, rgb):
        with self.cv:
            if devs != self.devs:
                self.devs, self.sent = devs, None
            self.want = rgb
            self.cv.notify()

    def run(self):
        sock, counts, devs = None, {}, None
        trips = []
        while True:
            with self.cv:
                while self.want is None or (self.want == self.sent and self.devs == devs):
                    self.cv.wait()
                want, want_devs = self.want, list(self.devs)
            try:
                if sock is None:
                    sock = socket.create_connection(ORGB, timeout=2)
                    name = b"Glyph ambi\0"
                    sock.sendall(struct.pack("<4sIII", b"ORGB", 0, 50, len(name)) + name)  # SET_CLIENT_NAME
                    devs = None
                if want_devs != devs:
                    counts, devs = led_counts(want_devs), want_devs
                pkt = b""
                for d in devs:
                    n = counts.get(d, 0)
                    if n:
                        body = struct.pack("<IH", 4 + 2 + 4 * n, n) + bytes((*want, 0)) * n
                        pkt += struct.pack("<4sIII", b"ORGB", d, 1050, len(body)) + body  # UPDATELEDS
                pkt += struct.pack("<4sIII", b"ORGB", 0, 0, 0)  # REQUEST_CONTROLLER_COUNT: answered after the above
                t0 = time.monotonic()
                sock.sendall(pkt)
                self.reply(sock)
                trips.append(time.monotonic() - t0)
                if len(trips) == 150:  # once per run: how fast the case really takes frames
                    tr = sorted(trips)
                    log(f"case: {len(devs)} devices, round trip p50 {tr[75] * 1000:.0f} ms p90 {tr[135] * 1000:.0f} ms")
                with self.cv:
                    self.sent = want
            except (OSError, struct.error) as e:
                log("openrgb", e)
                try:
                    if sock:
                        sock.close()
                except OSError:
                    pass
                sock = None
                time.sleep(5)

    @staticmethod
    def reply(sock):
        """Read until the controller-count answer (skipping device-list notices)."""
        def take(n):
            b = b""
            while len(b) < n:
                c = sock.recv(n - len(b))
                if not c:
                    raise OSError("openrgb closed the connection")
                b += c
            return b
        while True:
            magic, _, pid, size = struct.unpack("<4sIII", take(16))
            if magic != b"ORGB":
                raise OSError("not an OpenRGB answer")
            take(size)
            if pid == 0:
                return


def main():
    stdin = sys.stdin.fileno()
    cfg = {"monitor": "", "case": {"on": False, "level": 100, "devs": []}}
    case = Case()
    case.start()
    procs, mon, buf, started, up = None, None, b"", 0.0, False
    c_s, v_s, last_t, last_out = None, 0.0, time.monotonic(), None
    zc, zv = [None] * BANDS, [0.0] * BANDS  # each band smoothed like the whole
    fc, fv = Euro(CUT_C, BETA_C), Euro(CUT_V, BETA_V)
    fzc, fzv = [Euro(CUT_C, BETA_C) for _ in range(BANDS)], [Euro(CUT_V, BETA_V) for _ in range(BANDS)]
    rows = np.array_split(np.arange(H)[::-1], BANDS)  # bottom rows first
    frame = W * H * 3
    retry_at, backoff = 0.0, 5  # a capture that keeps failing (monitors off) is retried less and less often, up to 2 min

    while True:
        fds = [stdin] + ([procs[1].stdout] if procs else [])
        r, _, _ = select.select(fds, [], [], 1.0)
        if stdin in r:
            chunk = os.read(stdin, 65536)
            if not chunk:
                stop(procs)
                return
            for line in chunk.split(b"\n"):
                try:
                    cfg.update(json.loads(line))
                except (ValueError, TypeError):
                    pass

        want_mon = cfg.get("monitor") or ""
        if procs and (want_mon != mon or procs[0].poll() is not None or procs[1].poll() is not None):
            if want_mon == mon:
                try:
                    with open(LOG, errors="replace") as f:
                        err = f.read()[-2000:].strip()
                except OSError:
                    err = ""
                if backoff == 5:  # say it once per run of failures
                    log("capture stopped", err[-300:])
                    out(error="capture stopped: " + (err.splitlines()[-1] if err else "gpu-screen-recorder exited"))
                retry_at, backoff = time.monotonic() + backoff, min(120, backoff * 2)
            stop(procs)
            procs, buf, up = None, b"", False
            continue
        if not procs and want_mon and time.monotonic() >= retry_at:
            try:
                procs, mon, started = capture(want_mon), want_mon, time.monotonic()
            except OSError as e:
                out(error=str(e))
                retry_at = time.monotonic() + 30
            continue

        if procs and procs[1].stdout in r:
            chunk = os.read(procs[1].stdout.fileno(), 1 << 16)
            buf += chunk
            if len(buf) < frame:
                continue
            k = len(buf) // frame
            px = np.frombuffer(buf[(k - 1) * frame:k * frame], np.uint8).reshape(H, W, 3)  # the newest whole frame
            buf = buf[k * frame:]
            if not up:
                up = True
                out(up=mon)
                backoff = 5
                log("up", mon, f"after {time.monotonic() - started:.1f} s")

            now = time.monotonic()
            dt, last_t = max(0.005, min(0.2, now - last_t)), now
            c, v = scene(px)
            if c is not None:
                c_s = fc(c, dt)
            v_s = float(fv([v], dt)[0])
            if c_s is None:
                continue
            hexc = "".join(f"{round(255 * float(x)):02X}" for x in np.clip(c_s, 0, 1))
            drive = FLOOR + (1 - FLOOR) * max(0.0, v_s) ** SOFT
            vr = round(drive, 2)
            z = []
            for i, rs in enumerate(rows):
                bc, bv = scene(px[rs])
                if bc is not None:
                    zc[i] = fzc[i](bc, dt)
                zv[i] = float(fzv[i]([bv], dt)[0])
                col = zc[i] if zc[i] is not None else c_s
                z.append(["".join(f"{round(255 * float(x)):02X}" for x in np.clip(col, 0, 1)),
                          round(FLOOR + (1 - FLOOR) * max(0.0, zv[i]) ** SOFT, 2)])
            if (hexc, vr, z) != last_out:
                last_out = (hexc, vr, z)
                out(c=hexc, v=vr, z=z)
            cs = cfg.get("case") or {}
            if cs.get("on") and cs.get("devs"):
                g = (max(0, min(100, cs.get("level", 100))) / 100) ** 2.2 * drive  # Rgb.qml's level curve × the scene
                case.set(sorted(cs["devs"]), tuple(round(255 * float(x) ** 2.2 * g) for x in np.clip(c_s, 0, 1)))


if __name__ == "__main__":
    main()
