import QtQuick
import Quickshell
import qs
import qs.components

// local: BAR in the console (prefs/Console.qml): the tray as the bar shows it — a column on a left bar with names beside it, a row
// on a top one with names under — drag along it to reorder; each screen with its bar, hollow where it auto-hides. Keys: a part per
// key in bar order, ↵ in or out, shift ←→ moves it; the edge, window title, auto-hide per screen (left bar only, Bar.qml)
Item {
    id: root

    required property var ctl
    readonly property var ids: Theme.state.bar.filter(b => Theme.bars.includes(b))
    // the keys' order: the list's, then what it leaves out. A press leaves every key where it is — otherwise the next part slides under
    // the pointer and a second press drops that one; press-press puts it back in its place. A move re-sorts, so does coming back here
    function sorted() { return ids.concat(Theme.bars.filter(k => !ids.includes(k))); }
    property var order: []
    property var last: []
    property bool pressing: false
    Component.onCompleted: {
        last = ids;
        order = sorted();
    }
    onIdsChanged: {
        const same = ids.join() === last.join();
        last = ids;
        if (!pressing && !same) order = sorted();
    }
    onVisibleChanged: if (visible) order = sorted()
    function press(id, slot) {
        pressing = true;
        ctl.flip("bar", id, order.slice(0, slot).filter(k => ids.includes(k)).length - 1);
        pressing = false;
    }
    readonly property bool across: Theme.state.barAt === "top"
    readonly property real step: across ? 100 : 52
    readonly property string head: `desktop · ${ids.length} of ${Theme.bars.length} in the tray · ${across ? "top" : "left"} edge`
    // a part being dragged (-1 — none): d — the pointer's shift along the bar, at — where it is, to — where it'd land
    property int from: -1
    property real d: 0
    readonly property real at: Math.max(10, Math.min(10 + (ids.length - 1) * step, 10 + from * step + d))
    readonly property int to: Math.round((at - 10) / step)

    // ---- the tray ----
    Rectangle {
        readonly property int n: Math.max(1, root.ids.length)
        width: root.across ? n * 100 + 20 : 60
        height: root.across ? 106 : n * 52 + 20
        radius: Theme.corner(root.across ? 40 : 30)
        color: Theme.s1
        border { width: 1; color: Theme.s2 }
        Lb { visible: !root.ids.length; anchors.centerIn: parent; text: "empty"; px: 10 }
        Repeater {
            model: root.ids
            Item {
                id: part
                required property string modelData
                required property int index
                readonly property int place: root.from < 0 ? index
                    : index > root.from && index <= root.to ? index - 1
                    : index < root.from && index >= root.to ? index + 1 : index
                // its place along the bar: under the pointer while dragged
                property real pos: bd.active ? root.at : 10 + place * root.step
                Behavior on pos {
                    enabled: !bd.active
                    NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }
                }
                x: root.across ? pos : 0
                y: root.across ? 0 : pos
                z: bd.active ? 1 : 0
                width: root.across ? 100 : 60
                height: root.across ? parent.height : 52
                Rectangle {
                    id: partDot
                    x: (parent.width - width) / 2
                    y: root.across ? 16 : (parent.height - height) / 2
                    width: 40
                    height: 40
                    radius: 20
                    color: Theme.s2
                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.fg }
                }
                Lb {
                    x: root.across ? (parent.width - width) / 2 : parent.width + 12
                    y: root.across ? partDot.y + partDot.height + 10 : (parent.height - height) / 2
                    text: part.modelData
                    px: root.across ? 10 : 11
                    color: Theme.fg
                }
                HoverHandler { cursorShape: Qt.OpenHandCursor }
                DragHandler {
                    id: bd
                    target: null
                    xAxis.enabled: root.across
                    yAxis.enabled: !root.across
                    cursorShape: Qt.ClosedHandCursor
                    onActiveTranslationChanged: root.d = (root.across ? activeTranslation.x : activeTranslation.y) / Theme.s
                    onActiveChanged: {
                        if (active) {
                            root.from = part.index;
                            return;
                        }
                        const from = root.from, to = root.to;
                        Qt.callLater(() => {
                            root.from = -1;
                            root.ctl.edit("bar", a => a.splice(to, 0, a.splice(from, 1)[0]));
                        });
                    }
                }
            }
        }
    }

    // ---- each screen with its bar ----
    Grid {
        x: root.across ? 0 : 400
        y: root.across ? 170 : 0
        columns: root.across ? 2 : 1
        spacing: root.across ? 40 : 26
        Repeater {
            model: Quickshell.screens.slice().sort((a, b) => a.name.localeCompare(b.name))
            Column {
                id: sc
                required property var modelData
                readonly property string scr: modelData.model || modelData.name
                readonly property bool shown: Theme.scr(modelData.name, "bar")
                readonly property bool hides: !root.across && Theme.state.barHide.includes(scr)
                spacing: 10
                Rectangle {
                    width: 520
                    height: 218
                    color: "transparent"
                    border { width: 1; color: Theme.s3 }
                    Image {
                        anchors { fill: parent; margins: 1 }
                        fillMode: Image.Tile
                        source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="13" height="13"><circle cx="6.5" cy="6.5" r="1.2" fill="#${Theme.hex(Theme.s2)}"/></svg>`)
                    }
                    Rectangle {
                        visible: sc.shown
                        x: 8
                        y: 8
                        width: root.across ? parent.width - 16 : 14
                        height: root.across ? 14 : parent.height - 16
                        radius: Theme.corner(7)
                        color: sc.hides ? "transparent" : Theme.fg
                        border { width: sc.hides ? 1 : 0; color: Theme.mute }
                    }
                }
                Row {
                    spacing: 22
                    Lb { text: `${sc.scr} · ${sc.modelData.name}`; px: 11; color: Theme.fg }
                    Lb { px: 11; text: !sc.shown ? "no bar here · display shows it" : sc.hides ? "hides · peeks from the edge" : "always shown" }
                }
            }
        }
    }

    // ---- the keys ----
    Block {
        x: 1250
        title: "tray"
        note: "in bar order · shift ←→ moves one"
        Flow {
            width: 1106
            spacing: 12
            Repeater {
                id: parts
                model: root.order.length // by index: a new order doesn't rebuild the keys, focus stays
                Key {
                    required property int index
                    readonly property string id_: root.order[index] ?? ""
                    readonly property int at: root.ids.indexOf(id_)
                    minW: 162
                    text: (at >= 0 ? String(at + 1).padStart(2, "0") : "--") + " " + id_
                    on: at >= 0
                    onHit: root.press(id_, index)
                    onShifted: d => {
                        if (at >= 0) parts.itemAt(root.ctl.move("bar", at, at + d))?.forceActiveFocus(); // focus follows it
                    }
                }
            }
        }
    }
    Column {
        x: 1250
        y: 236
        spacing: 12
        Block {
            title: "edge"
            note: "every screen"
            Row {
                spacing: 12
                Bank { opts: ["left", "top"]; cur: root.across ? 1 : 0; onPicked: i => Theme.state.barAt = ["left", "top"][i] }
                Key { text: "window title"; on: Theme.state.barTitle; onHit: Theme.state.barTitle = !on }
            }
        }
        Lb { px: 10; color: Theme.mute; text: root.across ? "the title sits left of the clock" : "the title sits above the clock" }
    }
    Column {
        x: 1810
        y: 236
        spacing: 30
        // local: per monitor, by model (bar/Bar.qml) — keeps static white off OLEDs. Only a left bar can hide
        Block {
            title: "auto-hide"
            note: root.across ? "a left bar only" : "keeps static white off an oled"
            Row {
                spacing: 12
                Repeater {
                    model: Quickshell.screens.slice().sort((a, b) => a.name.localeCompare(b.name))
                    Key {
                        required property var modelData
                        readonly property string scr: modelData.model || modelData.name
                        minW: 190
                        enabled: !root.across
                        text: scr
                        on: Theme.state.barHide.includes(scr)
                        onHit: root.ctl.edit("barHide", a => {
                            const i = a.indexOf(scr);
                            if (i >= 0) a.splice(i, 1);
                            else a.push(scr);
                        })
                    }
                }
            }
        }
        Block {
            title: "show after"
            note: "left edge · or super `"
            Bank {
                opts: ["0.15 s", "0.3 s", "0.6 s"]
                cur: [150, 300, 600].indexOf(Theme.state.barShowMs)
                onPicked: i => Theme.state.barShowMs = [150, 300, 600][i]
            }
        }
    }
}
