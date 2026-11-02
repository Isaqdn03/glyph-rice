#!/usr/bin/python3 -I
# local: services/govee.py against a fake Govee lamp on 127.0.0.1 (its own ports, so the real lamp and the shell's helper
# are never touched). python3 -I -B tests/test_govee.py
import json, os, socket, subprocess, sys, tempfile, threading, time, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GOVEE = os.environ.get("GOVEE_PY") or os.path.join(HERE, "..", "config", "quickshell", "glyph", "services", "govee.py")
SCAN, LISTEN, CMD = 24001, 24002, 24003


class Fake:
    """The lamp: answers scans and devStatus, takes turn / brightness / colorwc, remembers every command."""

    def __init__(self):
        self.state = {"onOff": 1, "brightness": 25, "color": {"r": 0, "g": 0, "b": 0}, "colorTemInKelvin": 2700}
        self.cmds, self.mute, self.stop = [], False, False
        self.socks = []
        for port in (SCAN, CMD):
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", port))
            s.settimeout(0.1)
            self.socks.append(s)
            threading.Thread(target=self.serve, args=(s,), daemon=True).start()

    def reply(self, s, cmd, data):
        s.sendto(json.dumps({"msg": {"cmd": cmd, "data": data}}).encode(), ("127.0.0.1", LISTEN))

    def serve(self, s):
        while not self.stop:
            try:
                raw, _ = s.recvfrom(4096)
            except (socket.timeout, OSError):
                continue
            m = json.loads(raw)["msg"]
            if self.mute:
                continue
            cmd, d = m["cmd"], m["data"]
            if cmd == "scan":
                self.reply(s, "scan", {"ip": "127.0.0.1", "device": "AA:BB", "sku": "H6076"})
            elif cmd == "devStatus":
                self.reply(s, "devStatus", dict(self.state))
            else:
                self.cmds.append((cmd, d))
                if cmd == "turn":
                    self.state["onOff"] = d["value"]
                elif cmd == "brightness":
                    self.state["brightness"] = d["value"]
                elif cmd == "colorwc":
                    self.state["color"], self.state["colorTemInKelvin"] = d["color"], d["colorTemInKelvin"]

    def close(self):
        self.stop = True
        time.sleep(0.15)
        for s in self.socks:
            s.close()


class Helper:
    def __init__(self, memo):
        env = dict(os.environ, GOVEE_SCAN_HOST="127.0.0.1", GOVEE_SCAN_PORT=str(SCAN), GOVEE_LISTEN_PORT=str(LISTEN),
                   GOVEE_CMD_PORT=str(CMD), GOVEE_POLL="0.3", GOVEE_MEMO=memo)
        self.p = subprocess.Popen([sys.executable, "-I", GOVEE], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, env=env, text=True)
        self.out, self.log = [], []
        threading.Thread(target=self.read, args=(self.p.stdout, self.out, True), daemon=True).start()
        threading.Thread(target=self.read, args=(self.p.stderr, self.log, False), daemon=True).start()

    def read(self, f, into, js):
        for line in f:
            into.append(json.loads(line) if js else line.rstrip())

    def want(self, **w):
        self.p.stdin.write(json.dumps({"want": {"on": True, "level": 60, "rgb": None, "kelvin": 2700, **w}, "device": ""}) + "\n")
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


