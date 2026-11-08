import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.components

// local: AUDIO in the console (prefs/Console.qml). Left, both defaults as a volume knob, a live level and mute; right, every
// device on the machine, the lit lamp is the default (Pipewire.preferredDefault*, wireplumber remembers). Hardware only,
// grouped by card — the same reading of nodes as prefs/Audio.qml. The meters capture only while the page is on screen
Item {
    id: root

    property bool live: false
    readonly property var outs: devs(true)
    readonly property var ins: devs(false)
    readonly property string head: `system · pipewire · ${outs.length} out · ${ins.length} in`

    // m: mute the side that has focus, the output if neither has
    function mute() {
        const n = inSide.hot ? Sys.mic : Sys.sink;
        if (n?.audio) n.audio.muted = !n.audio.muted;
    }

    function devs(out) {
        return Pipewire.nodes.values.filter(n => n.audio && !n.isStream && (out ? n.isSink : n.type & PwNodeType.Source))
            .map(n => Object.assign({ node: n }, split(n)))
            .sort((a, b) => a.card.localeCompare(b.card) || a.port.localeCompare(b.port));
    }
    function split(n) {
        const d = n.description || n.name, nick = (n.nickname || "").replace(/ #\d+$/, "");
        if (nick && d.startsWith(nick + " ")) return { card: nick, port: d.slice(nick.length + 1) };
        // HDMI: "GA102 … Digital Stereo (HDMI 2) [ED340CU S3]" — the monitor is the name
        const bus = d.match(/\(((?:HDMI|DP)[^)]*)\)/);
        if (nick && d.includes(`[${nick}]`)) return { card: bus ? bus[1] : "", port: nick };
        return { card: "", port: d };
    }

    Side { id: outSide; x: 0; out: true; label: "output"; node: Sys.sink; list: root.outs }
    Side { id: inSide; x: 600; out: false; label: "input"; node: Sys.mic; list: root.ins }

    Devices { x: 1250; label: "output"; note: "lamp = default"; side: outSide }
    Devices { x: 1822; label: "input"; side: inSide }

    // one default: its knob, level, mute, and which device it is
    component Side: Column {
        id: side
        required property bool out
        required property string label
        required property var node
        required property var list
        readonly property int cur: list.findIndex(d => d.node === node)
        readonly property bool muted: node?.audio?.muted ?? false
        readonly property bool hot: knob.activeFocus || muteKey.activeFocus || pickedList
        property bool pickedList: false // its device list has focus
        function pick(i) {
            const n = list[i]?.node;
            if (!n) return;
            if (out) Pipewire.preferredDefaultAudioSink = n;
            else Pipewire.preferredDefaultAudioSource = n;
        }

        width: 560
        spacing: 20

        // no node while hidden — no capture stream, whichever binding Qt sets first
        PwNodePeakMonitor { id: peak; node: root.live ? side.node : null; onNodeChanged: side.lv = 0 }
        // peak is ∛amplitude, so dB = 60·log10(peak); the row shows -60…0 dB → 1 + log10(peak). It jumps up on a peak and falls
        // back on the timer so a word stays readable: in silence peak sits at 0 and peakChanged never fires
        readonly property real at: Math.max(0, Math.min(1, 1 + Math.log10(peak.peak)))
        property real lv: 0
        onAtChanged: lv = Math.max(lv, at)
        Timer { interval: 33; repeat: true; running: root.live && side.lv > 0; onTriggered: side.lv = Math.max(side.at, side.lv - 0.03) }

        Lb { text: side.label; px: 13; color: Theme.fg }
        Knob {
            id: knob
            enabled: !!side.node?.audio
            size: 280
            n: 40
            numPx: 92
            live: true
            dim: side.muted
            value: Math.round((side.node?.audio?.volume ?? 0) * 100)
            onMoved: v => {
                if (side.out) side.node.audio.muted = false; // the mic stays muted: its gain isn't a reason to open it
                side.node.audio.volume = v / 100;
            }
        }
        // 24 dots: 20 white, the last 4 red from -7.5 dB, close to clipping
        Row {
            spacing: 6
            Repeater {
                model: 24
                Rectangle {
                    required property int index
                    readonly property bool lit: !side.muted && index < Math.round(side.lv * 24)
                    width: 12
                    height: 12
                    radius: 6
                    color: lit ? index >= 20 ? Theme.red : Theme.fg : Theme.s3
                }
            }
        }
        Key { id: muteKey; enabled: !!side.node?.audio; text: "mute"; on: side.muted; onHit: side.node.audio.muted = !side.muted }
        Row {
            spacing: 8
            Lb { anchors.baseline: dev.baseline; text: "default ·"; px: 11 }
            Text {
                id: dev
                width: 460
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: side.cur >= 0 ? side.list[side.cur].port : "nothing"
                font { family: Theme.mono; pixelSize: 13; letterSpacing: 0.5 }
                color: Theme.fg
            }
        }
    }

    // the machine's devices on one side, one tab stop: ↑↓ walk, ↵ / space make it the default, a click too
    component Devices: Column {
        id: col
        required property string label
        property string note
        required property var side
        spacing: 14
        Row {
            spacing: 12
            Lb { text: col.label; px: 13; color: Theme.fg }
            Lb { visible: !!col.note; text: "· " + col.note; px: 13; color: Theme.mute }
        }
        ListView {
            id: view
            property int at: 0
            width: 520
            height: Math.min(contentHeight, 500)
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            activeFocusOnTab: true
            model: col.side.list
            onActiveFocusChanged: {
                col.side.pickedList = activeFocus;
                if (activeFocus) at = Math.max(0, col.side.cur);
            }
            onAtChanged: positionViewAtIndex(at, ListView.Contain)
            Keys.onPressed: e => {
                const d = e.key === Qt.Key_Up ? -1 : e.key === Qt.Key_Down ? 1 : 0;
                if (d) at = Math.max(0, Math.min(count - 1, at + d));
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) col.side.pick(at);
                else return;
                e.accepted = true;
            }
            delegate: Rectangle {
                id: dv
                required property var modelData
                required property int index
                readonly property bool on: index === col.side.cur
                readonly property bool ring: view.activeFocus && index === view.at
                width: 520
                height: 56
                radius: Theme.corner(8)
                color: on ? Theme.s2 : Theme.s1
                border { width: ring ? 1.5 : 1; color: ring ? Theme.fg : hh.hovered ? Theme.mute : Theme.s3 }
                Behavior on color { ColorAnimation { duration: Theme.t } }
                Rectangle {
                    x: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: 22
                    radius: 2
                    color: dv.on ? Theme.fg : Theme.s3
                }
                Text {
                    anchors { left: parent.left; leftMargin: 40; right: bus.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideMiddle // long ALSA names differ at the end: "… (HDMI 2)"
                    textFormat: Text.PlainText
                    text: dv.modelData.port
                    font { family: Theme.mono; pixelSize: 15; letterSpacing: 0.6 }
                    color: dv.on ? Theme.fg : Theme.grey
                }
                Lb {
                    id: bus
                    anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    text: dv.modelData.card
                    px: 11
                    color: Theme.mute
                }
                HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        view.forceActiveFocus();
                        view.at = dv.index;
                        col.side.pick(dv.index);
                    }
                }
            }
        }
    }
}
