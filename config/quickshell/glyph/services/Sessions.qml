pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// local: Claude Code sessions, written by sessions.py from Claude Code hooks (~/.claude/settings.json).
// state: working, ask (permission prompt or a question), done (finished, not seen yet), idle.
// ack() when the agents card closes: done becomes idle. prune drops sessions whose claude process died
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("sessions.py").toString().replace("file://", "")
    property var list: []  // [{ id, name, cwd, state, born, at }], oldest first
    readonly property int waiting: list.filter(s => needs(s)).length

    function needs(s) { return s.state === "ask" || s.state === "done"; }
    function ack() { if (list.some(s => s.state === "done")) run(["ack"]); }
    function run(args) { Quickshell.execDetached(["/usr/bin/python3", "-I", script, ...args]); }

    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/glyph/claude-sessions.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let j;
            try { j = JSON.parse(text()); } catch (e) { return; }
            root.list = Object.entries(j.sessions ?? {}).map(([id, s]) => Object.assign({ id }, s)).sort((a, b) => a.born - b.born);
        }
        onLoadFailed: root.list = []
    }

    // a session killed without SessionEnd stays in the file until its pid is checked
    Timer { interval: 30000; running: root.list.length > 0; repeat: true; onTriggered: root.run(["prune"]) }
}
