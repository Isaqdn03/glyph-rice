pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// local: Claude and Codex plan limits from usage.py every 5 min; refresh() on demand once the numbers are a minute old
Singleton {
    id: root

    property var agents: []  // [{ id, plan, limits: [{ key, pct, reset }], at, stale, error }], claude first
    property real at: 0
    readonly property var claude: agents.find(a => a.id === "claude") ?? null
    readonly property var codex: agents.find(a => a.id === "codex") ?? null
    readonly property bool busy: run.running

    // the headline limit: the 5h window, else the one an agent hits first
    function top(a) {
        if (!a?.limits?.length) return null;
        return a.limits.find(l => l["key"] === "5h") ?? a.limits.reduce((m, l) => l.pct > m.pct ? l : m);
    }
    function refresh(force) { if (force || Date.now() - at > 60000) run.running = true; }

    Process {
        id: run
        command: ["/usr/bin/python3", "-I", Qt.resolvedUrl("usage.py").toString().replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                let j;
                try { j = JSON.parse(text); } catch (e) { return; }
                root.agents = j.agents;
                root.at = j.at;
            }
        }
    }

    Timer { interval: 5 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: run.running = true }
}
