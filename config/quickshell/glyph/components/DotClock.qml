import QtQuick
import qs

// Local addition (not upstream Glyph): the home clock as a real 5x7 dot matrix.
// Doto at 300px shows polygon edges and its heavy dots fuse together, so this
// draws true circles instead. Same glyphs as the SDDM login clock.
Row {
    id: clock
    property string text: "00:00"
    property real dot: 30              // dot diameter
    property real colonOpacity: 1
    readonly property real gap: Math.round(dot * 0.5)
    readonly property var glyphs: ({
        "0": ["01110","10001","10001","10001","10001","10001","01110"],
        "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"],
        "3": ["11110","00001","00001","01110","00001","00001","11110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"],
        "5": ["11111","10000","11110","00001","00001","10001","01110"],
        "6": ["00110","01000","10000","11110","10001","10001","01110"],
        "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"],
        "9": ["01110","10001","10001","01111","00001","00010","01100"],
        ":": ["0","0","1","0","1","0","0"]
    })
    spacing: dot * 1.4

    Repeater {
        model: clock.text.split("")
        Grid {
            required property string modelData
            readonly property var rows: clock.glyphs[modelData] || clock.glyphs["0"]
            columns: rows[0].length
            spacing: clock.gap
            opacity: modelData === ":" ? clock.colonOpacity : 1
            Repeater {
                model: rows.length * rows[0].length
                Rectangle {
                    required property int index
                    readonly property bool lit: rows[Math.floor(index / rows[0].length)][index % rows[0].length] === "1"
                    width: clock.dot; height: clock.dot; radius: clock.dot / 2
                    antialiasing: true
                    color: lit ? Theme.fg : "transparent"
                }
            }
        }
    }
}
