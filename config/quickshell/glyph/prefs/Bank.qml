import QtQuick
import qs

// local: a bank of console keys joined by 4 px, one lamp lit — a radio. One tab stop: ←→ walk along it, ↵ / space press
// the key under the cursor (a rate or a scale shouldn't change on every arrow), a click presses at once
Row {
    id: root

    property var opts: []
    property int cur: -1
    property real minW: 96
    property int at: 0 // the cursor while it has focus
    signal picked(int i)

    spacing: 4
    activeFocusOnTab: true
    onActiveFocusChanged: if (activeFocus) at = Math.max(0, cur)
    Keys.onPressed: e => {
        const d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0;
        if (d) at = Math.max(0, Math.min(opts.length - 1, at + d));
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) picked(at);
        else return;
        e.accepted = true;
    }

    Repeater {
        model: root.opts
        Key {
            required property var modelData
            required property int index
            text: modelData
            on: index === root.cur
            solo: false
            first: index === 0
            last: index === root.opts.length - 1
            minW: root.minW
            cursor: root.activeFocus && index === root.at
            onHit: {
                root.forceActiveFocus();
                root.at = index;
                root.picked(index);
            }
        }
    }
}
