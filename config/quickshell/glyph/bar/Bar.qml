import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components
import qs.settings
import qs.services // local: Usage for the agent meter

// бар: вертикальная пилюля у левого края. Сверху знак (кольцо из 16 точек) — лаунчер, центр краснеет, пока запись или микрофон.
// Воркспейсы точками, заголовок окна столбиком, часы Doto по центру, трей снизу — клик открывает быстрые настройки.
// Что в трее и в каком порядке, есть ли заголовок — Theme.state (настройки, раздел BAR)
PanelWindow {
    id: root

    signal markClicked
    signal trayClicked
    signal powerClicked
    signal clockClicked
    signal agentsClicked // local

    anchors { left: true; top: true; bottom: true }
    implicitWidth: Math.ceil((64 + gap) * Theme.s)
    color: "transparent"
    WlrLayershell.namespace: "glyph-bar"

    // local: auto-hide, for OLEDs (burn-in). Theme.state.barHide lists the monitors (by model) it hides on. Hidden: no
    // exclusive zone, input only on a 2px strip at the left edge. Rest there for barShowMs, or shell:bar (peek), and the
    // pill slides in over the windows; leave it and it slides back out
    readonly property bool autoHide: Theme.state.barHide.includes(screen?.model || screen?.name || "")
    property bool hov: false
    property bool peeked: false
    property int peeks: 0 // shell.qml bumps it on every bar; the one on the focused monitor answers
    readonly property bool shown: !autoHide || hov || peeked || powOpen || pop.visible
    property real slide: shown ? 1 : 0
    Behavior on slide { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    exclusionMode: autoHide ? ExclusionMode.Ignore : ExclusionMode.Auto
    mask: Region { item: root.shown ? hitAll : hitEdge }
    onPeeksChanged: if (autoHide && Hyprland.focusedMonitor === mon) { peeked = !peeked; if (peeked) peekT.restart(); }
    onAutoHideChanged: { hov = false; peeked = false; }
    Timer { id: showT; interval: Theme.state.barShowMs; onTriggered: root.hov = true }
    Timer { id: hideT; interval: 500; onTriggered: root.hov = false }
    Timer { id: peekT; interval: 3000; onTriggered: root.peeked = false }
    Item { id: hitEdge; width: 2; height: parent.height }
    Item { id: hitAll; anchors.fill: parent }

    readonly property int gap: Rules.store.gapsOut // local: pill sits at the window gap, not a fixed 14
    // local: per-monitor workspaces (hypr/monitor-workspaces.lua): each monitor owns a block of ten, and the
    // workspace it shows is always one of its own, so that gives the block. Dots are this monitor's slots 1-10
    readonly property var mon: Hyprland.monitorFor(root.screen)
    readonly property int base: Math.floor(((mon?.activeWorkspace?.id ?? 1) - 1) / 10) * 10
    readonly property int active: (mon?.activeWorkspace?.id ?? 0) - base
    // шесть точек, больше — если занят или открыт дальний
    readonly property int count: Math.min(10, Math.max(6, active, ...Hyprland.workspaces.values.filter(w => w.toplevels.values.length && w.id > base && w.id <= base + 10).map(w => w.id - base)))
    readonly property var top: ToplevelManager.activeToplevel
    readonly property var bat: UPower.displayDevice
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null

    // hyprland 0.56 с lua: dispatch принимает lua-выражение
    function go(ws) { Hyprland.dispatch(`hl.dsp.focus({ workspace = "${ws}" })`); }
    // local: slot n on this bar's monitor; plain workspace n if the module isn't loaded
    function slot(n) { Hyprland.dispatch(`(monitor_workspaces and monitor_workspaces.focus(${n}, "${root.mon?.name ?? ""}")) or hl.dsp.focus({ workspace = "${base + n}" })`); }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Stage {
        // local: auto-hide — Stage covers the whole window, so this sees the edge strip and the pill alike
        HoverHandler {
            onHoveredChanged: {
                if (hovered) { hideT.stop(); showT.restart(); }
                else { showT.stop(); hideT.restart(); }
            }
        }
        Rectangle {
            id: pill
            x: root.gap - (1 - root.slide) * (64 + root.gap + 2) // local: auto-hide slides it off the left edge
            visible: root.slide > 0 // local
            y: root.gap
            width: 64
            height: parent.height - 2 * root.gap
            radius: 32
            color: Theme.s1
            border { width: 1; color: Theme.s2 }

            WheelHandler { onWheel: e => root.go(e.angleDelta.y > 0 ? "m-1" : "m+1") } // local: m = this monitor

            // знак: кольцо из точек, центр — красный, пока что-то пишет
            Item {
                id: mark
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18
                width: 34
                height: 34
                Ring { anchors.fill: parent; n: 16; dot: 3 }
                Rectangle {
                    anchors.centerIn: parent
                    width: 9
                    height: 9
                    radius: 4.5
                    color: Sys.live ? Theme.red : Theme.fg
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.markClicked() }
            }

            // воркспейсы: текущий вытягивается в белую пилюлю, занятые серые, пустые — линия
            Column {
                id: ws
                anchors.horizontalCenter: parent.horizontalCenter
                y: mark.y + mark.height + 24
                spacing: 8

                Repeater {
                    model: root.count

                    Rectangle {
                        required property int index
                        readonly property int n: index + 1
                        readonly property bool occ: (Hyprland.workspaces.values.find(w => w.id === root.base + n)?.toplevels.values.length ?? 0) > 0
                        readonly property bool on: root.active === n
                        width: 8
                        height: on ? 28 : 8
                        radius: 4
                        color: on ? Theme.fg : occ ? Theme.grey : Theme.s3
                        Behavior on height { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.slot(parent.n) }
                    }
                }
            }

            // заголовок окна, повёрнутый: от воркспейсов до часов
            Item {
                id: title
                anchors.horizontalCenter: parent.horizontalCenter
                y: ws.y + ws.height + 24
                width: 20
                height: Math.max(0, clk.y - 24 - y)
                clip: true
                visible: Theme.state.barTitle
                Lb {
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2
                    width: parent.height
                    rotation: 90
                    elide: Text.ElideRight
                    visible: (Hyprland.focusedWorkspace?.toplevels.values.length ?? 0) > 0
                    text: root.top ? `${root.top.appId.split(".").pop()} · ${root.top.title}` : ""
                    px: 11
                }
            }

            // часы столбиком: 14 над 32 и день. Клик — календарь и фокус-таймер (cal/Cal)
            Column {
                id: clk
                anchors.centerIn: parent
                TapHandler { onTapped: root.clockClicked() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Num {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Theme.hh(clock.date)
                    font.pixelSize: 30
                }
                Num {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.date, "mm")
                    font.pixelSize: 30
                }
                Lb {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 8
                    text: Qt.locale("en_US").toString(clock.date, "ddd d")
                    px: 10
                }
            }

            // трей — Theme.state.bar по порядку (настройки, раздел BAR). Раскладка, сеть, bluetooth, звук (колесо — громкость),
            // уведомления, батарея: клик открывает быстрые настройки. Режим питания и питание — свои клики
            Column {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 22 }
                spacing: 20

                Repeater {
                    model: Theme.state.bar
                    Loader {
                        id: part
                        required property string modelData
                        readonly property bool quick: modelData !== "mode" && modelData !== "power" && modelData !== "agents" // local: agents opens its own card
                        anchors.horizontalCenter: parent.horizontalCenter
                        sourceComponent: root.parts[modelData] ?? null
                        visible: !!sourceComponent && (modelData !== "battery" || root.bat.isLaptopBattery)
                        TapHandler { enabled: part.quick; onTapped: root.trayClicked() }
                        HoverHandler { enabled: part.quick; cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
    }

    readonly property var parts: ({ agents: agentsC, layout: layoutC, wifi: wifiC, bluetooth: btC, sound: soundC, notes: notesC, battery: batC, mode: modeC, power: powerC })
    // local: agent meter — Claude and Codex, a column of five dots each, filled to its 5h window (red from 80%);
    // Claude's number under them. Click — the agents card (agents/Agents)
    Component {
        id: agentsC
        Column {
            spacing: 8
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.agentsClicked() }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: [Usage.claude, Usage.codex]
                    Seg {
                        required property var modelData
                        readonly property int pct: Usage.top(modelData)?.pct ?? 0
                        width: 5
                        height: 41
                        n: 5
                        vertical: true
                        f: pct / 100
                        on: pct >= 80 ? Theme.red : Theme.fg
                    }
                }
            }
            Lb { anchors.horizontalCenter: parent.horizontalCenter; text: Usage.top(Usage.claude)?.pct ?? "--"; px: 10 }
        }
    }
    Component { id: layoutC; Lb { text: Sys.layout; px: 10 } }
    Component {
        id: wifiC
        Icon {
            text: Networking.wifiEnabled ? "\u{F05A9}" : "\u{F05AA}"
            color: root.wifi?.connected ? Theme.fg : Theme.grey
        }
    }
    Component {
        id: btC
        Icon {
            text: Bluetooth.defaultAdapter?.enabled ? "\u{F00AF}" : "\u{F00B2}"
            color: Bluetooth.devices.values.some(d => d.connected) ? Theme.fg : Theme.grey
        }
    }
    Component {
        id: soundC
        Icon {
            text: Sys.muted ? "\u{F075F}" : "\u{F057E}"
            WheelHandler { onWheel: e => Sys.setVol(Sys.vol + (e.angleDelta.y > 0 ? 0.05 : -0.05)) }
        }
    }
    Component {
        id: notesC
        Icon {
            text: Theme.state.dnd ? "\u{F009B}" : "\u{F009A}"
            color: Notes.list.length ? Theme.fg : Theme.grey
        }
    }
    // в вертикальном баре батарея стоит, заряд растёт снизу. На зарядке — молния сверху, заливка дышит, пока заряжается
    Component {
        id: batC
        Column {
            id: batc
            HoverHandler { onHoveredChanged: { root.batHot = hovered; root.peek(batc); } Component.onDestruction: root.batHot = false }
            spacing: 8
            readonly property bool ac: !UPower.onBattery
            readonly property bool charging: root.bat.state === UPowerDeviceState.Charging
            // дыхание шагом 20 кадров/с, как шар в home/Back: анимация гнала бы бар на каждом vsync (120 Гц) все часы
            // зарядки. Косинус с периодом 2,2 с — те же два InOutSine по 1,1 с
            property real phase: 0
            readonly property real pulse: charging ? 0.675 + 0.325 * Math.cos(phase * Math.PI / 1.1) : 1
            Timer { running: batc.charging; interval: 50; repeat: true; onTriggered: batc.phase = (batc.phase + 0.05) % 2.2; onRunningChanged: batc.phase = 0 }
            Icon { visible: batc.ac; anchors.horizontalCenter: parent.horizontalCenter; text: "\u{F140B}"; font.pixelSize: 14 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 14
                height: 26
                radius: 7
                color: "transparent"
                border { width: 1.5; color: Theme.grey }
                Rectangle {
                    x: 3
                    width: parent.width - 6
                    height: (parent.height - 6) * root.bat.percentage
                    anchors { bottom: parent.bottom; bottomMargin: 3 }
                    radius: 4
                    color: root.batLow ? Theme.red : Theme.fg
                    opacity: batc.pulse
                }
            }
            Lb { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(root.bat.percentage * 100); px: 10 }
        }
    }
    // режим питания засечками (Rules.modes): ultra — одна, performance — все; клик — следующий,
    // наведение (и на батарею) — карточка с выбором
    Component {
        id: modeC
        Item {
            id: ticks
            width: 40
            height: 22
            Row {
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: Rules.modeCount
                    Rectangle {
                        required property int index
                        anchors.bottom: parent.bottom
                        width: 3
                        height: 5 + index * 3
                        radius: 1.5
                        color: index <= Rules.mode ? Theme.fg : Theme.s3
                    }
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: { root.tickHot = hovered; root.peek(ticks); } Component.onDestruction: root.tickHot = false }
            TapHandler { onTapped: Rules.setMode((Rules.mode + 1) % Rules.modeCount) }
        }
    }
    Component {
        id: powerC
        Icon {
            text: "\u{F0425}"
            color: pwr.hovered ? Theme.fg : Theme.grey
            HoverHandler { id: pwr; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.powerClicked() }
        }
    }

    // ---- батарея и режим питания: навёл на батарею или засечки — карточка справа от бара, как поповер caelestia.
    // Заряд Doto, статус, шкала; ниже режимы кругами с засечками — клик выбирает, под курсором — что он делает.
    // Ушёл и с бара, и с карточки — гаснет ----
    property bool batHot: false
    property bool tickHot: false
    readonly property bool powHot: batHot || tickHot || popHov.hovered
    readonly property bool batLow: UPower.onBattery && root.bat.percentage < 0.15
    // карточка встаёт низом по тому, на что навели (батарея или засечки); пока видна — не прыгает
    property real popY: 0
    function peek(it) { if (!pop.visible) popY = it.mapToItem(pill, 0, it.height).y; }
    property bool powOpen: false
    property int powPeek: -1
    onPowHotChanged: powHot ? powOpenT.restart() : powCloseT.restart()
    Timer { id: powOpenT; interval: 180; onTriggered: if (root.powHot) root.powOpen = true }
    Timer { id: powCloseT; interval: 300; onTriggered: if (!root.powHot) root.powOpen = false }
    function hm(sec) { const m = Math.round(sec / 60); return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} m` : `${m} m`; }
    readonly property string batState: root.bat.state === UPowerDeviceState.Charging
        ? "charging" + (root.bat.timeToFull ? ` · full in ${hm(root.bat.timeToFull)}` : "")
        : !UPower.onBattery ? "on ac · full"
        : "on battery" + (root.bat.timeToEmpty ? ` · ${hm(root.bat.timeToEmpty)} left` : "")

    PopupWindow {
        id: pop
        property real t: root.powOpen ? 1 : 0
        Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        visible: t > 0
        // от правого края пилюли бара с зазором 14; низом — по popY, растёт вверх
        anchor.item: pill
        anchor.rect: Qt.rect(pill.width + 14, root.popY, 1, 1)
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Top | Edges.Right
        implicitWidth: Math.ceil(440 * Theme.s)
        implicitHeight: Math.ceil(card.height * Theme.s)
        color: "transparent"

        Stage {
            Rectangle {
                id: card
                width: 440
                height: body.height + 52
                radius: 36
                color: Theme.s1
                border { width: 1; color: Theme.s2 }
                opacity: pop.t
                transform: Translate { x: -16 * (1 - pop.t) }
                HoverHandler { id: popHov }

                Column {
                    id: body
                    x: 26
                    y: 26
                    width: parent.width - 52
                    spacing: 18

                    Row {
                        spacing: 14
                        Num { text: Math.round(root.bat.percentage * 100); font.pixelSize: 72 }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Lb { text: "% battery"; color: Theme.fg }
                            Lb { text: root.batState }
                        }
                    }
                    Seg { width: parent.width; height: 6; n: 24; f: root.bat.percentage; on: root.batLow ? Theme.red : Theme.fg }

                    Lb { topPadding: 6; text: "power mode" }
                    Row {
                        spacing: (body.width - Rules.modeCount * 80) / Math.max(1, Rules.modeCount - 1)
                        Repeater {
                            model: Rules.modeCount
                            Column {
                                id: mo
                                required property int index
                                readonly property bool on: Rules.mode === index
                                spacing: 10
                                Rectangle {
                                    width: 80
                                    height: 80
                                    radius: 40
                                    color: mo.on ? Theme.fg : moHov.hovered ? Theme.s3 : Theme.s2
                                    Behavior on color { ColorAnimation { duration: Theme.t } }
                                    // засечки: сколько горит — такая сила
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                required property int index
                                                anchors.bottom: parent.bottom
                                                width: 5
                                                height: 8 + index * 6
                                                radius: 2.5
                                                color: index <= mo.index ? (mo.on ? Theme.ink : Theme.fg) : (mo.on ? Theme.mute : Theme.s3)
                                            }
                                        }
                                    }
                                    HoverHandler {
                                        id: moHov
                                        cursorShape: Qt.PointingHandCursor
                                        onHoveredChanged: if (hovered) root.powPeek = mo.index; else if (root.powPeek === mo.index) root.powPeek = -1
                                    }
                                    TapHandler { onTapped: Rules.setMode(mo.index) }
                                }
                                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: mo.index === 3 ? "max" : Rules.modes[mo.index].name; color: mo.on ? Theme.fg : Theme.grey }
                            }
                        }
                    }
                    Lb {
                        readonly property int i: root.powPeek >= 0 ? root.powPeek : Rules.mode
                        width: parent.width
                        elide: Text.ElideRight
                        text: `${Rules.modes[i].what} · ${i === 0 ? Rules.rates[0] : Rules.refreshHz} hz`
                    }
                }
            }
        }
    }
}
