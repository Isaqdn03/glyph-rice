import QtQuick
import qs

// local: four corner brackets over a frame (the console's modules and its open frame). Sits on the outline: -w/2 out
Item {
    id: root

    property real size: 18
    property real w: 2
    property color color: Theme.grey
    Behavior on color { ColorAnimation { duration: Theme.t } }

    Repeater {
        model: 4
        Item {
            required property int index
            readonly property bool r: index % 2 === 1
            readonly property bool b: index > 1
            x: r ? root.width - root.size + root.w / 2 : -root.w / 2
            y: b ? root.height - root.size + root.w / 2 : -root.w / 2
            width: root.size
            height: root.size
            Rectangle { x: parent.r ? parent.width - root.w : 0; width: root.w; height: parent.height; color: root.color }
            Rectangle { y: parent.b ? parent.height - root.w : 0; width: parent.width; height: root.w; color: root.color }
        }
    }
}
