pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs

// cava в фоне, пока кто-то смотрит (active): 8 полос моно 0…1, от баса к верхам (число — в cava.conf)
Singleton {
    id: root

    property bool active: false
    property var bars: Array(8).fill(0)

    // local: the wallpaper's beat — how far the bass jumps above its last ~second, fast rise, slow fall: rests near 0,
    // kicks reach .5–.9. Cava runs for it whenever music plays (Theme.state.wallPulse) or the wallpaper picker is open —
    // its autosens needs ~2 s to stop clipping, so it isn't started only when a wallpaper shows; home/Back gates the shader
    readonly property bool beatOn: Media.playing && (Sys.wallOpen || Theme.state.wallPulse && Theme.state.wall !== "")
    property real bass: 0
    property real slow: 0.5
    onBarsChanged: {
        const b = Math.min(1, ((bars[0] ?? 0) + (bars[1] ?? 0)) / 2);
        slow = slow * 0.95 + b * 0.05;
        const t = Math.max(0, Math.min(1, (b - slow) * 4));
        bass = t > bass ? t : bass * 0.8 + t * 0.2;
    }

    Process {
        running: root.active || root.beatOn // local: beatOn
        command: ["cava", "-p", Qt.resolvedUrl("cava.conf").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: line => root.bars = line.split(";").filter(s => s !== "").map(v => v / 100)
        }
        onRunningChanged: if (!running) { root.bars = Array(8).fill(0); root.bass = 0; } // local: bass
    }
}
