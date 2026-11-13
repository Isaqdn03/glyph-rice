import QtQuick
import qs
import qs.components
import qs.services

// local: HOME in the console (prefs/Console.qml): the bento as it packs on this screen, 3 × 3. A click picks a tile, another —
// the next kind; drag — swap places. In focus: ←→ pick, shift ←→ move, ↵ next kind, del drop. What didn't fit is named on the
// right. Each screen keeps its own set once it's edited (ctl.edit)
Item {
    id: root

    required property var ctl
    property bool live: false
    readonly property var cells: ctl.cells
    readonly property var placed: cells.filter(c => c.fits)
    readonly property var off: cells.filter(c => !c.fits)
    readonly property var kinds: Object.keys(Theme.kinds)
    property int cur: 0
    readonly property var picked: cells[cur] ?? null
    readonly property string head: `desktop · bento 3 × 3 · ${ctl.mon}`
    onCellsChanged: if (cur >= cells.length) cur = Math.max(0, cells.length - 1)
    Connections { target: root.ctl; function onMonChanged() { root.cur = 0; } }

    function tap(i) {
        grid.forceActiveFocus();
        cur = cur === i ? ctl.cycle("widgets", i, kinds) : i;
    }
    // dropped at point p of the grid: on a widget — its place; on an empty cell — after the last one before it; off the grid — nothing
    function land(i, p) {
        if (p.x < 0 || p.y < 0 || p.x > grid.width || p.y > grid.height) return;
        const at = Math.min(2, Math.floor(p.y / 174)) * 3 + Math.min(2, Math.floor(p.x / 174));
        const hit = placed.find(c => c.row * 3 + c.col <= at && at < c.row * 3 + c.col + c.span);
        const n = placed.filter(c => c.row * 3 + c.col < at).length; // the ones that fit are always the head of the list
        cur = ctl.move("widgets", i, hit ? hit.i : i < n ? n - 1 : n);
    }

    // ---- the grid ----
    Item {
        id: grid
        width: 508
        height: 508
        activeFocusOnTab: true
        Keys.onPressed: e => {
            const c = root.ctl.nav(e, "widgets", root.cur, root.kinds);
            if (c < 0) return;
            root.cur = c;
            e.accepted = true;
        }
        // an empty cell: four rows of unlit dots
        Repeater {
            model: 9
            Grid {
                required property int index
                x: index % 3 * 174
                y: Math.floor(index / 3) * 174
                columns: 4
                padding: 17
                spacing: 34
                Repeater {
                    model: 16
                    Rectangle { width: 6; height: 6; radius: 3; color: Theme.s3 }
                }
            }
        }
        Repeater {
            model: root.placed
            Rectangle {
                id: tile
                required property var modelData // { id, i, row, col, span, fits }
                readonly property bool on: root.cur === modelData.i
                readonly property bool hot: on && grid.activeFocus
                readonly property bool round: modelData.span === 1 && root.ctl.rounds.includes(modelData.id)
                readonly property real dx: drag.activeTranslation.x / root.ctl.zoom // untargeted, the shift is in window px, and the board is scaled
                readonly property real dy: drag.activeTranslation.y / root.ctl.zoom
                x: modelData.col * 174
                y: modelData.row * 174
                z: drag.active ? 1 : 0
                width: modelData.span * 160 + (modelData.span - 1) * 14
                height: 160
                radius: round ? 80 : Theme.corner(28)
                color: hot ? Theme.fg : Theme.s1
                border { width: on ? 2 : 1; color: on ? Theme.fg : Theme.s3 }
                transform: Translate { x: drag.active ? tile.dx : 0; y: drag.active ? tile.dy : 0 }
                Behavior on color { ColorAnimation { duration: Theme.t } }
                Column {
                    x: tile.round ? (parent.width - width) / 2 : 18
                    y: tile.round ? (parent.height - height) / 2 : parent.height - height - 18
                    spacing: 6
                    Lb { anchors.horizontalCenter: tile.round ? parent.horizontalCenter : undefined; text: tile.modelData.id; px: 11; color: tile.hot ? Theme.ink : Theme.fg }
                    Lb { anchors.horizontalCenter: tile.round ? parent.horizontalCenter : undefined; text: tile.modelData.span === 1 ? "1 cell" : `${tile.modelData.span} cells`; px: 10; color: tile.hot ? Theme.ink : Theme.mute }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.tap(tile.modelData.i) }
                // the drop waits for the signal to end: a new list rebuilds the tiles, this one too
                DragHandler {
                    id: drag
                    target: null
                    onActiveChanged: {
                        if (active) {
                            root.cur = tile.modelData.i;
                            return;
                        }
                        const p = grid.mapFromItem(tile.parent, tile.x + tile.width / 2 + tile.dx, tile.y + tile.height / 2 + tile.dy);
                        Qt.callLater(root.land, tile.modelData.i, p);
                    }
                }
            }
        }
    }

    // ---- the numbers ----
    Column {
        x: root.ctl.narrow ? 548 : 580
        width: root.ctl.narrow ? 404 : 600
        Lb { text: "cells used"; px: 13 }
        Row {
            topPadding: 14
            spacing: 10
            D { id: usedN; text: root.ctl.used; font.pixelSize: 140 }
            D { anchors.baseline: usedN.baseline; text: "/9"; font.pixelSize: 50; color: Theme.mute }
        }
        Lb { topPadding: 44; text: "selected"; px: 13 }
        D { topPadding: lead + 14; text: root.picked ? root.picked.id.toUpperCase() : "EMPTY"; font.pixelSize: 52 }
        Lb {
            topPadding: 12
            px: 11
            text: !root.picked ? "↵ adds one" : (root.picked.span === 1 ? "1 cell" : `${root.picked.span} cells`)
                + (root.ctl.rounds.includes(root.picked.id) ? " · round" : "") + " · ↵ next kind · del remove"
        }
        // the cat's gif (services/Gifs), while the cat is selected. Click, or ←→ in focus
        Column {
            id: gifPick
            visible: root.picked?.id === "cat"
            topPadding: 26
            spacing: 12
            ListView {
                id: gifStrip
                width: 404
                height: 58
                orientation: ListView.Horizontal
                spacing: (width - 6 * 58) / 5 // six to a row
                clip: true
                snapMode: ListView.SnapToItem
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                activeFocusOnTab: true
                model: Gifs.list
                currentIndex: Gifs.sel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Left) Gifs.step(-1);
                    else if (e.key === Qt.Key_Right) Gifs.step(1);
                    else return;
                    e.accepted = true;
                }
                delegate: Rectangle {
                    id: th
                    required property string modelData
                    required property int index
                    width: 58
                    height: 58
                    radius: Theme.corner(8)
                    color: Theme.s1
                    border { width: index === Gifs.sel ? 1.5 : 1; color: index === Gifs.sel ? Theme.fg : Theme.s3 }
                    GifDots { anchors { fill: parent; margins: 6 } path: th.modelData; bg: th.color; playing: gifPick.visible && root.live }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            Gifs.pick(th.modelData);
                            gifStrip.forceActiveFocus();
                        }
                    }
                }
            }
            Lb { width: 404; elide: Text.ElideRight; px: 11; color: gifStrip.activeFocus ? Theme.fg : Theme.grey; text: `gif · ${Gifs.name(Gifs.cur)} · ${Gifs.sel + 1} of ${Gifs.list.length}` }
        }
        Lb {
            topPadding: gifPick.visible ? 22 : 44
            width: parent.width
            elide: Text.ElideRight
            px: 11
            color: Theme.mute
            text: !Theme.scr(root.ctl.mon, "home") ? "this screen has no home · display shows it"
                : root.off.length ? `off grid · ${root.off.map(c => c.id).join(" · ")}` : "off grid · none · everything fits"
        }
    }

    // ---- the keys ----
    Column {
        x: root.ctl.narrow ? 1000 : 1250
        spacing: 34
        Block {
            visible: root.ctl.multi
            title: "edit the bento on"
            note: "each screen keeps its own"
            Bank { minW: 84; opts: root.ctl.sorted; cur: root.ctl.sorted.indexOf(root.ctl.mon); onPicked: i => root.ctl.pickMon = root.ctl.sorted[i] }
        }
        Block {
            title: "widgets"
            note: `lamp on = on home · ${root.ctl.used} of 9 cells`
            Flow {
                width: root.ctl.narrow ? 744 : 1106
                spacing: 12
                Repeater {
                    model: root.kinds
                    Key {
                        required property string modelData
                        minW: 162
                        text: modelData + (Theme.kinds[modelData] > 1 ? ` ·${Theme.kinds[modelData]}` : "")
                        on: root.ctl.list("widgets").includes(modelData)
                        onHit: root.cur = root.ctl.flip("widgets", modelData, root.cur)
                    }
                }
            }
        }
    }
}
