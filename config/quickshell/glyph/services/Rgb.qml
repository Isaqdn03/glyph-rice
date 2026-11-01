pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.settings

// local: the case lights. RAM, the Thermaltake fan box and the board's Aura headers go through OpenRGB's server (root,
// 127.0.0.1:6742 — ~/dev/glyph-desktop-install/rgb.sh), the Kraken's Aer fans through liquidctl (OpenRGB has no Kraken Z).
// One steady colour — the Style's accent or white — dimmed by level; dark when off, in game mode, or in the night hours.
// Direct mode only: volatile, nothing lands in the RAM's own memory (a cold boot shows its rainbow until the shell is up).
// Mouse and keyboard are left alone. Settings: riceState/lights.json, prefs → LIGHTS
Singleton {
    id: root

    readonly property alias store: st
    // OpenRGB types that sit in the case; anything else (mouse, keyboard, headset…) isn't touched
    readonly property var kinds: ({ DRAM: "ram", Cooler: "fans", Motherboard: "board", GPU: "gpu", "LED Strip": "strip", Light: "light", Case: "case", Storage: "ssd" })
    property var devs: []   // [{ i, type }] from openrgb -ld
    property int fans: 0    // LED accessories on the Kraken; 0 — none, no Kraken, or liquidctl can't open it
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
    readonly property real gain: Math.pow(st.level / 100, 2) // LEDs are linear; squared, half the ring looks like half
    readonly property string hex: lit ? Theme.hex(Qt.rgba(base.r * gain, base.g * gain, base.b * gain, 1)) : "000000"

    onHexChanged: soon.restart()
    Timer { id: soon; interval: 120; onTriggered: root.push() }

    // one write per tool at a time; a drag that moved on meanwhile sends its newest colour when the last one lands
    property string sent: ""
    function push() {
        if (set.running || kraken.running || hex === sent) return;
        sent = hex;
        if (devs.length) {
            set.command = ["openrgb", "--nodetect"].concat(...devs.map(d => ["-d", String(d.i), "-m", "direct", "-c", sent]));
            set.running = true;
        }
        if (fans > 0) {
            kraken.command = ["liquidctl", "--match", "kraken", "set", "external", "color"].concat(sent === "000000" ? ["off"] : ["fixed", sent]);
            kraken.running = true;
        }
    }
    function again() { sent = ""; push(); }

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
        }
    }
}
