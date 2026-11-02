#!/usr/bin/python3 -I
# local: services/ambi.py — the frame → colour maths, and the OpenRGB writer against a slow fake server (never the real
# one, never the screen). python3 -I -B tests/test_ambi.py
import importlib.util, os, socket, struct, threading, time, unittest
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.environ.get("AMBI_PY") or os.path.join(HERE, "..", "config", "quickshell", "glyph", "services", "ambi.py")
spec = importlib.util.spec_from_file_location("ambi", PATH)
ambi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ambi)


def frame(rgb, bars=0):
    f = np.zeros((ambi.H, ambi.W, 3), np.uint8)
    f[bars:ambi.H - bars] = rgb
    return f


class Scene(unittest.TestCase):
    def test_a_red_frame_is_red_and_bright(self):
        c, v = ambi.scene(frame((200, 20, 20)))
        self.assertGreater(c[0], 0.99)
        self.assertLess(max(c[1], c[2]), 0.15)
        self.assertGreater(v, 0.9)

    def test_grey_goes_white(self):
        c, _ = ambi.scene(frame((90, 90, 90)))
        self.assertTrue(np.allclose(c, 1, atol=0.01), c)

    def test_letterbox_bars_dont_dim_it(self):
        _, v = ambi.scene(frame((0, 90, 200)))
        _, vb = ambi.scene(frame((0, 90, 200), bars=5))  # 10 of 27 rows black
        self.assertAlmostEqual(v, vb, places=2)

    def test_vivid_beats_a_big_grey_background(self):
        f = frame((60, 60, 60))
        f[10:17, 28:36] = (255, 120, 0)  # a small orange explosion on grey
        c, _ = ambi.scene(f)
        self.assertGreater(c[0], 0.95)
        self.assertLess(c[2], c[1])  # orange-ish, not white

    def test_bands_go_bottom_first(self):
        f = frame((220, 30, 20))
        f[:ambi.H // 2] = (20, 40, 230)  # the top half blue
        rows = np.array_split(np.arange(ambi.H)[::-1], ambi.BANDS)
        bottom, top = ambi.scene(f[rows[0]])[0], ambi.scene(f[rows[-1]])[0]
        self.assertGreater(bottom[0], 0.99)  # red at the bottom
        self.assertGreater(top[2], 0.99)  # blue at the top

    def test_black_is_no_colour(self):
        self.assertEqual(ambi.scene(frame((0, 0, 0)))[0], None)


class FakeOpenRGB:
    """The SDK server, slow on purpose: 60 ms per frame, like SMBus RAM. Records every UPDATELEDS."""

    def __init__(self):
        self.srv = socket.socket()
        self.srv.bind(("127.0.0.1", 0))
        self.srv.listen(1)
        self.port = self.srv.getsockname()[1]
        self.updates = []
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        c, _ = self.srv.accept()

        def take(n):
            b = b""
            while len(b) < n:
                x = c.recv(n - len(b))
                if not x:
                    raise OSError
                b += x
            return b
        try:
            while True:
                magic, dev, pid, size = struct.unpack("<4sIII", take(16))
                body = take(size)
                if pid == 1050:
                    n = struct.unpack("<H", body[4:6])[0]
                    self.updates.append((dev, n, tuple(body[6:9])))
                    time.sleep(0.03)
                elif pid == 0:
                    c.sendall(struct.pack("<4sIII", b"ORGB", 0, 0, 4) + struct.pack("<I", 2))
        except OSError:
            pass


class Case(unittest.TestCase):
    def test_slow_server_never_queues_frames_and_ends_on_the_newest(self):
        fake = FakeOpenRGB()
        ambi.ORGB = ("127.0.0.1", fake.port)
        ambi.led_counts = lambda devs: {d: 8 for d in devs}
        case = ambi.Case()
        case.start()
        for i in range(60):  # 2 s of 30 fps
            case.set([0, 1], (i, 0, 0))
            time.sleep(1 / 30)
        time.sleep(0.5)
        frames = len(fake.updates) // 2
        self.assertLess(frames, 40, "a slow server gets fewer frames, not a backlog")
        self.assertEqual(fake.updates[-1], (1, 8, (59, 0, 0)), "and the last one it gets is the newest")
        self.assertEqual({d for d, _, _ in fake.updates}, {0, 1})


if __name__ == "__main__":
    unittest.main(verbosity=1)
