import QtQuick
import qs

// local: a list that slides open under its row instead of popping in. value — what's showing ("" — folded);
// held keeps the last value while it folds away, so the content doesn't blank mid-fold. pad is the gap above,
// folded along with it (a Column's spacing would jump in and out)
Item {
    id: f
    property string value
    property string held
    property real pad: 16
    default property alias content: box.data

    onValueChanged: if (value) held = value
    width: parent?.width ?? 0
    height: value ? box.height + pad : 0
    clip: true
    visible: height > 0
    onHeightChanged: if (!value && height <= 0) held = ""
    Behavior on height { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    Item {
        id: box
        y: f.pad
        width: f.width
        height: childrenRect.height
    }
}
