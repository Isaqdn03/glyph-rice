import QtQuick
import qs
import qs.components

// local: a block of console keys: its name in white, a note in mute, then the keys
Column {
    id: grp

    property string title
    property string note

    spacing: 14
    Row {
        spacing: 12
        Lb { text: grp.title; px: 13; color: Theme.fg }
        Lb { visible: !!text; text: grp.note ? "· " + grp.note : ""; px: 13; color: Theme.mute }
    }
}
