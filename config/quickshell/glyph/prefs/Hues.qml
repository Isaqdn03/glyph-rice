import QtQuick
import qs
import qs.components

// local: a row of colour dots for LIGHTS (the case and the lamp): click one, or ←→ while the row has focus. The chosen one
// carries a dot in the middle and a ring while the row is focused; its name sits at the end
Row {
    id: root

    property var items: [] // [{ name, color }]
    property int cur: -1
    signal picked(int i)

    spacing: 12
    activeFocusOnTab: true
    Keys.onPressed: e => {
        const n = items.length;
        if (e.key === Qt.Key_Left) picked((Math.max(cur, 0) + n - 1) % n);
        else if (e.key === Qt.Key_Right) picked((cur + 1) % n);
        else return;
        e.accepted = true;
    }

    Repeater {
        model: root.items
        Item {
            id: hue
            required property var modelData
            required property int index
            readonly property bool on: index === root.cur
            width: 26
            height: 38
            Rectangle {
                anchors.centerIn: parent
                width: 38
                height: 38
                radius: 19
                color: "transparent"
                border { width: 2; color: hue.on && root.activeFocus ? Theme.fg : "transparent" }
            }
            Rectangle {
                id: disc
                anchors.centerIn: parent
                width: 26
                height: 26
                radius: 13
                color: hue.modelData.color
                border { width: 1; color: Theme.s3 }
                Behavior on color { ColorAnimation { duration: Theme.t } }
                Rectangle { visible: hue.on; anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.on(disc.color) }
            }
            TapHandler {
                onTapped: {
                    root.forceActiveFocus();
                    root.picked(hue.index);
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }
    Lb {
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: 6
        text: root.items[root.cur]?.name ?? ""
        color: root.activeFocus ? Theme.fg : Theme.grey
    }
}
