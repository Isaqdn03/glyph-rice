import QtQuick
import qs
import qs.components
import qs.services

// local: LIGHTS page of prefs (services/Rgb). The level ring and the switch on the left; colour, when they go dark, and
// what's behind them on the right — a row of dots per part, in the colour it shows now, unlit when it's dark
Row {
    id: root

    readonly property var st: Rgb.store
    readonly property var hours: [[], [22, 7], [23, 7], [0, 8]]
    readonly property string caption: "lights · " + (!Rgb.parts.length ? "openrgb isn't answering"
        : !st.on ? "off" : Rgb.gaming ? "dark · game mode" : Rgb.night ? "dark · night hours" : `#${Rgb.hex.toLowerCase()} · ${st.level} %`)

    spacing: 70

    Column {
        spacing: 22
        Dial { anchors.horizontalCenter: parent.horizontalCenter; size: 340; n: 60; label: "level"; value: root.st.level; onMoved: v => root.st.level = Math.round(v) }
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
            topPadding: 14
            spacing: 16
            Repeater {
                model: Rgb.parts
                Row {
                    required property var modelData
                    Lb { width: 110; anchors.verticalCenter: parent.verticalCenter; text: modelData.name }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Repeater {
                            model: modelData.n
                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: !Rgb.lit ? Theme.s3 : modelData.mono ? Theme.fg : Rgb.base
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
