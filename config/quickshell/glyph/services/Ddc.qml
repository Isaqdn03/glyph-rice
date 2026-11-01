pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// local: brightness of external monitors over DDC/CI (VCP 0x10) through ddcutil — needs i2c-dev and uaccess on /dev/i2c-*
// (~/dev/glyph-desktop-install/ddc-brightness.sh). Displays from `ddcutil detect`, matched to Hyprland by model, never by
// connector; left to right as they sit. One ddcutil per display at a time (a write takes ~300 ms on the 3090 Ti): a drag
// sends the newest value once the last one lands
Singleton {
    id: root

    // [{ bus, model, name, x }] — what Variants turns into screens
    property var found: []
    readonly property var screens: list.instances

    // re-read every display (the monitor's own buttons may have moved it): quick panel and prefs call this on open
    function refresh() { for (const s of screens) s.read(); }
    function detect() { if (!scan.running) scan.running = true; }

    // ddcutil detect --terse: "Display N" blocks with "I2C bus: /dev/i2c-4" and "Monitor: ACR:ED340CU S3:serial";
    // "Invalid display" blocks (no DDC) are skipped
    property var ddc: []
    Process {
        id: scan
        running: true
        command: ["ddcutil", "detect", "--terse"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const b of text.split(/\n(?=\S)/)) {
                    if (!b.startsWith("Display")) continue;
                    const bus = b.match(/\/dev\/i2c-(\d+)/);
                    const mon = b.match(/Monitor:\s+[^:]*:([^:]*):/);
                    if (bus && mon) out.push({ bus: parseInt(bus[1]), model: mon[1].trim() });
                }
                root.ddc = out;
                mons.running = true;
            }
        }
    }
    Process {
        id: mons
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const hy = JSON.parse(text);
                root.found = root.ddc.map(d => {
                    const m = hy.find(m => m.model === d.model || m.description.includes(d.model));
                    if (!m) return null;
                    return { bus: d.bus, model: d.model, x: m.x, name: m.model.startsWith("AW") ? "alienware" : m.make.split(" ")[0].toLowerCase() };
                }).filter(Boolean).sort((a, b) => a.x - b.x);
            }
        }
    }
    // hotplug: DDC needs a moment after the link comes up
    Timer { id: again; interval: 3000; onTriggered: root.detect() }
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "monitoraddedv2" || e.name === "monitorremovedv2") again.restart(); }
    }

    Variants {
        id: list
        model: root.found

        Scope {
            id: s
            required property var modelData
            readonly property string name: modelData.name
            readonly property int bus: modelData.bus
            property real value: 0      // 0…1
            property int max: 100
            property bool ready: false  // first read landed; until then the slider stays hidden
            property int want: -1       // raw value not sent yet

            function set(v) {
                value = Math.max(0, Math.min(1, v));
                want = Math.round(value * max);
                if (!put.running && !get.running) send();
            }
            function send() {
                put.command = ["ddcutil", "--bus", String(bus), "--noverify", "setvcp", "10", String(want)];
                want = -1;
                put.running = true;
            }
            function read() { if (!put.running && want < 0) get.running = true; }

            Component.onCompleted: read()

            // --brief: "VCP 10 C 50 100" — current, max
            Process {
                id: get
                command: ["ddcutil", "--bus", String(s.bus), "--brief", "getvcp", "10"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const m = text.match(/VCP 10 C (\d+) (\d+)/);
                        if (!m) return;
                        s.max = parseInt(m[2]) || 100;
                        if (s.want < 0 && !put.running) s.value = parseInt(m[1]) / s.max;
                        s.ready = true;
                    }
                }
                onExited: if (s.want >= 0) s.send()
            }
            Process {
                id: put
                onExited: if (s.want >= 0) s.send()
            }
        }
    }
}
