import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// local: LIGHTS in the console (prefs/Console.qml, services/Rgb, services/Govee). Left: the level, then the thing itself —
// the Kraken's round panel as it is now and the parts that answered, or, for the lamp, its tall bar in the colour it reports;
// a strip in the colour they show. Right: the switch, which light, its colour, when it goes dark, what the panel shows.
// Same settings as prefs/Lights.qml and prefs/Lamp.qml, one layout for both
Item {
    id: root

    property bool live: false
    property int view: 0
    readonly property bool lamp: view === 1 && Govee.seen
    readonly property var st: lamp ? Govee.store : Rgb.store
    readonly property var s: Govee.status
    readonly property bool barOn: Govee.found && !!s && s.on

    readonly property var hours: [[], [22, 7], [23, 7], [0, 8]]
    readonly property var screens: ["dial", "gif", "liquid"]
    readonly property var modes: lamp ? ["case", "palette", "white", "screen"] : ["accent", "palette", "white", "screen"]
    readonly property string tone: lamp ? st.source : Rgb.tone
    // screen follows: auto (a fullscreen window's monitor, else the focused one) or one monitor, by connector
    readonly property var mons: [""].concat(Quickshell.screens.map(x => x.name))
    readonly property var gifs: Gifs.list.filter(p => p)

    readonly property string caseState: !Rgb.parts.length ? "openrgb isn't answering"
        : !st.on ? "off" : Rgb.gaming ? "dark · game mode" : Rgb.night ? "dark · night hours"
        : Rgb.tone === "screen" ? (Rgb.liveErr ? `screen · ${Rgb.liveErr}` : Rgb.liveUp ? `screen · ${Rgb.capMon} · live` : "screen · starting the capture")
        : `${Rgb.tone === "palette" ? Rgb.pick.name : Rgb.tone} #${Rgb.hex.toLowerCase()} · ${st.level} %`
    readonly property string lampState: !Govee.found ? (Govee.seen ? "not answering" : "looking for it on the network")
        : !st.on ? "off" : Govee.gaming ? "dark · game mode" : Govee.night ? "dark · night hours"
        : !s ? "…" : !s.on ? "off · from the lamp" : `${s.kelvin ? s.kelvin + " k" : "#" + (s.rgb ?? "").toLowerCase()} · ${s.level} %`
    readonly property string head: "more · " + (lamp ? "lamp · " + lampState : "case · " + caseState)

    readonly property color shows: lamp ? (barOn ? Govee.now : Theme.s3) : Rgb.lit ? Rgb.base : Theme.s3

    // ---- what it sets, left ----
    // on the screen the lamp has a level of its own (the room's stays for after)
    Knob {
        size: 300
        n: 44
        numPx: 96
        from: root.lamp ? 1 : 0
        label: root.lamp && Govee.onScreen ? "level · screen · drag round" : "level · drag round"
        dim: !root.st.on
        value: root.lamp && Govee.onScreen ? root.st.screenLevel : root.st.level
        onMoved: v => {
            if (root.lamp && Govee.onScreen) root.st.screenLevel = Math.round(v);
            else root.st.level = Math.round(v);
        }
    }

    // the Kraken's panel: what's on it now, dimmed like the real one. NZXT's own screen we can't see — a word instead
    Column {
        x: 380
        visible: !root.lamp
        spacing: 18
        ClippingRectangle {
            width: 300
            height: 300
            radius: 150
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            Item {
                anchors.fill: parent
                opacity: Rgb.lit ? 0.35 + 0.65 * Rgb.store.level / 100 : 0.15
                Behavior on opacity { NumberAnimation { duration: Theme.t } }
                Image {
                    anchors.fill: parent
                    visible: Rgb.screen && Rgb.shown === "dial"
                    source: root.live && Rgb.frame ? `file://${Rgb.framePath}?${Rgb.frame}` : ""
                    cache: false
                    asynchronous: true
                    smooth: true
                }
                AnimatedImage {
                    anchors.fill: parent
                    visible: Rgb.shown === "gif"
                    source: root.live && Rgb.shown === "gif" ? Gifs.url(Rgb.gif) : ""
                    fillMode: Image.PreserveAspectCrop
                    playing: visible && root.live
                }
            }
            Lb {
                anchors.centerIn: parent
                visible: !Rgb.screen || Rgb.mode === "liquid"
                text: Rgb.screen ? "nzxt's own screen" : "no kraken"
            }
        }
        Lb {
            anchors.horizontalCenter: parent.horizontalCenter
            px: 11
            text: !Rgb.screen ? "kraken lcd" : Rgb.shown !== Rgb.mode ? `kraken lcd · can't play ${Gifs.name(Rgb.gif)} · the dial meanwhile`
                : `kraken lcd · ${Rgb.mode === "liquid" ? "nzxt" : Rgb.mode}`
        }
    }

    // the lamp: a corner lamp is a tall bar of light, in the colour it reports, as bright as it is — whoever set it
    Column {
        x: 500
        visible: root.lamp
        spacing: 6
        Repeater {
            model: 28
            Row {
                spacing: 6
                Repeater {
                    model: 2
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: root.barOn ? Govee.now : Theme.s3
                        opacity: root.barOn ? 0.3 + 0.7 * root.s.level / 100 : 1
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                        Behavior on opacity { NumberAnimation { duration: Theme.t } }
                    }
                }
            }
        }
    }

    // what answered: each part a row of dots in the colour it shows
    Column {
        x: 760
        width: 420
        Lb { height: 34; text: root.lamp ? "the lamp" : "parts that answered"; px: 13; color: Theme.fg }
        Repeater {
            model: root.lamp ? [{ name: "model", how: Govee.store.sku || "—" }, { name: "address", how: Govee.ip || "—" },
                                { name: "reports", how: root.lampState }] : Rgb.parts
            Rectangle {
                id: part
                required property var modelData
                readonly property string how: modelData.how ?? (modelData.note ? modelData.note
                    : modelData.name === "kraken" ? `liquidctl · ${modelData.n} fan${modelData.n === 1 ? "" : "s"}`
                    : modelData.name === "keyboard" ? "via" : `openrgb · ${modelData.n}`)
                width: parent.width
                height: 56
                color: "transparent"
                Rectangle { width: parent.width; height: 1; color: Theme.s2 }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 18
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.lamp
                        width: 50
                        spacing: 6
                        Repeater {
                            model: part.modelData.n ?? 0
                            Rectangle {
                                width: 11
                                height: 11
                                radius: 5.5
                                color: root.shows
                                Behavior on color { ColorAnimation { duration: Theme.t } }
                            }
                        }
                    }
                    Lb { anchors.verticalCenter: parent.verticalCenter; width: 104; text: part.modelData.name; px: 13; color: Theme.fg }
                    Lb { anchors.verticalCenter: parent.verticalCenter; text: part.how; px: 10; color: Theme.mute }
                }
            }
        }
    }

    // the colour they show now, as bright as they're set
    Row {
        y: 410
        spacing: 12
        Repeater {
            model: 38
            Rectangle {
                width: 18
                height: 18
                radius: 9
                color: root.shows
                opacity: root.lamp ? (root.barOn ? 0.3 + 0.7 * root.s.level / 100 : 1) : Rgb.lit ? 0.3 + 0.7 * Rgb.gain : 1
                Behavior on color { ColorAnimation { duration: Theme.t } }
                Behavior on opacity { NumberAnimation { duration: Theme.t } }
            }
        }
    }
    Lb { y: 446; px: 11; text: "now · " + (root.lamp ? root.lampState : root.caseState) }

    // ---- the keys, right ----
    Column {
        x: 1250
        width: 540
        spacing: 36
        Block {
            title: "output"
            Key { minW: 240; text: root.lamp ? "lamp" : "lights"; on: root.st.on; onHit: root.st.on = !on }
        }
        // the switch shows once a lamp has answered
        Block {
            visible: Govee.seen
            title: "control"
            Bank { minW: 120; opts: ["case", "lamp"]; cur: root.view; onPicked: i => root.view = i }
        }
        Block {
            title: "colour"
            Bank {
                minW: 120
                opts: root.modes
                cur: root.modes.indexOf(root.tone)
                onPicked: i => root.st.source = root.modes[i]
            }
            // a picked colour or white lights the lamp too
            Hues {
                visible: root.tone === "palette"
                items: Rgb.palette
                cur: Rgb.palette.findIndex(p => p.name === root.st.color)
                onPicked: i => {
                    root.st.color = Rgb.palette[i].name;
                    if (root.lamp) root.st.on = true;
                }
            }
            // the case has no white LEDs, these are tints — the lamp does them for real
            Hues {
                visible: root.tone === "white"
                items: Rgb.whites.map(k => ({ name: k + " k", color: Rgb.tint(k) }))
                cur: Rgb.whites.indexOf(root.st.kelvin)
                onPicked: i => {
                    root.st.kelvin = Rgb.whites[i];
                    if (root.lamp) root.st.on = true;
                }
            }
            // one live colour from the monitor; the keyboard and a lamp on "case" go along
            Bank {
                visible: !root.lamp && root.tone === "screen"
                minW: 120
                opts: ["auto"].concat(Quickshell.screens.map(x => (x.model || x.name).toLowerCase().split(" ")[0]))
                cur: root.mons.indexOf(Rgb.store.follow)
                onPicked: i => Rgb.store.follow = root.mons[i]
            }
            Lb {
                visible: root.lamp && root.tone === "case"
                px: 11
                color: Theme.mute
                text: "the case lights' " + (Rgb.tone === "white" ? `white · ${Rgb.store.kelvin} k on its white leds`
                    : Rgb.tone === "palette" ? `colour · ${Rgb.pick.name}` : Rgb.tone === "screen" ? "colour · the screen, live" : "colour · the style's accent")
            }
        }
    }
    Column {
        x: 1850
        width: 506
        spacing: 36
        Block {
            title: "go dark at night"
            Bank {
                minW: 84
                opts: ["never", "22→7", "23→7", "0→8"]
                cur: root.hours.findIndex(h => h.length === (root.st.night || []).length && h.every((x, j) => x === root.st.night[j]))
                onPicked: i => root.st.night = root.hours[i]
            }
        }
        Block {
            title: "go dark"
            Key { text: "in a game"; on: root.st.gameDark; onHit: root.st.gameDark = !on }
        }
        Block {
            visible: !root.lamp && Rgb.screen
            title: "kraken lcd"
            Bank {
                minW: 84
                opts: ["dial", "gif", "nzxt"]
                cur: root.screens.indexOf(Rgb.mode)
                onPicked: i => Rgb.store.screen = root.screens[i]
            }
            // the gif folder (services/Gifs, the same one home's cat uses). Click or ←→ in focus
            ListView {
                id: gifRow
                readonly property int sel: root.gifs.indexOf(Rgb.gif)
                visible: Rgb.store.screen === "gif"
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
                    const n = root.gifs.length, d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0;
                    if (!d || !n) return;
                    Rgb.store.gif = root.gifs[(sel + d + n) % n];
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
                    border { width: index === gifRow.sel ? 1.5 : 1; color: index === gifRow.sel ? Theme.fg : Theme.s3 }
                    GifDots { anchors { fill: parent; margins: 6 } path: th.modelData; bg: th.color; playing: gifRow.visible && root.live }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            Rgb.store.gif = th.modelData;
                            gifRow.forceActiveFocus();
                        }
                    }
                }
            }
            Lb {
                visible: gifRow.visible
                width: 404
                elide: Text.ElideRight
                px: 11
                color: gifRow.activeFocus ? Theme.fg : Theme.grey
                text: !root.gifs.length ? `no gifs in ${Gifs.dir}` : `${Gifs.name(Rgb.gif)} · ${gifRow.sel + 1} of ${root.gifs.length}`
            }
        }
    }
}
