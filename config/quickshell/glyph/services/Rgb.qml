pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.settings

// local: the case lights. RAM, the Thermaltake fan box and the board's Aura headers go through OpenRGB's server (root,
// 127.0.0.1:6742 — ~/dev/glyph-desktop-install/rgb.sh); the Kraken Z (OpenRGB doesn't know it) through kraken.py, which
// owns the cooler: its Aer fans, its LCD's brightness and what the LCD shows — Glyph's dial of CPU and GPU, a GIF from
// the gif folder, or NZXT's own liquid screen. One steady colour — the Style's accent or white — dimmed by level; dark
// when off, in game mode, or in the night hours, and the LCD goes to 0 with them.
// Direct mode only: volatile, nothing lands in the RAM's own memory (a cold boot shows its rainbow until the shell is up).
// Mouse and keyboard are left alone. Settings: riceState/lights.json, prefs → LIGHTS
Singleton {
    id: root

    readonly property alias store: st
    // OpenRGB types that sit in the case; anything else (mouse, keyboard, headset…) isn't touched
    readonly property var kinds: ({ DRAM: "ram", Cooler: "fans", Motherboard: "board", GPU: "gpu", "LED Strip": "strip", Light: "light", Case: "case", Storage: "ssd" })
    property var devs: []    // [{ i, type }] from openrgb -ld
    property int fans: 0     // LED accessories on the Kraken; 0 — none, or no Kraken
    property bool screen: false // kraken.py found the Kraken Z
    // what's lit, for prefs: [{ name, n }] — n dots (sticks, fans, or one per controller)
    readonly property var parts: {
        const out = [];
        for (const d of devs) {
            const p = out.find(p => p.name === kinds[d.type]);
            if (p) p.n++; else out.push({ name: kinds[d.type], n: 1 });
        }
        if (fans > 0) out.push({ name: "kraken", n: fans });
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
    // LEDs are linear, a screen isn't: each channel goes through the sRGB curve (≈2.2), level with it. Without it the
    // accent's faint green and blue glow at full LED strength (#D71921 came out pink), and half the ring looks like half
    readonly property real gain: Math.pow(st.level / 100, 2.2)
    function led(c) { return Math.pow(c, 2.2) * gain; }
    readonly property string hex: lit ? Theme.hex(Qt.rgba(led(base.r), led(base.g), led(base.b), 1)) : "000000"

    onHexChanged: soon.restart()
    Timer { id: soon; interval: 120; onTriggered: root.push() }

    // OpenRGB: one write at a time; a drag that moved on meanwhile sends its newest colour when the last one lands
    property string sent: ""
    function push() {
        if (set.running || !devs.length || hex === sent) return;
        sent = hex;
        set.command = ["openrgb", "--nodetect"].concat(...devs.map(d => ["-d", String(d.i), "-m", "direct", "-c", sent]));
        set.running = true;
    }
    function again() {
        sent = "";
        push();
    }
    // --nodetect: no server — nothing, instead of probing the hardware as the user
    Process { id: set; onExited: root.push() }

    // the server comes up a few seconds after login (detection) — keep asking for 3 min
    property int tries: 0
    function scan() {
        tries = 0;
        list.running = true;
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
    Component.onCompleted: scan()

    // ---- the Kraken: kraken.py gets the whole wanted state on hello and whatever changes after ----
    readonly property int lcd: lit ? st.level : 0 // the LCD's own brightness is already even, no curve
    // the panel is round and black, so the dial keeps the dark greys in a light theme too; head — the lights' colour
    readonly property var faceGreys: Theme.light ? Theme.glyphDark : Theme.greys
    readonly property var colors: [faceGreys[6], faceGreys[3], faceGreys[5], base, Theme.red].map(c => Theme.hex(c))
    readonly property string gif: st.gif && Gifs.list.includes(st.gif) ? st.gif : Gifs.list.find(p => p) ?? ""
    readonly property string mode: st.screen === "gif" && !gif ? "dial" : st.screen
    readonly property var want: ({ fans: hex, bright: lcd, screen: mode, gif: gif, colors: colors })
    onWantChanged: send(want)
    function send(o) { if (kraken.running) kraken.write(JSON.stringify(o) + "\n"); }

    // what the dial shows now and which frame is up (kraken.py writes it to framePath, prefs previews it)
    property var stats: ({})
    property int frame: 0
    readonly property string framePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glyph-kraken.png"
    Process {
        id: kraken
        running: true
        stdinEnabled: true
        command: ["/usr/bin/python3", "-I", Qt.resolvedUrl("kraken.py").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.hello) {
                    root.fans = m.fans;
                    root.screen = true;
                    root.send(root.want);
                } else if (m.frame) {
                    root.frame = m.frame;
                    root.stats = m;
                }
            }
        }
        stderr: SplitParser { onRead: line => console.warn(line) } // "kraken: …" — what went wrong with the cooler
        onExited: respawn.restart() // crashed or killed: back in a few seconds
    }
    Timer { id: respawn; interval: 5000; onTriggered: kraken.running = true }

    // the clock for the night hours; a jump means the machine slept — USB controllers wake up in their own colours
    property real last: Date.now()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now();
            root.hour = new Date().getHours();
            if (now - root.last > 90000) {
                root.scan();
                root.send({ init: true });
            }
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
            property int level: 100        // %
            property bool white: false     // false — the Style's accent
            property bool gameDark: true   // dark while game mode is on (manual or services/Game)
            property var night: []         // [from, to] hours, dark inside; [] — never
            property string screen: "dial" // the Kraken's LCD: dial (CPU and GPU), gif, liquid (NZXT's own)
            property string gif: ""        // path in the gif folder (services/Gifs); empty — the first one
        }
    }
}