class Govee(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="govee-test-")
        self.memo = os.path.join(self.tmp.name, "memo.json")
        self.fake = Fake()
        self.helpers = []

    def tearDown(self):
        for h in self.helpers:
            if h.p.poll() is None:
                h.p.kill()
                h.p.wait()
        self.fake.close()
        self.tmp.cleanup()

    def start(self):
        h = Helper(self.memo)
        self.helpers.append(h)
        self.assertTrue(h.until(lambda: any("ready" in m for m in h.out)), h.log)
        return h

    def settle(self, h, n=None):
        """Wait until the helper's seen the lamp and a couple of polls went by."""
        self.assertTrue(h.until(lambda: any("status" in m for m in h.out)), (h.out, h.log))
        time.sleep(0.8)

    def test_first_start_sends_only_what_differs(self):
        h = self.start()
        h.want(rgb="D71921", kelvin=None)
        self.assertTrue(h.until(lambda: any("found" in m for m in h.out)), h.log)
        self.settle(h)
        # already on: no turn; the colour through the curve, the brightest channel full
        self.assertEqual(self.fake.cmds, [("colorwc", {"color": {"r": 255, "g": 2, "b": 4}, "colorTemInKelvin": 0}),
                                          ("brightness", {"value": 60})])
        last = [m for m in h.out if "status" in m][-1]
        self.assertEqual(last["status"]["level"], 60)
        self.assertFalse(any(m.get("external") for m in h.out), h.out)

    def test_restart_with_the_same_want_sends_nothing(self):
        h = self.start()
        h.want()
        self.settle(h)
        self.assertEqual(self.fake.cmds, [("brightness", {"value": 60})])
        h.close()
        self.fake.cmds.clear()
        h = self.start()
        h.want()
        self.settle(h)
        self.assertEqual(self.fake.cmds, [])

    def test_phone_turns_it_off_and_it_stays_off(self):
        h = self.start()
        h.want()
        self.settle(h)
        time.sleep(0.6)
        self.fake.state["onOff"] = 0  # the phone
        self.assertTrue(h.until(lambda: any(m.get("external") and not m["status"]["on"] for m in h.out)), h.out)
        self.fake.cmds.clear()
        h.want()  # the same want again (a reload, the accent unchanged): nothing
        h.want(level=61)  # only the level changed: the lamp isn't turned back on for it
        time.sleep(0.8)
        self.assertEqual(self.fake.cmds, [("brightness", {"value": 61})])

    def test_phone_dims_it_while_a_colour_goes_out(self):
        # 2026-11-01: one window after any command hid the phone's change to another field, and prefs never saw it
        h = self.start()
        h.want()
        self.settle(h)
        time.sleep(0.6)  # past the level's own window from the setup
        h.want(rgb="22C3FF", kelvin=None)
        self.fake.state["brightness"] = 30  # the phone, at the same moment
        self.assertTrue(h.until(lambda: any("level" in (m.get("external") or []) for m in h.out)), h.out)
        ext = [m["external"] for m in h.out if m.get("external")]
        self.assertTrue(all("color" not in e for e in ext), ext)

    def test_colour_picked_while_dark_lands_when_it_lights(self):
        h = self.start()
        h.want()
        self.settle(h)
        h.want(on=False)
        self.assertTrue(h.until(lambda: ("turn", {"value": 0}) in self.fake.cmds))
        self.fake.cmds.clear()
        h.want(on=False, kelvin=6500)
        time.sleep(0.6)
        self.assertEqual(self.fake.cmds, [], "nothing sent to a dark lamp")
        h.want(on=True, kelvin=6500)
        self.assertTrue(h.until(lambda: len(self.fake.cmds) >= 2))
        self.assertEqual(self.fake.cmds[:2], [("turn", {"value": 1}),
                                              ("colorwc", {"color": {"r": 0, "g": 0, "b": 0}, "colorTemInKelvin": 6500})])

    def stream(self, h, rgb, v=1.0):
        h.p.stdin.write(json.dumps({"stream": {"rgb": rgb, "v": v} if rgb else None}) + "\n")
        h.p.stdin.flush()

    def test_screen_stream_is_throttled_and_the_newest_wins(self):
        h = self.start()
        h.want()
        self.settle(h)
        memo = open(self.memo).read()
        self.fake.cmds.clear()
        for i in range(30):  # 30 frames in 0.3 s
            self.stream(h, f"{i * 8:02X}0000")
            time.sleep(0.01)
        time.sleep(0.4)
        sent = [d for c, d in self.fake.cmds if c == "colorwc"]
        self.assertLessEqual(len(sent), 6, sent)
        self.assertEqual(sent[-1]["color"], {"r": 255, "g": 0, "b": 0})  # the last frame, through the curve
        self.assertEqual(open(self.memo).read(), memo, "the stream doesn't touch the memo")
        self.assertFalse(any(m.get("external") for m in h.out), "our own stream isn't the phone")

    def test_stream_dims_with_the_scene_and_ends_on_the_wanted_white(self):
        h = self.start()
        h.want()
        self.settle(h)
        self.fake.cmds.clear()
        self.stream(h, "FFFFFF", 0.5)
        self.assertTrue(h.until(lambda: any(c == "colorwc" for c, _ in self.fake.cmds)))
        self.assertEqual(self.fake.cmds[0][1]["color"], {"r": 55, "g": 55, "b": 55})  # 0.5 ** 2.2 of full
        self.stream(h, None)
        self.assertTrue(h.until(lambda: self.fake.cmds[-1] == ("colorwc", {"color": {"r": 0, "g": 0, "b": 0}, "colorTemInKelvin": 2700})),
                        self.fake.cmds)

    def test_whites_outside_the_lamp_are_clamped(self):
        h = self.start()
        h.want(kelvin=12000)
        self.settle(h)
        self.assertIn(("colorwc", {"color": {"r": 0, "g": 0, "b": 0}, "colorTemInKelvin": 9000}), self.fake.cmds)

    def test_lost_and_found_again(self):
        h = self.start()
        h.want()
        self.settle(h)
        self.fake.mute = True
        self.assertTrue(h.until(lambda: any("lost" in m for m in h.out), 5), h.out)
        self.fake.mute = False
        self.assertTrue(h.until(lambda: sum("found" in m for m in h.out) >= 2, 6), h.out)


if __name__ == "__main__":
    unittest.main(verbosity=1)
