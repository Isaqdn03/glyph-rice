import QtQuick
import QtQuick.Effects
import qs
import qs.components

// local: a console key (prefs/Console.qml) — hardware, not a pill: s1 with a hairline, a 28 × 4 lamp top-left, the label
// bottom-left. On: the key lifts to s2, the label whitens, the lamp lights with a faint glow — the only glow in prefs, as on
// a VFD only lit segments glow. mom: momentary, hollow — a press does a thing once (reload, hypr config). Disabled: 40 %.
// chip: a swatch — the lamp is a 40 × 8 chip of that colour, no glow, on = a white outline. shift ←→ asks to move it (shifted).
// ↵ / space / click press it. In a Bank (solo false) the bank takes focus and only its outer corners round
Rectangle {
    id: root

    property string text
    property bool on
    property bool mom
    property bool solo: true   // its own tab stop
    property bool first: true  // round on the left (a bank's first key)
    property bool last: true   // round on the right
    property bool cursor       // a bank's ←→ position while the bank has focus
    property real minW: 150
    property color chip: "transparent"
    readonly property bool swatch: chip.a > 0
    readonly property alias hovered: hov.hovered
    signal hit
    signal shifted(int d)

    readonly property bool ring: activeFocus || cursor || swatch && on
    readonly property real r: Theme.corner(8)

    implicitWidth: Math.max(minW, lab.implicitWidth + 32)
    implicitHeight: 72
    topLeftRadius: first ? r : 0
    bottomLeftRadius: first ? r : 0
    topRightRadius: last ? r : 0
    bottomRightRadius: last ? r : 0
    color: mom ? "transparent" : on ? Theme.s2 : Theme.s1
    border { width: ring ? 1.5 : 1; color: ring ? Theme.fg : hov.hovered || mom ? Theme.mute : Theme.s3 }
    opacity: enabled ? 1 : 0.4
    Behavior on color { ColorAnimation { duration: Theme.t } }

    activeFocusOnTab: solo
    Keys.onPressed: e => {
        if (e.modifiers & Qt.ShiftModifier && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
            root.shifted(e.key === Qt.Key_Left ? -1 : 1);
            e.accepted = true;
            return;
        }
        if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
        root.hit();
        e.accepted = true;
    }

    RectangularShadow {
        anchors.fill: lamp
        visible: root.on && !root.mom && !root.swatch
        radius: 2
        blur: 10
        color: Theme.fade(Theme.fg, 0.55)
    }
    Rectangle {
        id: lamp
        x: 16
        y: 13
        width: root.swatch ? 40 : 28
        height: root.swatch ? 8 : 4
        radius: 2
        color: root.swatch ? root.chip : root.mom ? "transparent" : root.on ? Theme.fg : Theme.s3
        border { width: root.mom ? 1 : 0; color: Theme.mute }
        Behavior on color { ColorAnimation { duration: Theme.t } }
    }
    Lb {
        id: lab
        x: 16
        anchors { bottom: parent.bottom; bottomMargin: 11 }
        text: root.text
        px: 13
        font.letterSpacing: px * 0.12
        color: root.on || root.mom ? Theme.fg : Theme.grey
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        onTapped: {
            if (root.solo) root.forceActiveFocus();
            root.hit();
        }
    }
}
