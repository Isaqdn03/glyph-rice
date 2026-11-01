import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components
import qs.settings
import qs.services

// local: agent usage — Super+U or a click on the bar's agent meter. Card 440 right of the bar, bottom-aligned with the tray
// where the meter sits, on the focused monitor. Per agent: the 5h window in Doto, then every limit as a dot row
// with what's left until it resets. A row goes red at 80%. R or the round button refreshes; Esc or a click outside closes
PanelWindow {
    id: root

    property bool open: false
    function toggle() {
        if (!open) screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        open = !open;
    }
    function close() { open = false; }
    onOpenChanged: if (open) Usage.refresh(false)

    property real t: open ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-agents"

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var en: Qt.locale("en_US")
    readonly property int gap: Rules.store.gapsOut

    function left(ms) {
        const s = (ms - clock.date.getTime()) / 1000;
        if (s <= 0) return "now";
        if (s < 3600) return `${Math.ceil(s / 60)} m`;
        if (s < 86400) return `${Math.floor(s / 3600)} h ${Math.floor(s % 3600 / 60)} m`;
        return en.toString(new Date(ms), "ddd h AP");
    }
    function ago(ms) {
        const m = Math.floor((clock.date.getTime() - ms) / 60000);
        return m < 1 ? "just now" : m < 60 ? `${m} m ago` : `${Math.floor(m / 60)} h ago`;
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.35 * root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Stage {
        Rectangle {
            id: panel
            x: root.gap + 64 + 14 - 24 * (1 - root.t) // right edge of the bar pill, then a 14 gap
            y: parent.height - height - root.gap
            width: 440
            height: col.height + 52
            opacity: root.t
            radius: 36
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_R) Usage.refresh(true);
                else return;
                e.accepted = true;
            }
            MouseArea { anchors.fill: parent }

            Column {
                id: col
                x: 26
                y: 26
                width: parent.width - 52
                spacing: 22

                Item {
                    width: parent.width
                    height: 44
                    Lb { anchors.verticalCenter: parent.verticalCenter; text: "agents"; color: Theme.fg }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 44
                        height: 44
                        radius: 22
                        color: refHov.hovered ? Theme.s3 : Theme.s2
                        Icon { anchors.centerIn: parent; text: "\u{F0450}"; color: Usage.busy ? Theme.grey : Theme.fg }
                        HoverHandler { id: refHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Usage.refresh(true) }
                    }
                }

                Lb { visible: !Usage.agents.length; text: Usage.busy ? "reading limits" : "no data"; px: 10 }

                Repeater {
                    model: Usage.agents

                    Column {
                        id: ag
                        required property var modelData
                        required property int index
                        readonly property var first: Usage.top(modelData)
                        width: col.width
                        spacing: 14

                        Rectangle { visible: ag.index > 0; width: parent.width; height: 1; color: Theme.s2 }

                        Row {
                            spacing: 14
                            Num { text: ag.first ? ag.first.pct : "--"; font.pixelSize: 64 }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Lb { text: `% ${ag.modelData.id}`; color: Theme.fg }
                                Lb {
                                    text: [ag.modelData.plan, ag.first?.pct ? ag.first["key"] : "",
                                        ag.modelData.stale ? (ag.modelData.at ? `stale · ${root.ago(ag.modelData.at)}` : ag.modelData.error) : ""]
                                        .filter(s => s).join(" · ")
                                }
                            }
                        }

                        Repeater {
                            model: ag.modelData.limits

                            Row {
                                id: lim
                                required property var modelData
                                readonly property int pct: modelData.pct
                                spacing: 12
                                Lb { anchors.verticalCenter: parent.verticalCenter; width: 52; elide: Text.ElideRight; text: lim.modelData.key; px: 10 }
                                Seg {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: col.width - 52 - 48 - 92 - 3 * 12
                                    height: 6
                                    n: 16
                                    f: lim.pct / 100
                                    on: lim.pct >= 80 ? Theme.red : Theme.fg
                                }
                                Lb { anchors.verticalCenter: parent.verticalCenter; width: 48; horizontalAlignment: Text.AlignRight; text: `${lim.pct}%`; color: Theme.fg; px: 11 }
                                // an untouched window has no real reset yet (Codex reports now + window), so say nothing
                                Lb { anchors.verticalCenter: parent.verticalCenter; width: 92; horizontalAlignment: Text.AlignRight; text: lim.pct > 0 && lim.modelData.reset ? root.left(lim.modelData.reset) : ""; px: 10 }
                            }
                        }
                    }
                }

                Lb { visible: Usage.at > 0; text: `updated ${root.ago(Usage.at)} · r refreshes`; color: Theme.mute; px: 10 }
            }
        }
    }
}
