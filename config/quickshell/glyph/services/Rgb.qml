pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.settings

// local: the case lights. RAM, the Thermaltake fan box and the board's Aura headers go through OpenRGB's server (root,
// 127.0.0.1:6742 — ~/dev/glyph-desktop-install/rgb.sh), the Kraken's Aer fans through liquidctl (OpenRGB has no Kraken Z).
// One steady colour — the Style's accent or white — dimmed by level; dark when off, in game mode, or in the night hours.
// The Kraken's LCD shows Glyph's dial of the coolant temperature (kraken.py) or its own liquid screen; its brightness
// follows too: level, or 0 when dark.
// Direct mode only: volatile, nothing lands in the RAM's own memory (a cold boot shows its rainbow until the shell is up).
// Mouse and keyboard are left alone. Settings: riceState/lights.json, prefs → LIGHTS
Singleton {
    id: root

    readonly property alias store: st
    // OpenRGB types that sit in the case; anything else (mouse, keyboard, headset…) isn't touched
    readonly property var kinds: ({ DRAM: "ram", Cooler: "fans", Motherboard: "board", GPU: "gpu", "LED Strip": "strip", Light: "light", Case: "case", Storage: "ssd" })
    property var devs: []   // [{ i, type }] from openrgb -ld
    property int fans: 0    // LED accessories on the Kraken; 0 — none, no Kraken, or liquidctl can't open it
    property bool screen: false // a Kraken Z: its LCD (liquid temperature) dims with the lights, 0 when they're dark
    // what's lit, for prefs: [{ name, n, mono }] — n dots (sticks, fans, or one per controller); mono — white, not the colour
    readonly property var parts: {
        const out = [];
        for (const d of devs) {
            const p = out.find(p => p.name === kinds[d.type]);
            if (p) p.n++; else out.push({ name: kinds[d.type], n: 1 });
        }
        if (fans > 0) out.push({ name: "kraken", n: fans });
        if (screen) out.push({ name: "screen", n: 1, mono: true });
        return out;
    }

    property int hour: new Date().getHours()
    readonly property bool night: {
        const n = st.night;
        if (!n || n.length !== 2 || n[0] === n[1]) return false;
        return n[0] < n[1] ? hour >= n[0] && hour < n[1] : hour >= n[0] || hour < n[1];
    }
    readonly property bool gaming: st.gameDark && Rules.store.game
    readonly property bool lit: st.on && !gaming && !night
    readonly property color base: st.white ? "#FFFFFF" : Theme.accent
    readonly property real gain: Math.pow(st.level / 100, 2) // LEDs are linear; squared, half the ring looks like half
    readonly property string hex: lit ? Theme.hex(Qt.rgba(base.r * gain, base.g * gain, base.b * gain, 1)) : "000000"

    readonly property int lcd: lit ? st.level : 0 // the LCD's own brightness is already even, no squaring

    onHexChanged: soon.restart()
    onLcdChanged: soon.restart()
    Timer { id: soon; interval: 120; onTriggered: root.push() }

    // the screen's face (kraken.py): a Glyph dial of the coolant temperature. Redrawn only when the reading moves 0.8 °C
    // past the whole degree it shows (35.5 doesn't flicker 35↔36), uploaded at most every 30 s, untouched while dark —
    // nobody says if the Kraken keeps its images in flash, so writes stay rare. st.face false — the Kraken's own screen
    property real liquid: 0 // °C, from the kernel's z53 hwmon: no USB traffic
    property int shows: -1  // the whole degree on the face
    onLiquidChanged: if (liquid > 0 && (shows < 0 || Math.abs(liquid - shows) >= 0.8)) shows = Math.round(liquid)
    FileView { id: coolant; path: SysStats.hwmon(["z53"]); blockAllReads: true; printErrors: false }
    Timer {
        interval: 10000
        running: root.screen && st.face
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            coolant.reload();
            const t = parseInt(coolant.text());
            if (t > 0) root.liquid = t / 1000;
        }
    }
    readonly property string facePng: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/glyph/kraken.png"
    // what the screen should show: "" — nothing to do (no screen, dark, no reading yet), "liquid", or the dial's arguments.
    // The panel is round and black, so the dial keeps the dark greys in a light theme too
    readonly property var faceGreys: Theme.light ? Theme.glyphDark : Theme.greys
    readonly property string face: !screen || !lit ? "" : !st.face ? "liquid" : shows < 0 ? ""
        : [shows, faceGreys[6], faceGreys[3], faceGreys[5], base].map(v => typeof v === "number" ? String(v) : Theme.hex(v)).join(" ")
    property string drawn: ""
    property string sentFace: ""
    onFaceChanged: draw()
    function draw() {
        if (face === "" || face === "liquid" || face === drawn || painter.running) return;
        const a = face.split(" ");
        painter.key = face;
        painter.command = ["/usr/bin/python3", "-I", Qt.resolvedUrl("kraken.py").toString().replace("file://", ""), a[0], facePng].concat(a.slice(1));
        painter.running = true;
    }
    Process {
        id: painter
        property string key
        onExited: code => {
            if (code === 0) root.drawn = key;
            root.draw();
            root.push();
        }
    }
    Timer { id: cool; interval: 30000; onTriggered: root.push() }

    // one write per tool at a time; a drag that moved on meanwhile sends its newest value when the last one lands.
    // The Kraken's fans and screen are one device: one liquidctl at a time, fans first
    property string sent: ""     // openrgb
    property string sentFans: ""
    property int sentLcd: -1
    function push() {
        if (!set.running && devs.length && hex !== sent) {
            sent = hex;
            set.command = ["openrgb", "--nodetect"].concat(...devs.map(d => ["-d", String(d.i), "-m", "direct", "-c", sent]));
            set.running = true;
        }
        if (kraken.running) return;
        if (fans > 0 && hex !== sentFans) {
            sentFans = hex;
            kraken.command = ["liquidctl", "--match", "kraken", "set", "external", "color"].concat(sentFans === "000000" ? ["off"] : ["fixed", sentFans]);
            kraken.running = true;
        } else if (screen && lcd !== sentLcd) {
            sentLcd = lcd;
            kraken.command = ["liquidctl", "--match", "kraken", "set", "lcd", "screen", "brightness", String(sentLcd)];
            kraken.running = true;
        } else if (face !== "" && face !== sentFace && (face === "liquid" || face === drawn) && !cool.running) {
            sentFace = face;
            kraken.command = ["liquidctl", "--match", "kraken", "set", "lcd", "screen"].concat(face === "liquid" ? ["liquid"] : ["static", facePng]);
            kraken.running = true;
            if (face !== "liquid") cool.restart();
        }
    }
    function again() {
        sent = "";
        sentFans = "";
        sentLcd = -1;
        sentFace = "";
        cool.stop();
        push();
    }

    // --nodetect: no server — nothing, instead of probing the hardware as the user
    Process { id: set; onExited: root.push() }
    Process { id: kraken; onExited: root.push() }

    // the server comes up a few seconds after login (detection) — keep asking for 3 min
    property int tries: 0
    function scan() {
        tries = 0;
        list.running = true;
        init.running = true;
    }
    Process {
        id: list
        command: ["openrgb", "--nodetect", "-ld"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const b of text.split(/\n(?=\d+: )/)) {
                    const m = b.match(/^(\d+): /), t = b.match(/^\s+Type:\s+(.+)$/m);
                    if (m && t && root.kinds[t[1].trim()]) out.push({ i: +m[1], type: t[1].trim() });
                }
                root.devs = out;
                if (!out.length && root.tries++ < 18) retry.restart();
                else root.again();
            }
        }
    }
    Timer { id: retry; interval: 10000; onTriggered: list.running = true }
    // liquidctl wants an initialize after power-on; it also says what hangs off the external channel
    Process {
        id: init
        command: ["liquidctl", "--match", "kraken", "initialize"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.fans = (text.match(/LED accessory/g) || []).length;
                root.screen = /Kraken Z|LCD Brightness/.test(text);
                root.again();
            }
        }
    }
    Component.onCompleted: scan()

    // the clock for the night hours; a jump means the machine slept — USB controllers wake up in their own colours
    property real last: Date.now()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now();
            root.hour = new Date().getHours();
            if (now - root.last > 90000) root.scan();
            root.last = now;
        }
    }

    FileView {
        id: file
        path: Theme.riceState + "/lights.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: Qt.callLater(file.writeAdapter)
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: st
            property bool on: true
            property int level: 100      // %
            property bool white: false   // false — the Style's accent
            property bool gameDark: true // dark while game mode is on (manual or services/Game)
            property var night: []       // [from, to] hours, dark inside; [] — never
            property bool face: true     // the Kraken's screen shows Glyph's dial (kraken.py), not its own liquid screen
        }
    }
}
