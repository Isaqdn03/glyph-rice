import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.services
import qs.settings

// local: prefs as a console ("D · Console", prefs-console-handoff.md in the repo root). It opens on the wall: all 13
// sections at once, fixed modules on a lettered 5 × 3 grid, each a tiny instrument and its live numbers — nothing on it
// is made up. State by brightness: lit dots and white type are on, hollow and grey are off; the one accent is the
// selected module's dot. ←↑↓→ move, ↵ / tab / click open, esc closes.
// Same API as Prefs.qml (open, close, toggle, wallRequested), shell.qml swaps it in. A module that isn't built here yet
// opens that page of the old Prefs (pageRequested)
PanelWindow {
    id: root

    signal wallRequested
    signal pageRequested(int k) // the old Prefs' page k (Prefs.sections); -1 — the old prefs as it was left

    // the wall, left to right and down: c, r — top-left cell, w — cells wide; k — the page in Prefs.qml
    readonly property var mods: [
        { tag: "a1", name: "home", k: 0, c: 0, r: 0, w: 1 },
        { tag: "b1", name: "deck", k: 1, c: 1, r: 0, w: 1 },
        { tag: "c1", name: "bar", k: 2, c: 2, r: 0, w: 1 },
        { tag: "d1", name: "look", k: 3, c: 3, r: 0, w: 1 },
        { tag: "e1", name: "style", k: 4, c: 4, r: 0, w: 1 },
        { tag: "a2", name: "windows", k: 5, c: 0, r: 1, w: 2 },
        { tag: "c2", name: "display", k: 6, c: 2, r: 1, w: 2 },
        { tag: "e2", name: "audio", k: 7, c: 4, r: 1, w: 1 },
        { tag: "a3", name: "power", k: 8, c: 0, r: 2, w: 1 },
        { tag: "b3", name: "input", k: 9, c: 1, r: 2, w: 1 },
        { tag: "c3", name: "idle", k: 10, c: 2, r: 2, w: 1 },
        { tag: "d3", name: "lights", k: 12, c: 3, r: 2, w: 1 },
        { tag: "e3", name: "shell", k: 11, c: 4, r: 2, w: 1 }
    ]
    property int sel: 6 // remembered between opens; display first
    property int cx: 2  // the column ↑↓ keep: b1 ↓ a2 ↓ lands on b3, not a3

    function at(c, r) { return mods.findIndex(m => m.r === r && c >= m.c && c < m.c + m.w); }
    function step(dc, dr) {
        const m = mods[sel];
        if (dc) {
            const c = dc < 0 ? m.c - 1 : m.c + m.w;
            if (c < 0 || c > 4) return;
            sel = at(c, m.r);
            cx = mods[sel].c;
        } else if (m.r + dr >= 0 && m.r + dr <= 2) {
            sel = at(cx, m.r + dr);
        }
    }
    function enter(i) {
        sel = i;
        cx = mods[i].c;
        close();
        pageRequested(mods[i].k);
    }

    // ---- open and close: animates itself (glyph's layers are no_anim in hypr) ----
    property bool shown: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    function open() {
        pickMon = Hyprland.focusedMonitor?.name ?? "";
        // the wall needs 2580 design px (21:9); a 16:10 stage is 1920 — the old prefs there, until a narrow wall exists
        const s = Quickshell.screens.find(x => x.name === pickMon);
        if (s && s.width / Theme.s < 2580) {
            pageRequested(-1);
            return;
        }
        shown = true;
        stage.forceActiveFocus();
        Ddc.refresh(); // the monitors' own buttons may have moved it
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }

    // the screen HOME, BAR and DISPLAY speak about: the focused one at open; unplugged — the first
    property string pickMon
    readonly property var names: Quickshell.screens.map(s => s.name)
    readonly property string mon: names.includes(pickMon) ? pickMon : names[0] ?? ""
    readonly property bool multi: names.length > 1
    readonly property string monModel: Quickshell.screens.find(s => s.name === mon)?.model || mon

    // ---- what the modules read ----
    // home's bento on this screen, packed like Home: left to right, a widget that doesn't fit its row starts the next
    readonly property var cells: {
        let row = 0, col = 0;
        return Theme.scr(mon, "widgets").map(w => {
            const span = Theme.kinds[w] ?? 1;
            if (col + span > 3) {
                row++;
                col = 0;
            }
            const c = { id: w, row, col, span, fits: row < 3 };
            col += span;
            return c;
        });
    }
    readonly property int used: cells.filter(c => c.fits).reduce((a, c) => a + c.span, 0)
    readonly property int offGrid: cells.filter(c => !c.fits).length
    readonly property var rounds: ["weather", "cpu", "ram", "gpu", "disk", "battery", "buds", "cava"] // as Prefs draws them

    readonly property var disp: Rules.mons.find(x => x.name === mon) ?? Rules.mon
    readonly property var ddc: Ddc.screens.find(x => x.ready && x.out === disp.name) ?? null
    readonly property string bri: ddc ? Math.round(ddc.value * 100) : Sys.hasBri && disp.name === Rules.mon.name ? Math.round(Sys.bri * 100) : "—"

    // a device as card + port, like the AUDIO page: "SSL 2+" + "Line Outputs 1/L + 2/R"
    function split(n) {
        if (!n) return { card: "", port: "nothing" };
        const d = n.description || n.name, nick = (n.nickname || "").replace(/ #\d+$/, "");
        if (nick && d.startsWith(nick + " ")) return { card: nick, port: d.slice(nick.length + 1) };
        const bus = d.match(/\(((?:HDMI|DP)[^)]*)\)/);
        if (nick && d.includes(`[${nick}]`)) return { card: bus ? bus[1] : "", port: nick };
        return { card: "", port: d };
    }

    // idle: the first thing that happens, then the rest
    readonly property var idles: [["lock", Rules.store.lockAfter], ["screen off", Rules.store.dpmsAfter], [Rules.hibernateOn ? "hibernate" : "sleep", Rules.store.sleepAfter]]
    readonly property var nextIdle: idles.filter(x => x[1] > 0).sort((a, b) => a[1] - b[1])[0] ?? null

    readonly property string tone: Rgb.tone === "palette" ? Rgb.pick.name : Rgb.tone
    readonly property int leds: Rgb.parts.reduce((a, p) => a + p.n, 0)

    readonly property string styleName: Theme.state.paint === "scheme" || Theme.state.paint === "wall" && Theme.tones.length ? Theme.pal.name : "nothing"
    readonly property string styleFrom: Theme.state.paint === "scheme" ? `palette · ${Theme.pal.group}` : Theme.state.paint === "wall" && Theme.tones.length ? "from the wallpaper" : "black · white dots · one red"
    readonly property var swatches: [Theme.fg, Theme.grey, Theme.mute, Theme.s3, Theme.s2, Theme.s1, Theme.bg, Theme.accent].concat(Qt.colorEqual(Theme.accent, Theme.red) ? [] : [Theme.red])

    SystemClock { id: clock; enabled: root.visible; precision: SystemClock.Minutes }
    readonly property string hello: { const h = clock.date.getHours(); return h < 5 ? "good night" : h < 12 ? "good morning" : h < 18 ? "good afternoon" : "good evening"; }
    property bool dim: false // look's colon, off half the time when the home clock blinks
    Timer { running: root.visible && Theme.state.blink; interval: 500; repeat: true; onTriggered: root.dim = !root.dim; onRunningChanged: root.dim = false }

    property var meta: ({})
    FileView { path: Quickshell.shellPath("rice.json"); onLoaded: try { root.meta = JSON.parse(text()); } catch (e) {} }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    // several screens — on demand (a click elsewhere takes the keyboard, a click here brings it back); one — exclusive
    WlrLayershell.keyboardFocus: shown ? multi ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-prefs"

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: stage.forceActiveFocus() }
    }

    Stage {
        id: stage
        opacity: root.t
        focus: true
        Keys.onPressed: e => {
            const k = e.key;
            if (k === Qt.Key_Left || k === Qt.Key_H) root.step(-1, 0);
            else if (k === Qt.Key_Right || k === Qt.Key_L) root.step(1, 0);
            else if (k === Qt.Key_Up || k === Qt.Key_K) root.step(0, -1);
            else if (k === Qt.Key_Down || k === Qt.Key_J) root.step(0, 1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_Tab) root.enter(root.sel);
            else if (k === Qt.Key_Escape) root.close();
            else return;
            e.accepted = true;
        }

        // ---- header: the rice and the time ----
        Row {
            x: 72
            y: 36
            spacing: 18
            D { id: brand; text: root.meta.name ?? "GLYPH"; font.pixelSize: 34 }
            Lb { anchors.baseline: brand.baseline; text: "prefs"; px: 13 }
        }
        Row {
            anchors { right: parent.right; rightMargin: 72 }
            y: 36
            spacing: 18
            Lb { anchors.baseline: hc.baseline; text: Qt.locale("en_US").toString(clock.date, "ddd · d MMM"); px: 13 }
            D { id: hc; text: Theme.hh(clock.date) + ":" + Qt.formatTime(clock.date, "mm"); font.pixelSize: 34 }
        }

        // the grid's letters and numbers: modules are addressed by them
        Repeater {
            model: ["a", "b", "c", "d", "e"]
            Lb { required property string modelData; required property int index; x: 349 + index * 482 - width / 2; y: 96; text: modelData; px: 13; color: Theme.mute }
        }
        Repeater {
            model: 3
            Lb { required property int index; x: 78; y: 263 + index * 291 - height / 2; text: index + 1; px: 13; color: Theme.mute }
        }

        // ---- a1 HOME: the bento as it packs on this screen ----
        Slot {
            i: 0
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 30
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    height: 96
                    opacity: Theme.state.homeBento && Theme.scr(root.mon, "home") ? 1 : 0.4
                    Repeater {
                        model: root.cells.filter(c => c.fits)
                        Rectangle {
                            required property var modelData
                            x: modelData.col * 34
                            y: modelData.row * 34
                            width: modelData.span * 34 - 6
                            height: 28
                            radius: modelData.span === 1 && root.rounds.includes(modelData.id) ? 14 : Theme.corner(7)
                            color: Theme.s2
                            border { width: 1; color: Theme.s3 }
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    D { text: `${root.used}/9`; font.pixelSize: 64 }
                    Lb { topPadding: 12; px: 11; text: "cells" + (root.multi ? " · " + root.mon : "") }
                    Lb {
                        topPadding: 6
                        px: 10
                        color: Theme.mute
                        text: `${root.cells.length} widgets · ` + (!Theme.scr(root.mon, "home") ? "no home here" : !Theme.state.homeBento ? "hidden"
                            : root.offGrid ? `${root.offGrid} off grid` : "everything fits")
                    }
                }
            }
        }

        // ---- b1 DECK: its sections in the strip ----
        Slot {
            i: 1
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 30
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, Theme.state.deck.length) * 30 + 12
                    height: 42
                    radius: Theme.corner(21)
                    color: Theme.s1
                    border { width: 1; color: Theme.s2 }
                    Row {
                        x: 10
                        y: 10
                        spacing: 8
                        Repeater {
                            model: Theme.state.deck.length
                            Rectangle { width: 22; height: 22; radius: 11; color: Theme.s3 }
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    D { text: `${Theme.state.deck.length}/${Theme.decks.length}`; font.pixelSize: 64 }
                    Lb { topPadding: 12; px: 11; text: "sections · bottom" }
                    Row {
                        topPadding: 14
                        spacing: 18
                        Lamp { lit: Theme.state.deckHover; text: "hover" }
                        Lamp { lit: Theme.state.quickHover; text: "quick" }
                    }
                }
            }
        }

        // ---- c1 BAR: a lamp per tray part, lit in the bar's order, then the ones it leaves out; lies along its edge ----
        Slot {
            i: 2
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 30
                Rectangle {
                    id: pill
                    readonly property var tray: Theme.state.bar.filter(b => Theme.bars.includes(b))
                    readonly property bool across: Theme.state.barAt === "top"
                    anchors.verticalCenter: parent.verticalCenter
                    width: across ? lamps.width + 24 : 30
                    height: across ? 30 : lamps.height + 24
                    radius: Theme.corner(15)
                    color: Theme.s1
                    border { width: 1; color: Theme.s2 }
                    Grid {
                        id: lamps
                        anchors.centerIn: parent
                        columns: pill.across ? Theme.bars.length : 1
                        spacing: 7
                        Repeater {
                            model: pill.tray.concat(Theme.bars.filter(b => !pill.tray.includes(b)))
                            Dot { required property string modelData; lit: pill.tray.includes(modelData) }
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    D { text: `${pill.tray.length}/${Theme.bars.length}`; font.pixelSize: 64 }
                    Lb { topPadding: 12; px: 11; text: `tray · ${Theme.state.barAt} edge` }
                    Row {
                        topPadding: 14
                        spacing: 18
                        Lamp { lit: Theme.state.barTitle; text: "title" }
                        Lamp { lit: Theme.state.barHide.includes(root.monModel); text: "auto-hide" }
                    }
                }
            }
        }

        // ---- d1 LOOK: the home clock as home shows it, and its switches ----
        Slot {
            i: 3
            Column {
                y: 22
                Row {
                    D { id: lookH; text: Theme.hh(clock.date); font.pixelSize: 76 }
                    D { text: ":"; font.pixelSize: 76; opacity: root.dim ? 0.2 : 1 }
                    D { text: Qt.formatTime(clock.date, "mm"); font.pixelSize: 76 }
                    Lb { visible: !Theme.state.clock24; anchors.baseline: lookH.baseline; leftPadding: 12; text: clock.date.getHours() < 12 ? "am" : "pm"; px: 11 }
                }
                Lb { topPadding: 12; px: 11; text: Qt.locale("en_US").toString(clock.date, "ddd · d MMMM") + " · " + root.hello }
                Row {
                    topPadding: 14
                    spacing: 18
                    Lamp { lit: Theme.state.grid; text: "grid" }
                    Lamp { lit: Theme.state.orb; text: "orb" }
                    Lamp { lit: Theme.state.edges; text: "edges" }
                    Lamp { lit: Theme.state.blink; text: "blink" }
                }
            }
        }

        // ---- e1 STYLE: the palette the shell wears now, grey by grey, then its accent (and red, if it isn't the accent) ----
        Slot {
            i: 4
            Column {
                y: 18
                width: parent.width
                Row {
                    spacing: 10
                    Repeater {
                        model: root.swatches
                        Rectangle {
                            required property color modelData
                            required property int index
                            width: 28
                            height: 28
                            radius: 14
                            color: modelData
                            border { width: index === 5 || index === 6 ? 1 : 0; color: Theme.s3 } // s1 and bg vanish on bg
                        }
                    }
                }
                D { topPadding: lead + 26; width: parent.width; elide: Text.ElideRight; text: root.styleName.toUpperCase(); font.pixelSize: 40 }
                Lb { topPadding: 12; px: 11; text: `${root.styleFrom} · ${Theme.light ? "light" : "dark"}` }
            }
        }

        // ---- a2 WINDOWS: a desk with two windows in the gaps, border and rounding as set — drawn bigger than life (at 1:9
        // a 3 px gap would be a third of a pixel), so it moves when they do ----
        Slot {
            i: 5
            extra: "· hyprland"
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 40
                Rectangle {
                    id: desk
                    readonly property bool across: Theme.state.barAt === "top"
                    readonly property real o: 2 + Rules.store.gapsOut * 0.4
                    readonly property real g: Rules.store.gapsIn * 0.8
                    readonly property real l: across ? o : 2 + 9 + o
                    readonly property real tp: across ? 2 + 9 + o : o
                    anchors.verticalCenter: parent.verticalCenter
                    width: 300
                    height: 126
                    color: "transparent"
                    border { width: 1; color: Theme.s3 }
                    Rectangle {
                        x: 2
                        y: 2
                        width: desk.across ? desk.width - 4 : 9
                        height: desk.across ? 9 : desk.height - 4
                        radius: Theme.corner(4.5)
                        color: Theme.s2
                    }
                    Repeater {
                        model: 2
                        Rectangle {
                            required property int index
                            readonly property real w: (desk.width - desk.l - desk.o - desk.g) / 2
                            x: desk.l + index * (w + desk.g)
                            y: desk.tp
                            width: w
                            height: desk.height - desk.tp - desk.o
                            radius: Theme.state.rounding * 0.4
                            color: Theme.s1
                            border { width: Rules.store.border ? 1 : 0; color: index ? Theme.s3 : Theme.fg }
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        spacing: 28
                        Stat { v: Rules.store.gapsIn; label: "gaps in" }
                        Stat { v: Rules.store.gapsOut; label: "gaps out" }
                        Stat { v: Rules.store.border; label: "border" }
                        Stat { v: Theme.state.rounding; label: "round" }
                        Stat { v: Theme.state.corners; label: "panels" }
                    }
                    Row {
                        topPadding: 22
                        spacing: 18
                        Lamp { lit: Rules.store.motion; text: "motion" }
                        Lamp { lit: Rules.store.blur; text: "blur" }
                        Lamp { lit: Rules.store.shadow; text: "shadow" }
                        Lamp { lit: Rules.store.gameDnd; text: "dnd in a game" }
                    }
                }
            }
        }

        // ---- c2 DISPLAY: the screens as hypr placed them, this one lit; its rate, scale and brightness ----
        Slot {
            i: 6
            extra: `· ${Rules.mons.length} screen${Rules.mons.length === 1 ? "" : "s"}`
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 50
                Item {
                    id: map
                    readonly property var ms: Rules.mons
                    readonly property real x0: Math.min(...ms.map(m => m.x))
                    readonly property real y0: Math.min(...ms.map(m => m.y))
                    readonly property real bw: Math.max(...ms.map(m => m.x + m.lw)) - x0
                    readonly property real bh: Math.max(...ms.map(m => m.y + m.lh)) - y0
                    readonly property real k: Math.min(width / bw, height / bh)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 240
                    height: 184
                    Repeater {
                        model: map.ms
                        Rectangle {
                            required property var modelData
                            readonly property bool on: modelData.name === root.disp.name
                            x: (modelData.x - map.x0) * map.k + 2
                            y: (map.height - map.bh * map.k) / 2 + (modelData.y - map.y0) * map.k + 2
                            width: modelData.lw * map.k - 4
                            height: modelData.lh * map.k - 4
                            color: "transparent"
                            border { width: on ? 1.5 : 1; color: on ? Theme.fg : Theme.mute }
                            Lb { anchors.centerIn: parent; text: parent.modelData.name; px: 13; color: parent.on ? Theme.fg : Theme.grey }
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        spacing: 46
                        Stat { v: root.disp.hz; label: "hz · " + root.disp.name }
                        Stat { v: root.disp.scale; label: "scale" }
                        Stat { v: root.bri; label: "brightness" }
                        Stat { v: Rules.store.warmth; label: "warmth k" }
                    }
                    Row {
                        topPadding: 22
                        spacing: 18
                        Lamp { lit: Theme.scr(root.mon, "bar"); text: "bar" }
                        Lamp { lit: Theme.scr(root.mon, "home"); text: "home" }
                        Lamp { lit: Sys.night; text: "night light" }
                    }
                }
            }
        }

        // ---- e2 AUDIO: both defaults' volume as rings, and which devices they are ----
        Slot {
            i: 7
            Column {
                y: 4
                width: parent.width
                Row {
                    spacing: 34
                    Vol { node: Sys.sink; label: "out" }
                    Vol { node: Sys.mic; label: "in" }
                }
                Lb { topPadding: 20; width: parent.width; elide: Text.ElideRight; px: 11; text: root.split(Sys.sink).port }
                Lb {
                    readonly property var d: root.split(Sys.mic)
                    topPadding: 6
                    width: parent.width
                    elide: Text.ElideRight
                    px: 10
                    color: Theme.mute
                    text: d.card ? `${d.port} · ${d.card}` : d.port
                }
            }
        }

        // ---- a3 POWER: the mode, and the four it could be ----
        Slot {
            i: 8
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 30
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    D { text: Rules.modes[Rules.mode].short; font.pixelSize: 76 }
                    Lb { topPadding: 12; px: 11; text: Rules.modes[Rules.mode].name + (Rules.store.ultra ? ` · ${Rules.rates[0]} hz · still` : " · cpu only") }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Repeater {
                        model: Rules.modes.slice(0, Rules.modeCount)
                        Lamp { required property var modelData; required property int index; lit: index === Rules.mode; text: modelData.name }
                    }
                }
            }
        }

        // ---- b3 INPUT: key repeat and scroll ----
        Slot {
            i: 9
            Column {
                y: 10
                Row {
                    spacing: 40
                    Stat { v: Rules.store.repeatDelay; label: "delay ms" }
                    Stat { v: Rules.store.repeatRate; label: "rate /s" }
                    Stat { v: Rules.store.scroll; label: "scroll" }
                }
                Row {
                    topPadding: 22
                    spacing: 18
                    Lamp { lit: Rules.store.natural; text: "natural" }
                    Lamp { lit: Rules.store.tap; text: "tap" }
                    Lamp { lit: Rules.store.flat; text: "flat" }
                }
            }
        }

        // ---- c3 IDLE: what happens first, and the hour as dots that dim at every step (2 min a dot) ----
        Slot {
            i: 10
            Column {
                y: 6
                Row {
                    spacing: 14
                    D { id: idleN; text: root.nextIdle ? root.nextIdle[1] : "—"; font.pixelSize: 64 }
                    Lb { anchors.baseline: idleN.baseline; px: 13; text: root.nextIdle ? "min · " + root.nextIdle[0] : "nothing sleeps" }
                }
                Row {
                    topPadding: 22
                    spacing: 6
                    Repeater {
                        model: 31
                        Rectangle {
                            required property int index
                            readonly property int lvl: root.idles.filter(x => x[1] && x[1] <= index * 2).length
                            width: 7
                            height: 7
                            radius: 3.5
                            color: [Theme.fg, Theme.grey, Theme.mute, Theme.s3][lvl]
                        }
                    }
                }
                Lb {
                    topPadding: 14
                    px: 10
                    color: Theme.mute
                    text: root.idles.filter(x => x !== root.nextIdle).map(x => `${x[0]} ${x[1] ? x[1] + " min" : "never"}`).join(" · ")
                        + (Sys.caffeine ? " · caffeine" : "")
                }
            }
        }

        // ---- d3 LIGHTS: the case at its level, a dot per lit part in the colour it shows ----
        Slot {
            i: 11
            Column {
                y: 6
                Row {
                    spacing: 14
                    D { id: litN; text: !Rgb.parts.length ? "—" : !Rgb.store.on ? "OFF" : Rgb.lit ? Rgb.store.level + "%" : "DARK"; font.pixelSize: 64 }
                    Lb {
                        anchors.baseline: litN.baseline
                        px: 13
                        text: !Rgb.parts.length ? "openrgb isn't answering" : Rgb.gaming ? "game mode · case" : Rgb.night ? "night hours · case" : root.tone + " · case"
                    }
                }
                Row {
                    topPadding: 22
                    spacing: 8
                    Repeater {
                        model: Math.min(root.leds, 24)
                        Rectangle { width: 12; height: 12; radius: 6; color: Rgb.lit ? Rgb.base : Theme.s3 }
                    }
                }
                Lb {
                    topPadding: 14
                    px: 10
                    color: Theme.mute
                    text: [Rgb.screen ? `kraken ${Rgb.shown}` + (Rgb.shown === "dial" && Rgb.stats.cpu != null ? ` · ${Rgb.stats.cpu}° / ${Rgb.stats.gpu}°` : "") : "",
                           `${Rgb.parts.length} parts`, Govee.seen ? `lamp ${Govee.lit ? Govee.store.level + "%" : "off"}` : ""].filter(s => s).join(" · ")
                }
            }
        }

        // ---- e3 SHELL: the rice's mark and name ----
        Slot {
            i: 12
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 30
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 92
                    height: 92
                    Ring { anchors { fill: parent; margins: 6 } n: 12; dot: 8; f: 1 }
                    Rectangle { anchors.centerIn: parent; width: 24; height: 24; radius: 12; color: Theme.fg }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    D { text: root.meta.name ?? "GLYPH"; font.pixelSize: 52 }
                    Lb { topPadding: 12; px: 11; text: `quickshell · dnd ${Theme.state.dnd ? "on" : "off"}` }
                }
            }
        }

        // ---- the keys ----
        Row {
            x: 72
            anchors { bottom: parent.bottom; bottomMargin: 36 }
            spacing: 40
            Hint { k: "←↑↓→"; text: "module" }
            Hint { k: "↵"; text: "open it" }
            Hint { k: "tab"; text: "straight to its keys" }
            Hint { k: "click"; text: "open" }
        }
        Hint {
            anchors { right: parent.right; rightMargin: 72; bottom: parent.bottom; bottomMargin: 36 }
            k: "esc"
            text: "close"
            TapHandler { onTapped: root.close() }
        }

        // NieR's edge darkening: clear inside an ellipse 80 % × 90 % of the canvas out to 58 % of the way, then into the
        // dark. Shapes' gradient is round — drawn round in a space squashed into the ellipse
        Shape {
            id: vig
            readonly property real rx: parent.width * 0.8
            readonly property real ry: parent.height * 0.9
            width: parent.width
            height: parent.height * rx / ry // the ellipse is a circle of rx here
            transform: Scale { yScale: vig.ry / vig.rx }
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: vig.width / 2
                    centerY: vig.height / 2
                    centerRadius: vig.rx
                    focalX: vig.width / 2
                    focalY: vig.height / 2
                    GradientStop { position: 0.58; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, Theme.light ? 0.2 : 0.62) }
                }
                startX: 0
                startY: 0
                PathLine { x: vig.width; y: 0 }
                PathLine { x: vig.width; y: vig.height }
                PathLine { x: 0; y: vig.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    // a module in its cell of the wall
    component Slot: Module {
        required property int i
        readonly property var d: root.mods[i]
        x: 120 + d.c * 482
        y: 130 + d.r * 291
        width: 458 + (d.w - 1) * 482
        tag: d.tag
        name: d.name
        on: root.sel === i
        onOpened: root.enter(i)
    }
    // numbers in Doto at 700: at 900 its dots fuse at these sizes
    component D: Num { font.weight: Font.Bold; font.variableAxes: ({ "ROND": 100, "wght": 700 }) }
    // a number and what it is
    component Stat: Column {
        property var v
        property string label
        D { text: parent.v; font.pixelSize: 52 }
        Lb { topPadding: 12; text: parent.label; px: 11 }
    }
    // on: a lit dot; off: a hollow one
    component Dot: Rectangle {
        property bool lit
        width: 8
        height: 8
        radius: 4
        color: lit ? Theme.fg : "transparent"
        border { width: lit ? 0 : 1.5; color: Theme.mute }
    }
    component Lamp: Row {
        property alias lit: dot.lit
        property alias text: l.text
        spacing: 8
        Dot { id: dot; anchors.verticalCenter: parent.verticalCenter }
        Lb { id: l; px: 10 }
    }
    // a volume ring: lit to the level, dark when muted
    component Vol: Row {
        id: vol
        property var node
        property string label
        readonly property real v: node?.audio?.volume ?? 0
        readonly property bool muted: node?.audio?.muted ?? true
        spacing: 14
        Item {
            width: 92
            height: 92
            Ring { anchors { fill: parent; margins: 4 } n: 36; dot: 4; f: vol.muted ? 0 : vol.v }
            D { anchors.centerIn: parent; text: Math.round(vol.v * 100); font.pixelSize: 30; color: vol.muted ? Theme.mute : Theme.fg }
        }
        Lb { anchors.verticalCenter: parent.verticalCenter; text: vol.muted ? vol.label + " · muted" : vol.label; px: 11 }
    }
    component Hint: Row {
        property string k
        property alias text: hl.text
        spacing: 8
        Lb { text: parent.k; px: 13; color: Theme.fg }
        Lb { id: hl; px: 13 }
    }
}
