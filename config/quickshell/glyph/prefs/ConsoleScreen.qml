import QtQuick
import qs
import qs.settings

// local: the screen in miniature for the console's pages, to scale (a logical px is k here, a design px of the shell u): the dot
// grid if it's on, and the bar where Bar.qml puts it — pill 64 at the gap. Windows start past its zone and hypr's own gap (l).
// An auto-hidden one slides in over the windows: an unlit outline on top of them
Rectangle {
    id: scr

    required property var ctl // prefs/Console: which screen it is
    readonly property var disp: ctl.disp
    readonly property real k: width / (disp.lw || 2752)
    readonly property real u: Theme.s * k
    readonly property bool across: Theme.state.barAt === "top"
    readonly property bool hasBar: Theme.scr(ctl.mon, "bar")
    readonly property bool hides: !across && Theme.state.barHide.includes(ctl.monModel)
    readonly property real o: Rules.store.gapsOut * k
    readonly property real g: Rules.store.gapsIn * k
    readonly property real l: hasBar && !hides ? (64 + Rules.store.gapsOut) * u + o : o

    width: 1140
    height: width * (disp.lh || 1152) / (disp.lw || 2752)
    color: "transparent"
    border { width: 1; color: Theme.s3 }
    clip: true

    Image {
        visible: Theme.state.grid
        anchors { fill: parent; margins: 1 }
        fillMode: Image.Tile
        source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="1.2" fill="#${Theme.hex(Theme.s2)}"/></svg>`)
    }
    Rectangle {
        visible: scr.hasBar
        z: scr.hides ? 1 : 0
        x: Rules.store.gapsOut * scr.u
        y: x
        width: scr.across ? scr.width - 2 * x : 64 * scr.u
        height: scr.across ? 64 * scr.u : scr.height - 2 * y
        radius: Theme.corner(Math.min(width, height) / 2)
        color: scr.hides ? "transparent" : Theme.s1
        border { width: 1; color: scr.hides ? Theme.mute : Theme.s2 }
    }
}
