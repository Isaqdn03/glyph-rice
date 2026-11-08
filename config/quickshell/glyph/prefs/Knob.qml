import QtQuick
import qs
import qs.components

// local: a console knob — a 270° arc of dots from bottom-left over the top to bottom-right (135° → 405°), lit up to the
// value, a bigger dot at the value, the number in Doto inside. Drag round it, the wheel, ←→ a step. Like Dial.qml: while
// it turns it keeps its own v and sends moved(v) once — on release or after 250 ms still; live — on every step (brightness).
// Focused: the label whitens and the unlit dots lift a step. Disabled: 40 %, "—"
Grid {
    id: root

    property real value
    property real from: 0
    property real to: 100
    property real step: 1
    property int n: 34
    property real size: 136
    property real numPx: 44
    property string label
    property string text: enabled ? Math.round(v) : "—"
    property bool live: false
    property bool beside: false // the label right of the arc, not under it
    property real v: value
    signal moved(real v)

    readonly property real dot: size >= 240 ? 8 : size >= 130 ? 5 : 4
    readonly property real rad: size / 2 - dot * 1.7
    readonly property int k: Math.round((v - from) / (to - from) * (n - 1))
    function put(x) {
        x = Math.max(from, Math.min(to, from + Math.round((x - from) / step) * step));
        if (x === v) return;
        v = x;
        if (live) moved(x);
        else wait.restart();
    }
    onValueChanged: if (!area.pressed && !wait.running) v = value
    Timer { id: wait; interval: 250; onTriggered: if (!area.pressed && root.v !== root.value) root.moved(root.v) }

    columns: beside ? 2 : 1
    columnSpacing: 18
    rowSpacing: 12
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
    opacity: enabled ? 1 : 0.4
    activeFocusOnTab: true
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Left) put(v - step);
        else if (e.key === Qt.Key_Right) put(v + step);
        else return;
        e.accepted = true;
    }

    Item {
        width: root.size
        height: root.size

        Repeater {
            model: root.n
            Rectangle {
                required property int index
                readonly property real a: (135 + index / (root.n - 1) * 270) * Math.PI / 180
                readonly property real d: index === root.k ? root.dot * 2.2 : root.dot
                x: root.size / 2 + root.rad * Math.cos(a) - d / 2
                y: root.size / 2 + root.rad * Math.sin(a) - d / 2
                width: d
                height: d
                radius: d / 2
                color: index <= root.k ? Theme.fg : root.activeFocus ? Theme.mute : Theme.s3
            }
        }
        Num {
            anchors.centerIn: parent
            text: root.text
            font.pixelSize: root.numPx
            font.weight: Font.Bold
            font.variableAxes: ({ "ROND": 100, "wght": 700 })
        }

        MouseArea {
            id: area
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            property real last: -1
            // where on the arc: 0 at its start, 1 at its end; the gap at the bottom snaps to the nearer end
            function at(x, y) {
                const c = width / 2;
                if (Math.hypot(x - c, y - c) < width * 0.2) return; // the middle has no angle
                let p = ((Math.atan2(y - c, x - c) * 180 / Math.PI - 135 + 720) % 360) / 270;
                if (p > 1) p = p < 1 + 90 / 270 / 2 ? 1 : 0;
                if (last >= 0 && Math.abs(p - last) > 0.5) p = last > 0.5 ? 1 : 0; // no jumping across the gap
                last = p;
                root.put(root.from + p * (root.to - root.from));
            }
            onPressed: e => {
                last = -1;
                root.forceActiveFocus();
                at(e.x, e.y);
            }
            onPositionChanged: e => at(e.x, e.y)
            onReleased: {
                wait.stop();
                if (root.v !== root.value) root.moved(root.v);
            }
        }
        Notch { onNotch: d => root.put(root.v + d * root.step) }
    }
    Lb { text: root.label; px: 11; color: root.activeFocus ? Theme.fg : Theme.grey }
}
