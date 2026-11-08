import QtQuick
import qs
import qs.components

// local: one module on the console wall (prefs/Console.qml): a hairline frame with corner brackets, `a1 · name` in
// Space Mono, one status dot (unlit; the accent, breathing, only on the selected one) and a body — a tiny instrument and
// the section's live numbers. Hover lifts the outline a step, a click opens it
Item {
    id: root

    property string tag   // where it sits on the wall, a1…e3
    property string name
    property string extra // after the name, mute: "· hyprland"
    property bool on      // selected
    default property alias body: body.data
    signal opened
    readonly property bool hot: hov.hovered

    width: 458
    height: 267

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border { width: root.on ? 1.5 : 1; color: root.on ? Theme.fg : root.hot ? Theme.mute : Theme.s2 }
        Behavior on border.color { ColorAnimation { duration: Theme.t } }
    }
    Brackets { anchors.fill: parent; color: root.on ? Theme.fg : Theme.grey }

    Row {
        x: 20
        y: 16
        spacing: 14
        Lb { text: root.tag; px: 13; color: Theme.mute }
        Lb { text: root.name; px: 13; color: Theme.fg }
        Lb { visible: !!root.extra; text: root.extra; px: 13; color: Theme.mute }
    }
    Rectangle {
        id: led
        anchors { right: parent.right; rightMargin: 20 }
        y: 22
        width: 8
        height: 8
        radius: 4
        color: root.on ? Theme.accent : Theme.s3
        SequentialAnimation on opacity {
            running: root.on && root.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running) led.opacity = 1
            NumberAnimation { to: 0.3; duration: 1200; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 1200; easing.type: Easing.InOutSine }
        }
    }

    Item {
        id: body
        x: 20
        y: 58
        width: parent.width - 40
        height: parent.height - 76
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.opened() }
}
