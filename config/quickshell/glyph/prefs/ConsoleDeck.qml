import QtQuick
import qs
import qs.components

// local: DECK in the console (prefs/Console.qml): the screen with the deck's strip at the bottom edge, in order — drag along it to
// reorder. Edges with lit dots open on hover. Keys: a section per key, in strip order, numbered; ↵ takes it in or out, shift ←→ moves it
Item {
    id: root

    required property var ctl
    readonly property var ids: Theme.state.deck
    // the keys' order: the list's, then what it leaves out. A press leaves every key where it is — otherwise the next part slides under
    // the pointer and a second press drops that one; press-press puts it back in its place. A move re-sorts, so does coming back here
    function sorted() { return ids.concat(Theme.decks.filter(k => !ids.includes(k))); }
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
        ctl.flip("deck", id, order.slice(0, slot).filter(k => ids.includes(k)).length - 1);
        pressing = false;
    }
    readonly property string head: `desktop · ${ids.length} of ${Theme.decks.length} sections · bottom edge`
    // a section being dragged (-1 — none): dx — the pointer's shift, at — where it is in the strip, to — where it'd land
    property int from: -1
    property real dx: 0
    readonly property real at: Math.max(12, Math.min(12 + (ids.length - 1) * 110, 12 + from * 110 + dx))
    readonly property int to: Math.round((at - 12) / 110)

    ConsoleScreen {
        ctl: root.ctl

        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 44 }
            width: Math.max(1, root.ids.length) * 110 + 24
            height: 110
            radius: Theme.corner(40)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            Lb { visible: !root.ids.length; anchors.centerIn: parent; text: "empty"; px: 13 }
            Repeater {
                model: root.ids
                Item {
                    id: slot
                    required property string modelData
                    required property int index
                    // while one is dragged: it follows the pointer, the ones between it and the drop step toward its place
                    readonly property int place: root.from < 0 ? index
                        : index > root.from && index <= root.to ? index - 1
                        : index < root.from && index >= root.to ? index + 1 : index
                    x: dd.active ? root.at : 12 + place * 110
                    z: dd.active ? 1 : 0
                    width: 110
                    height: parent.height
                    Behavior on x {
                        enabled: !dd.active
                        NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 54
                            height: 54
                            radius: 27
                            color: Theme.s2
                            Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.fg }
                        }
                        Lb { anchors.horizontalCenter: parent.horizontalCenter; text: slot.modelData; px: 10 }
                    }
                    HoverHandler { cursorShape: Qt.OpenHandCursor }
                    DragHandler {
                        id: dd
                        target: null
                        yAxis.enabled: false
                        cursorShape: Qt.ClosedHandCursor
                        onActiveTranslationChanged: root.dx = activeTranslation.x / Theme.s // window px, and the stage is scaled
                        onActiveChanged: {
                            if (active) {
                                root.from = slot.index;
                                return;
                            }
                            // after the signal: a new list rebuilds the slots, this one too
                            const from = root.from, to = root.to;
                            Qt.callLater(() => {
                                root.from = -1;
                                root.ctl.move("deck", from, to);
                            });
                        }
                    }
                }
            }
        }
        // the edges that catch the pointer: bottom — the deck, right — quick settings
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
            spacing: 6
            Repeater {
                model: 24
                Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.state.deckHover ? Theme.fg : Theme.s3 }
            }
        }
        Column {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 6
            Repeater {
                model: 16
                Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.state.quickHover ? Theme.fg : Theme.s3 }
            }
        }
    }
    Lb { y: 500; px: 11; color: Theme.mute; text: `your screen · ${root.ctl.aspect(root.ctl.disp.lw, root.ctl.disp.lh)} · lit dots on an edge = it opens on hover` }

    Column {
        x: 1250
        spacing: 34
        Block {
            title: "sections"
            note: "in strip order · shift ←→ moves one"
            Row {
                spacing: 12
                Repeater {
                    id: secs
                    model: root.order.length // by index: a new order doesn't rebuild the keys, focus stays
                    Key {
                        required property int index
                        readonly property string id_: root.order[index] ?? ""
                        readonly property int at: root.ids.indexOf(id_)
                        minW: 180
                        text: (at >= 0 ? String(at + 1).padStart(2, "0") : "--") + " " + id_
                        on: at >= 0
                        onHit: root.press(id_, index)
                        onShifted: d => {
                            if (at >= 0) secs.itemAt(root.ctl.move("deck", at, at + d))?.forceActiveFocus(); // focus follows it
                        }
                    }
                }
            }
        }
        Block {
            title: "opens on hover"
            note: "off = only its key"
            Row {
                spacing: 12
                Key { minW: 260; text: "deck · bottom edge"; on: Theme.state.deckHover; onHit: Theme.state.deckHover = !on }
                Key { minW: 260; text: "quick · right edge"; on: Theme.state.quickHover; onHit: Theme.state.quickHover = !on }
            }
        }
    }
}
