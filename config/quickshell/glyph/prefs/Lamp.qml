import QtQuick
import qs
import qs.components
import qs.services

// local: LIGHTS → lamp (services/Govee). Left, the lamp as it is now — a tall column of dots in the colour it reports,
// as bright as it is, whoever set it (the phone too). Then its level and switch; right, what colour it takes — the case
// lights', one from the palette, a white — and when it goes dark
Row {
    id: root

    readonly property var st: Govee.store
    readonly property var hours: [[], [22, 7], [23, 7], [0, 8]]
    readonly property var sources: ["case", "palette", "white"]
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
        Dial {
            anchors.horizontalCenter: parent.horizontalCenter
            size: 280
            n: 52
            from: 1
            label: "level"
            value: root.st.level
            onMoved: v => root.st.level = Math.round(v)
        }
        Toggle { anchors.horizontalCenter: parent.horizontalCenter; text: "lamp"; on: root.st.on; onFlip: root.st.on = !root.st.on }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 22
        Pick { label: "colour"; opts: root.sources; cur: root.sources.indexOf(root.st.source); onPicked: i => root.st.source = root.sources[i] }

        // case: whatever the case lights are on — the accent, or white (daylight on the lamp's white LEDs)
        Lb {
            visible: root.st.source === "case"
            text: Rgb.store.white ? "the case lights' white · 6500 k on its white leds" : "the case lights' colour · the style's accent"
        }
        // a colour picked lights the lamp too. Click, ↵ or space; ←→ the next one
        Grid {
            visible: root.st.source === "palette"
            columns: 7
            rowSpacing: 4
            Repeater {
                model: Govee.palette
                Swatch {
                    required property var modelData
                    width: 88
                    size: 40
                    item: ({ name: modelData.name, fill: modelData.color, now: root.st.color === modelData.name,
                             run: () => { root.st.color = modelData.name; root.st.on = true; } })
                }
            }
        }
        Row {
            visible: root.st.source === "white"
            Repeater {
                model: Govee.whites
                Swatch {
                    required property int modelData
                    width: 88
                    size: 40
                    item: ({ name: modelData + " k", fill: Govee.tint(modelData), now: root.st.kelvin === modelData,
                             run: () => { root.st.kelvin = modelData; root.st.on = true; } })
                }
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
