import QtQuick
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// local: LIGHTS page of prefs (services/Rgb). Top: the level ring and the switch; colour, when they go dark, and what's
// behind them — a row of dots per part, in the colour it shows now, unlit when it's dark. Under it the Kraken's screen:
// the round panel as it is now (the dial's last frame or the GIF, dimmed like the real one), what it shows, and the GIFs
Column {
    id: root

    readonly property var st: Rgb.store
    readonly property var hours: [[], [22, 7], [23, 7], [0, 8]]
    readonly property var screens: ["dial", "gif", "liquid"]
    readonly property var gifs: Gifs.list.filter(p => p)
    readonly property string caption: "lights · " + (!Rgb.parts.length ? "openrgb isn't answering"
        : !st.on ? "off" : Rgb.gaming ? "dark · game mode" : Rgb.night ? "dark · night hours" : `#${Rgb.hex.toLowerCase()} · ${st.level} %`)

    spacing: 44

    Row {
        spacing: 70

        Column {
            spacing: 22
            Dial { anchors.horizontalCenter: parent.horizontalCenter; size: 280; n: 52; label: "level"; value: root.st.level; onMoved: v => root.st.level = Math.round(v) }
            Toggle { anchors.horizontalCenter: parent.horizontalCenter; text: "lights"; on: root.st.on; onFlip: root.st.on = !root.st.on }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 22
            Pick { label: "colour"; opts: ["accent", "white"]; cur: root.st.white ? 1 : 0; onPicked: i => root.st.white = i === 1 }
            Pick {
                label: "dark at night"
                opts: ["never", "22 → 7", "23 → 7", "0 → 8"]
                cur: root.hours.findIndex(h => h.length === (root.st.night || []).length && h.every((x, j) => x === root.st.night[j]))
                onPicked: i => root.st.night = root.hours[i]
            }
            Toggle { text: "dark in a game"; on: root.st.gameDark; onFlip: root.st.gameDark = !root.st.gameDark }

            Column {
                topPadding: 8
                spacing: 16
                Repeater {
                    model: Rgb.parts
                    Row {
                        id: part
                        required property var modelData
                        Lb { width: 110; anchors.verticalCenter: parent.verticalCenter; text: part.modelData.name }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Repeater {
                                model: part.modelData.n
                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: Rgb.lit ? Rgb.base : Theme.s3
                                    opacity: Rgb.lit ? 0.3 + 0.7 * Rgb.gain : 1
                                    Behavior on color { ColorAnimation { duration: Theme.t } }
                                    Behavior on opacity { NumberAnimation { duration: Theme.t } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- the Kraken's screen ----
    Row {
        visible: Rgb.screen
        spacing: 70

        // the panel itself: what's on it now. NZXT's own screen we can't see — a word instead
        ClippingRectangle {
            width: 280
            height: 280
            radius: 140
            color: Theme.bg
            border { width: 1; color: Theme.s3 }
            Item {
                anchors.fill: parent
                opacity: Rgb.lit ? 0.35 + 0.65 * root.st.level / 100 : 0.15
                Behavior on opacity { NumberAnimation { duration: Theme.t } }
                Image {
                    anchors.fill: parent
                    visible: Rgb.shown === "dial"
                    source: Rgb.frame ? `file://${Rgb.framePath}?${Rgb.frame}` : ""
                    cache: false
                    asynchronous: true
                    smooth: true
                }
                AnimatedImage {
                    anchors.fill: parent
                    visible: Rgb.shown === "gif"
                    source: Rgb.shown === "gif" ? Gifs.url(Rgb.gif) : ""
                    fillMode: Image.PreserveAspectCrop
                    playing: visible && root.visible
                }
            }
            Lb { anchors.centerIn: parent; visible: Rgb.mode === "liquid"; text: "nzxt · liquid" }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 22
            Pick {
                label: "screen"
                opts: ["dial", "gif", "nzxt"]
                cur: root.screens.indexOf(Rgb.mode)
                onPicked: i => root.st.screen = root.screens[i]
            }
            Lb {
                visible: Rgb.mode === "dial"
                text: "cpu and gpu · temperature in dots · load round the ring"
            }
            // the gif folder (services/Gifs, the same one home's cat uses). Click or ←→ in focus
            Column {
                visible: Rgb.mode === "gif" || root.st.screen === "gif"
                spacing: 12
                Lb {
                    width: 404
                    elide: Text.ElideRight
                    text: !root.gifs.length ? `no gifs in ${Gifs.dir}` : Rgb.shown !== Rgb.mode ? `gif · ${Gifs.name(Rgb.gif)} · can't play it · the dial meanwhile`
                        : `gif · ${Gifs.name(Rgb.gif)} · ${root.gifs.indexOf(Rgb.gif) + 1} of ${root.gifs.length}`
                    color: strip.activeFocus ? Theme.fg : Theme.grey
                }
                ListView {
                    id: strip
                    readonly property int sel: root.gifs.indexOf(Rgb.gif)
                    function step(d) { if (root.gifs.length) root.st.gif = root.gifs[(sel + d + root.gifs.length) % root.gifs.length]; }
                    width: 404
                    height: 58
                    orientation: ListView.Horizontal
                    spacing: (width - 6 * 58) / 5 // six to a row
                    clip: true
                    snapMode: ListView.SnapToItem
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: false
                    activeFocusOnTab: true
                    model: root.gifs
                    currentIndex: sel
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Left) step(-1);
                        else if (e.key === Qt.Key_Right) step(1);
                        else return;
                        e.accepted = true;
                    }
                    delegate: Rectangle {
                        id: th
                        required property string modelData
                        required property int index
                        readonly property bool on: index === strip.sel
                        width: 58
                        height: 58
                        radius: Theme.corner(width * 0.18)
                        color: Theme.s1
                        border { width: on ? 2 : 1; color: on ? Theme.fg : Theme.s2 }
                        GifDots { anchors { fill: parent; margins: 6 } path: th.modelData; bg: th.color; playing: strip.visible && root.visible }
                        TapHandler {
                            onTapped: {
                                root.st.gif = th.modelData;
                                strip.forceActiveFocus();
                            }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
    }
}
