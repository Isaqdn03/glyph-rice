import QtQuick
import qs
import qs.components
import qs.services

// local: LIGHTS → lamp (services/Govee). Left, the lamp as it is now — a tall column of dots in the colour it reports,
// as bright as it is, whoever set it (the phone too). Then its level and switch; right, what colour it takes — the case
// lights', one from the palette, a white (prefs/Hues) — and when it goes dark
Row {
    id: root

    readonly property var st: Govee.store
    readonly property var hours: [[], [22, 7], [23, 7], [0, 8]]
    readonly property var sources: ["case", "palette", "white", "screen"]
    readonly property var s: Govee.status
    readonly property string caption: "lamp · " + (!Govee.found ? (Govee.seen ? "not answering" : "looking for it on the network")
        : !st.on ? "off" : Govee.gaming ? "dark · game mode" : Govee.night ? "dark · night hours"
        : !s ? "…" : !s.on ? "off · from the lamp" : `${s.kelvin ? s.kelvin + " k" : "#" + (s.rgb ?? "").toLowerCase()} · ${s.level} %`)

    spacing: 64

    // the lamp: a corner lamp is a tall bar of light
    Column {
        id: bar
        readonly property bool on: Govee.found && !!root.s && root.s.on
        anchors.verticalCenter: parent.verticalCenter
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
                        color: bar.on ? Govee.now : Theme.s3
                        opacity: bar.on ? 0.3 + 0.7 * root.s.level / 100 : 1
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                        Behavior on opacity { NumberAnimation { duration: Theme.t } }
                    }
                }
            }
        }
    }

    Column {
        spacing: 22
        // on the screen it has a level of its own (the room's stays for after)
        Dial {
            anchors.horizontalCenter: parent.horizontalCenter
            size: 280
            n: 52
            from: 1
            label: Govee.onScreen ? "level · screen" : "level"
            value: Govee.onScreen ? root.st.screenLevel : root.st.level
            onMoved: v => {
                if (Govee.onScreen) root.st.screenLevel = Math.round(v);
                else root.st.level = Math.round(v);
            }
        }
        Toggle { anchors.horizontalCenter: parent.horizontalCenter; text: "lamp"; on: root.st.on; onFlip: root.st.on = !root.st.on }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 22
        Pick { label: "colour"; opts: root.sources; cur: root.sources.indexOf(root.st.source); onPicked: i => root.st.source = root.sources[i] }

        // case: whatever the case lights show — their white on the lamp's own white LEDs
        Lb {
            visible: root.st.source === "case"
            text: "the case lights' " + (Rgb.tone === "white" ? `white · ${Rgb.store.kelvin} k on its white leds`
                : Rgb.tone === "palette" ? `colour · ${Rgb.pick.name}` : Rgb.tone === "screen" ? "colour · the screen, live"
                : "colour · the style's accent")
        }
        // screen: live, about ten colours a second — the lamp fades between them itself
        Lb {
            visible: root.st.source === "screen"
            text: Rgb.liveErr ? `screen · ${Rgb.liveErr}` : Govee.streaming ? `the screen, live · ${Rgb.capMon}${Govee.zones ? ` · ${Govee.zones} zones, its top the screen's top` : ""} · up to ${root.st.screenLevel} %`
                : Govee.lit ? "the screen · starting the capture" : "the screen · dark now"
        }
        // a colour or a white picked lights the lamp too
        Hues {
            visible: root.st.source === "palette"
            items: Rgb.palette
            cur: Rgb.palette.findIndex(p => p.name === root.st.color)
            onPicked: i => {
                root.st.color = Rgb.palette[i].name;
                root.st.on = true;
            }
        }
        Hues {
            visible: root.st.source === "white"
            items: Rgb.whites.map(k => ({ name: k + " k", color: Rgb.tint(k) }))
            cur: Rgb.whites.indexOf(root.st.kelvin)
            onPicked: i => {
                root.st.kelvin = Rgb.whites[i];
                root.st.on = true;
            }
        }

        Pick {
            label: "dark at night"
            opts: ["never", "22 → 7", "23 → 7", "0 → 8"]
            cur: root.hours.findIndex(h => h.length === (root.st.night || []).length && h.every((x, j) => x === root.st.night[j]))
            onPicked: i => root.st.night = root.hours[i]
        }
        Toggle { text: "dark in a game"; on: root.st.gameDark; onFlip: root.st.gameDark = !root.st.gameDark }
    }
}
