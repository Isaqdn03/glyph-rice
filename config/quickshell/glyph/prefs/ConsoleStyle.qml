import QtQuick
import qs
import qs.components

// local: STYLE in the console (prefs/Console.qml): where each colour of the palette lands, and its terminal — of the swatch under
// the pointer or in focus, else the one on now. Right: where colour comes from, the theme, then what that source offers: the
// wallpaper's tones and variants, or the palettes by group (Theme.styles, the same as the launcher's style). Swatches go by index,
// so a pick doesn't rebuild them and focus stays
Item {
    id: root

    signal wallRequested
    property bool narrow: false // the console's narrow board: smaller swatches, the keys closer
    property Item hot: null // the swatch under the pointer or in focus
    readonly property var p: hot?.it?.pal ?? Theme.pal
    readonly property var c: p.c
    readonly property string paint: Theme.state.paint
    readonly property bool wall: paint === "wall" && Theme.tones.length > 0
    readonly property string name: hot?.it?.name ?? (paint === "scheme" ? (Theme.pal.group === "more" ? "" : Theme.pal.group + " ") + Theme.pal.name : wall ? Theme.pal.name : "nothing")
    readonly property string from: hot ? "↵ sets it" : paint === "scheme" ? "palette" : wall ? "from the wallpaper" : "black · white dots · one red"
    readonly property string head: `desktop · ${paint === "scheme" ? (Theme.pal.group === "more" ? "" : Theme.pal.group + " ") + Theme.pal.name : wall ? Theme.pal.name : "nothing"} · ${Theme.light ? "light" : "dark"}`
    function block(h) { return Theme.styles.find(b => b.head === h)?.items ?? []; }
    function peek(sw) {
        if (sw.peek) hot = sw;
        else if (hot === sw) hot = null;
    }

    // ---- where each colour lands ----
    Lb { text: "where each colour lands"; px: 13; color: Theme.fg }
    Row {
        y: 32
        spacing: 12
        Repeater {
            model: [
                { n: "fg", i: 6, where: "text · focus · border" },
                { n: "s1", i: 1, where: "bar · panels · kitty" },
                { n: "s3", i: 3, where: "lines · selection · off" },
                { n: "bg", i: 0, where: "wallpaper" },
                { n: "accent", k: "accent", where: "the one live thing" },
                { n: "red", k: "red", where: "alarm" },
                { n: "mute", i: 4, where: "unlit · hints" }
            ]
            Column {
                id: slot
                required property var modelData
                readonly property color col: modelData.k ? root.p[modelData.k] : root.c[modelData.i]
                width: root.narrow ? 112 : 150
                spacing: 10
                Rectangle {
                    width: root.narrow ? 96 : 110
                    height: width
                    radius: width / 2
                    color: slot.col
                    border { width: 1; color: Theme.s3 }
                    Behavior on color { ColorAnimation { duration: Theme.t } }
                }
                Lb { topPadding: 8; text: slot.modelData.n; px: 13; color: Theme.fg }
                Lb { text: "#" + Theme.hex(slot.col); px: 11 }
                Lb { width: parent.width; wrapMode: Text.WordWrap; text: slot.modelData.where; px: 10; color: Theme.mute }
            }
        }
    }
    Row {
        y: 330
        spacing: 60
        Column {
            anchors.bottom: parent.bottom
            spacing: 12
            Lb { text: "terminal · 16"; px: 11 }
            Grid {
                columns: 8
                Repeater {
                    model: 16
                    Rectangle {
                        required property int index
                        width: 44
                        height: 26
                        color: root.p.ansi[index]
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                    }
                }
            }
        }
        Column {
            anchors.bottom: parent.bottom
            spacing: 12
            D { width: root.narrow ? 448 : 760; elide: Text.ElideRight; text: root.name.toUpperCase(); font.pixelSize: 52 }
            Lb { text: root.from; px: 11 }
        }
    }
    Lb { y: 500; px: 11; color: Theme.mute; text: "hover a swatch to see where its colours land · leave and it comes back" }

    // ---- the keys ----
    Column {
        x: root.narrow ? 910 : 1250
        spacing: 26
        Row {
            spacing: root.narrow ? 32 : 40
            Block {
                title: "colour from"
                Bank {
                    minW: 110
                    opts: ["nothing", "wall", "palette"]
                    cur: ["", "wall", "scheme"].indexOf(Theme.state.paint)
                    onPicked: i => Theme.state.paint = ["", "wall", "scheme"][i]
                }
            }
            Block {
                title: "theme"
                Bank { minW: 110; opts: ["dark", "light"]; cur: Theme.light ? 1 : 0; onPicked: i => Theme.setLight(i === 1) }
            }
            Block {
                title: "wallpaper"
                Key {
                    minW: 200
                    mom: true
                    text: "wallpapers ›"
                    onHit: root.wallRequested()
                }
            }
        }
        Block {
            visible: !Theme.state.paint
            title: "nothing to pick"
            note: "black · white dots · one red"
        }
        // a wallpaper without colour: the same words the old page had
        Block {
            visible: Theme.state.paint === "wall" && !Theme.tones.length
            title: "no colour in it"
            note: "pick another wallpaper"
        }
        Block {
            visible: root.wall
            title: "tones"
            note: "from the wallpaper"
            Flow {
                width: root.narrow ? 834 : 1106
                spacing: 12
                Repeater {
                    model: root.block("tones").length
                    Swatch { list: root.block("tones"); byFill: true }
                }
            }
        }
        Block {
            visible: root.wall
            title: "variant"
            note: "how much colour"
            Flow {
                width: root.narrow ? 834 : 1106
                spacing: 12
                Repeater {
                    model: root.block("variant").length
                    Swatch { list: root.block("variant"); minW: 202 }
                }
            }
        }
        // the palettes, a row per group
        Repeater {
            model: Theme.state.paint === "scheme" ? Theme.styles.length - 2 : 0
            Row {
                id: grp
                required property int index
                readonly property var b: Theme.styles[index + 1] ?? ({ head: "", items: [] })
                spacing: 20
                Lb { anchors.verticalCenter: parent.verticalCenter; width: 150; text: grp.b.head; px: 13; color: Theme.fg }
                Flow {
                    width: (root.narrow ? 834 : 1106) - 170
                    spacing: 12
                    Repeater {
                        model: grp.b.items.length
                        Swatch { list: grp.b.items }
                    }
                }
            }
        }
    }

    component Swatch: Key {
        required property int index
        property var list: []
        property bool byFill: false // a tone shows the tone itself, not the accent it makes
        readonly property var it: list[index] ?? ({ name: "" })
        readonly property bool peek: activeFocus || hovered
        text: it.name
        chip: (byFill ? it.fill : it.dot) ?? Theme.s3
        on: !!it.now
        onPeekChanged: root.peek(this)
        onHit: it.run?.()
    }
}
