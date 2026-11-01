import QtQuick
import qs
import qs.components

// образец (Theme.styles): круг fill, в нём акцент (dot), под ним имя; amount — кольцо точек вокруг, доля цвета у варианта, как
// Glyph-шкала. Фокус — белое кольцо, что стоит — точка в центре. Клик, ↵, пробел — поставить, ←→ — соседний. Наведение
// ставит фокус, как в Power: курсор один, ↵ ставит то, что на макете. peek — в фокусе: STYLE рисует его палитру на макете
Column {
    id: root

    property var item: ({ name: "" })
    property real size: 56
    readonly property bool peek: activeFocus

    width: 96
    spacing: 8
    activeFocusOnTab: true
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) item.run();
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Right) nextItemInFocusChain(e.key === Qt.Key_Right)?.forceActiveFocus();
        else return;
        e.accepted = true;
    }

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.size + 28
        height: width
        Ring {
            visible: root.item.amount !== undefined
            anchors.fill: parent
            n: visible ? 24 : 0 // кольцо — только у вариантов, остальным не держать 24 точки
            dot: 3
            f: root.item.amount ?? 0
            on: root.item.dot ?? Theme.fg
        }
        Rectangle {
            anchors.centerIn: parent
            width: root.size + 14
            height: width
            radius: width / 2
            color: "transparent"
            border { width: 2; color: root.activeFocus ? Theme.fg : "transparent" }
        }
        Rectangle {
            id: disc
            anchors.centerIn: parent
            width: root.size
            height: width
            radius: width / 2
            color: root.item.fill ?? Theme.s2
            border { width: 1; color: Theme.s3 } // чёрный образец на чёрном
            Behavior on color { ColorAnimation { duration: Theme.t } }
            Rectangle {
                id: inner
                visible: !!root.item.dot
                anchors.centerIn: parent
                width: Math.round(root.size * 0.46)
                height: width
                radius: width / 2
                color: root.item.dot ?? "transparent"
                Behavior on color { ColorAnimation { duration: Theme.t } }
            }
            Rectangle { visible: !!root.item.now; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.on(inner.visible ? inner.color : disc.color) }
        }
        TapHandler { onTapped: { root.forceActiveFocus(); root.item.run(); } }
        HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.forceActiveFocus() }
    }
    Lb {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        px: 10
        text: root.item.name
        color: root.activeFocus || root.item.now ? Theme.fg : Theme.grey
    }
}
