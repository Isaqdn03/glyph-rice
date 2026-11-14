#!/usr/bin/python3 -I
# local: services/keyboard.py against a fake VIA keyboard on a socketpair (KBD_FD) — the real keyboard is never touched.
# python3 -I -B tests/test_keyboard.py
import json, os, socket, subprocess, sys, threading, time, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
KBD = os.environ.get("KEYBOARD_PY") or os.path.join(HERE, "..", "config", "quickshell", "glyph", "services", "keyboard.py")


class Fake:
    """QMK's VIA rgb_matrix channel: answers version and get, keeps what set sets, writes down every set."""

    def __init__(self, state=None):
        self.state = state or {1: [200], 2: [5], 4: [10, 20]}  # brightness, effect (a rainbow), colour
        self.sets = []
        self.ours, self.theirs = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while True:
            try:
                m = self.ours.recv(64)
            except OSError:
                return
            if not m:
                return
            assert m[0] == 0 and len(m) == 33, m  # report id 0 + 32 bytes
            b = m[1:]
            r = bytearray(b)
            if b[0] == 0x01:
                r[1:3] = bytes([0, 12])
            elif b[0] == 0x08 and b[1] == 3:
                v = self.state[b[2]]
                r[3:3 + len(v)] = bytes(v)
            elif b[0] == 0x07 and b[1] == 3:
                v = list(b[3:5]) if b[2] == 4 else [b[3]]
                self.state[b[2]] = v
                self.sets.append((b[2], v))
            else:
                r[0] = 0xFF
            self.ours.send(bytes(r))


class Helper:
    def __init__(self, fake):
        env = dict(os.environ, KBD_FD=str(fake.theirs.fileno()))
        self.p = subprocess.Popen([sys.executable, "-I", KBD], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, env=env, text=True, pass_fds=(fake.theirs.fileno(),))
        self.out, self.log = [], []
        threading.Thread(target=lambda: [self.out.append(json.loads(l)) for l in self.p.stdout], daemon=True).start()
        threading.Thread(target=lambda: [self.log.append(l.rstrip()) for l in self.p.stderr], daemon=True).start()

    def want(self, **w):
        self.p.stdin.write(json.dumps({"on": True, "level": 100, "rgb": "D71921", **w}) + "\n")
        self.p.stdin.flush()

    def until(self, ok, timeout=4.0):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if ok():
                return True
            time.sleep(0.05)
        return False

    def close(self):
        self.p.stdin.close()
        self.p.wait(3)


class Keyboard(unittest.TestCase):
    def setUp(self):
        self.fake = Fake()
        self.helpers = []

    def tearDown(self):
        for h in self.helpers:
            if h.p.poll() is None:
                h.p.kill()
                h.p.wait()

    def start(self):
        h = Helper(self.fake)
        self.helpers.append(h)
        h.want()
        self.assertTrue(h.until(lambda: any(m.get("found") for m in h.out)), h.log)
        time.sleep(0.3)
        return h

    def test_solid_red_through_the_curve(self):
        self.start()
        # #D71921 on LEDs: hue all the way round, nearly full saturation; colour and level before the effect
        self.assertEqual(self.fake.sets, [(4, [255, 253]), (1, [255]), (2, [1])])

    def test_reload_with_nothing_changed_writes_nothing(self):
        h = self.start()
        h.close()
        self.fake.sets.clear()
        self.start()
        self.assertEqual(self.fake.sets, [])

    def test_dark_waits_with_the_colour(self):
        h = self.start()
        self.fake.sets.clear()
        h.want(on=False)
        self.assertTrue(h.until(lambda: self.fake.sets == [(2, [0])]), self.fake.sets)
        h.want(on=False, rgb="22C3FF")
        time.sleep(0.3)
        self.assertEqual(self.fake.sets, [(2, [0])], "nothing but the effect while it's dark")
        h.want(on=True, rgb="22C3FF")
        self.assertTrue(h.until(lambda: len(self.fake.sets) == 3), self.fake.sets)
        self.assertEqual([f for f, _ in self.fake.sets[1:]], [4, 2])  # the new colour, then lit; the level never changed

    def test_level_follows_the_curve(self):
        h = self.start()
        self.fake.sets.clear()
        h.want(level=50)
        self.assertTrue(h.until(lambda: self.fake.sets == [(1, [55])]), self.fake.sets)
        h.want(level=1)
        self.assertTrue(h.until(lambda: self.fake.sets[-1:] == [(1, [1])]), self.fake.sets)


if __name__ == "__main__":
    unittest.main(verbosity=1)
