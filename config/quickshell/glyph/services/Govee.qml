pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.settings

// local: the floor lamp — a Govee light on the LAN (an H6076 corner lamp here) through govee.py, Govee's LAN API, no cloud.
// Its own switch and level; its colour the case lights' (services/Rgb — their white on the lamp's own white LEDs), one
// from the palette, or a white 2000-9000 K; dark at night or in a game if asked. govee.py sends a field only when
// it changes here, so the phone and the lamp's button keep working: what they change comes back on the next poll, and
// a switch or level changed there is taken into prefs. Settings: riceState/lamp.json, prefs → LIGHTS → lamp
Singleton {
    id: root

    readonly property alias store: st
    property bool found: false   // answering now
    property string ip: ""
    property var status: null    // { on, level, rgb, kelvin } — the lamp as it reported itself last
    readonly property bool seen: st.device !== "" // a lamp answered once: prefs shows the lamp

    readonly property bool night: {
        const n = st.night, h = Rgb.hour; // Rgb keeps the clock
        if (!n || n.length !== 2 || n[0] === n[1]) return false;
        return n[0] < n[1] ? h >= n[0] && h < n[1] : h >= n[0] || h < n[1];
    }
    readonly property bool gaming: st.gameDark && Rules.store.game
    readonly property bool lit: st.on && !gaming && !night

    readonly property var pick: Rgb.palette.find(p => p.name === st.color) ?? Rgb.palette[0]
    readonly property bool white: st.source === "white" || st.source === "case" && Rgb.tone === "white"
    readonly property int kelvin: st.source === "white" ? st.kelvin : Rgb.store.kelvin
    // screen: what a monitor shows (Rgb's ambi.py), streamed — the wanted colour underneath stays the accent, so the
    // stream doesn't churn the memo; the lamp's level is the stream's ceiling
    readonly property bool screenWanted: lit && (st.source === "screen" || st.source === "case" && Rgb.tone === "screen")
    readonly property bool streaming: screenWanted && Rgb.liveUp
    readonly property var stream: streaming ? { rgb: Theme.hex(Rgb.live), v: Rgb.liveV } : null
    onStreamChanged: if (lamp.running && seen && !adopting) lamp.write(JSON.stringify({ stream: stream }) + "\n")
    readonly property bool onScreen: st.source === "screen" || st.source === "case" && Rgb.tone === "screen"
    readonly property color shade: white ? Rgb.tint(kelvin) : onScreen ? Theme.accent : st.source === "case" ? Rgb.base : pick.color
    readonly property var want: ({ on: lit, level: st.level, rgb: white ? null : Theme.hex(shade), kelvin: white ? kelvin : null })
    onWantChanged: send()
    function send() { if (lamp.running && seen && !adopting) lamp.write(JSON.stringify({ want: want, device: st.device }) + "\n"); }
    // the first lamp ever seen isn't repainted: prefs takes what it shows now, nothing goes out until something's picked
    property bool adopting: false
    function adopt(s) {
        st.on = s.on;
        st.level = Math.max(1, s.level);
        if (s.kelvin) {
            st.source = "white";
            st.kelvin = s.kelvin;
        } else if (s.rgb) {
            const c = Qt.color("#" + s.rgb), d = p => (p.color.r - c.r) ** 2 + (p.color.g - c.g) ** 2 + (p.color.b - c.b) ** 2;
            st.source = "palette";
            st.color = Rgb.palette.reduce((a, p) => d(p) < d(a) ? p : a).name;
        }
        adopting = false;
        send();
    }

    // what the lamp shows now, for prefs: its own report when there is one
    readonly property color now: !status ? shade : status.kelvin ? Rgb.tint(status.kelvin) : "#" + (status.rgb ?? "FFFFFF")

    Process {
        id: lamp
        running: true
        stdinEnabled: true
        command: ["/usr/bin/python3", "-I", Qt.resolvedUrl("govee.py").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.ready) {
                    root.send();
                } else if (m.found) {
                    root.found = true;
                    root.ip = m.found.ip;
                    if (st.device === "") root.adopting = true;
                    if (st.device !== m.found.device) st.device = m.found.device;
                    if (st.sku !== m.found.sku) st.sku = m.found.sku;
                } else if (m.status) {
                    root.status = m.status;
                    if (root.adopting) return root.adopt(m.status);
                    // switched or dimmed from the phone or the button: prefs takes it, so nothing here undoes it later
                    const ext = m.external ?? [];
                    if (ext.includes("on") && m.status.on !== root.lit && (m.status.on || !root.night && !root.gaming)) st.on = m.status.on;
                    if (ext.includes("level") && m.status.on && m.status.level !== st.level) st.level = m.status.level;
                } else if (m.lost) {
                    root.found = false;
                }
            }
        }
        stderr: SplitParser { onRead: line => console.warn(line) } // "govee: …"
        onExited: respawn.restart()
    }
    Timer { id: respawn; interval: 5000; onTriggered: lamp.running = true }

    FileView {
        id: file
        path: Theme.riceState + "/lamp.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: Qt.callLater(file.writeAdapter)
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: st
            property bool on: true
            property int level: 50          // %, the lamp's own scale (already even)
            property string source: "case"  // case (the case lights' colour) | palette | white | screen
            property string color: "accent" // a palette name
            property int kelvin: 2700       // 2000-9000
            property bool gameDark: false   // a room lamp: lit in a game unless asked
            property var night: []          // [from, to] hours, dark inside; [] — never
            property string device: ""      // the lamp's id from its scan reply; empty — none seen yet
            property string sku: ""
        }
    }
}
