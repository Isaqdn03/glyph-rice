import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components
import qs.services
import qs.settings

// local: prefs as a console ("D · Console", prefs-console-handoff.md in the repo root). It opens on the wall: all 13
// sections at once, fixed modules on a lettered 5 × 3 grid, each a tiny instrument and its live numbers — nothing on it
// is made up. State by brightness: lit dots and white type are on, hollow and grey are off; the one accent is the
// selected module's dot. ←↑↓→ move, ↵ / tab / click open, esc closes.
// Open, a module fills a frame — header, the object it sets on the left, its keys on the right — with the other modules
// in a dock under it: tab walks the keys, [ ] the modules, esc goes back to the wall.
// Same API as Prefs.qml (open, close, toggle, wallRequested), shell.qml swaps it in. A screen narrower than the wall (the 16:10
// laptop) gets the old Prefs instead (narrowRequested)
PanelWindow {
    id: root

    signal wallRequested
    signal narrowRequested

    // the wall, left to right and down: c, r — top-left cell, w — cells wide
    readonly property var mods: [
        { tag: "a1", name: "home", c: 0, r: 0, w: 1 },
        { tag: "b1", name: "deck", c: 1, r: 0, w: 1 },
        { tag: "c1", name: "bar", c: 2, r: 0, w: 1 },
        { tag: "d1", name: "look", c: 3, r: 0, w: 1 },
        { tag: "e1", name: "style", c: 4, r: 0, w: 1 },
        { tag: "a2", name: "windows", c: 0, r: 1, w: 2 },
        { tag: "c2", name: "display", c: 2, r: 1, w: 2 },
        { tag: "e2", name: "audio", c: 4, r: 1, w: 1 },
        { tag: "a3", name: "power", c: 0, r: 2, w: 1 },
        { tag: "b3", name: "input", c: 1, r: 2, w: 1 },
        { tag: "c3", name: "idle", c: 2, r: 2, w: 1 },
        { tag: "d3", name: "lights", c: 3, r: 2, w: 1 },
        { tag: "e3", name: "shell", c: 4, r: 2, w: 1 }
    ]
    property int sel: 6 // remembered between opens; display first
    property int cx: 2  // the column ↑↓ keep: b1 ↓ a2 ↓ lands on b3, not a3

    function at(c, r) { return mods.findIndex(m => m.r === r && c >= m.c && c < m.c + m.w); }
    // a module's box on the wall, and its middle
    function box(i) {
        const d = mods[i];
        return { x: 120 + d.c * 482, y: 130 + d.r * 291, w: 458 + (d.w - 1) * 482, h: 267 };
    }
    function mid(i) {
        const b = box(i);
        return Qt.point(b.x + b.w / 2, b.y + b.h / 2);
    }
    // its tile in the dock, and the box of an open module
    function dockBox(i) { return { x: 72 + i * (tileW + 12), y: 848, w: tileW, h: 136 }; }
    readonly property var whole: ({ x: 72, y: 110, w: 2436, h: 712 })
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
    // open module i; keys: straight to its first key. -1 — the wall
    property int cur: -1
    property int page: 0 // the module on show: outlives cur on the way back to the wall
    function enter(i, keys) {
        const was = cur;
        if (was < 0 && i !== sel) leap(box(i)); // clicked: the frame grows out of that module, not the selected one
        sel = i;
        cx = mods[i].c;
        page = i;
        cur = i;
        if (was >= 0 && was !== i) leap(dockBox(i)); // another module: out of its tile
        stage.forceActiveFocus();
        if (keys) Qt.callLater(firstKey);
    }
    function back() {
        cur = -1;
        stage.forceActiveFocus();
    }
    // [ ] — the next module, round the dock
    function nextModule(d) { enter((cur + d + mods.length) % mods.length); }
    function firstKey() { stage.nextItemInFocusChain(true)?.forceActiveFocus(); }

    // ---- open and close: animates itself (glyph's layers are no_anim in hypr) ----
    property bool shown: false
    readonly property real t: shut.value
    // springs, no bounce (components/Spring), exits quicker than entrances. Periods are Rune's: glide .32/.26
    readonly property real pace: 1.3 // the openings only, not exits or the frame's way round the wall: higher is slower
    readonly property bool still: !Rules.moving
    readonly property real frameT: cur < 0 ? 0.26 : 0.32 * pace
    // one frame: it goes round the wall with the selection and grows into the open module
    readonly property var frameTo: cur < 0 ? box(sel) : whole
    Spring { id: shut; to: root.shown ? 1 : 0; period: root.shown ? 0.32 * root.pace : 0.2; instant: root.still }
    Spring { id: fx; to: root.frameTo.x; period: root.frameT; instant: root.still; epsilon: 0.05 }
    Spring { id: fy; to: root.frameTo.y; period: root.frameT; instant: root.still; epsilon: 0.05 }
    Spring { id: fw; to: root.frameTo.w; period: root.frameT; instant: root.still; epsilon: 0.05 }
    Spring { id: fh; to: root.frameTo.h; period: root.frameT; instant: root.still; epsilon: 0.05 }
    Spring { id: grow; to: root.cur < 0 ? 0 : 1; period: root.frameT; instant: root.still } // wall ↔ module
    // the wall comes in as dots (components/Halftone) when the console opens
    Spring { id: wallIn; to: 1; period: 0.7 * root.pace; instant: root.still }
    property point waveAt // the selected module's middle at open: the arrows move on, the wave's centre stays
    // a layer's copy, pixel for pixel: Qt takes an explicit textureSize as is, it adds neither the Stage's scale nor the screen's
    readonly property real texScale: Theme.s * devicePixelRatio
    function leap(b) {
        fx.jump(b.x);
        fy.jump(b.y);
        fw.jump(b.w);
        fh.jump(b.h);
    }
    function open() {
        pickMon = Hyprland.focusedMonitor?.name ?? "";
        // the wall needs 2580 design px (21:9); a 16:10 stage is 1920 — the old prefs there, until a narrow wall exists
        const s = Quickshell.screens.find(x => x.name === pickMon);
        if (s && s.width / Theme.s < 2580) {
            narrowRequested();
            return;
        }
        cur = -1;
        leap(box(sel));
        grow.jump(0);
        if (t === 0) { // not when reopened on its way out
            waveAt = mid(sel);
            wallIn.jump(0);
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
    readonly property var sorted: names.slice().sort() // DP-1 before DP-2
    readonly property string monModel: Quickshell.screens.find(s => s.name === mon)?.model || mon

    // ---- lists of ids in Theme.state: home's widgets, the deck, the tray (as Prefs.qml). Edit a copy — JsonAdapter writes the file on
    // assignment. They return the new cursor. Widgets are this screen's: with several screens an edit gives it its own set ----
    function list(key) { return key === "widgets" ? Theme.scr(mon, "widgets") : Theme.state[key]; }
    function edit(key, f) {
        const a = list(key).slice();
        f(a);
        if (key === "widgets" && (multi || Theme.own(mon)?.widgets)) Theme.setScr(mon, "widgets", a);
        else Theme.state[key] = a;
    }
    function move(key, i, to) {
        if (to < 0 || to >= list(key).length || to === i) return i;
        edit(key, a => a.splice(to, 0, a.splice(i, 1)[0]));
        return to;
    }
    function cut(key, i) {
        const n = list(key).length;
        if (i >= n) return i;
        edit(key, a => a.splice(i, 1));
        return Math.max(0, Math.min(i, n - 2));
    }
    // ↵ on the selected one: the next of all that isn't there yet. In an empty list — the first free
    function cycle(key, i, all) {
        const a = list(key);
        if (all.every(k => a.includes(k))) return i;
        i = Math.min(i, a.length);
        let j = all.indexOf(a[i]);
        do j = (j + 1) % all.length; while (a.includes(all[j]));
        edit(key, b => b[i] = all[j]);
        return i;
    }
    // there — take it out; not there — put it after the selected one
    function flip(key, w, cur) {
        const a = list(key), i = a.indexOf(w);
        if (i >= 0) {
            edit(key, b => b.splice(i, 1));
            return Math.max(0, Math.min(i < cur ? cur - 1 : cur, a.length - 2));
        }
        const at = Math.min(cur + 1, a.length);
        edit(key, b => b.splice(at, 0, w));
        return at;
    }
    // a list in focus: ←→ select, shift ←→ move, ↵ / space next kind, del drop. -1 — not its key
    function nav(e, key, cur, all) {
        const n = list(key).length, d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0;
        if (d && (e.modifiers & Qt.ShiftModifier)) return move(key, cur, cur + d);
        if (d) return n ? (cur + d + n) % n : 0;
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) return cycle(key, cur, all);
        if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) return cut(key, cur);
        return -1;
    }

    // ---- what the modules read ----
    // home's bento on this screen, packed like Home: left to right, a widget that doesn't fit its row starts the next
    readonly property var cells: {
        let row = 0, col = 0;
        return Theme.scr(mon, "widgets").map((w, i) => {
            const span = Theme.kinds[w] ?? 1;
            if (col + span > 3) {
                row++;
                col = 0;
            }
            const c = { id: w, i, row, col, span, fits: row < 3 };
            col += span;
            return c;
        });
    }
    readonly property int used: cells.filter(c => c.fits).reduce((a, c) => a + c.span, 0)
    readonly property int offGrid: cells.filter(c => !c.fits).length
    readonly property var rounds: ["weather", "cpu", "ram", "gpu", "disk", "battery", "buds", "cava"] // as Prefs draws them

    readonly property var disp: Rules.mons.find(x => x.name === mon) ?? Rules.mon
    readonly property var ddc: Ddc.screens.find(x => x.ready && x.out === disp.name) ?? null
    readonly property var want: Rules.want(disp) // its scale (0 — auto) and refresh as set
    readonly property bool ownBri: Sys.hasBri && disp.name === Rules.mon.name // a built-in panel's backlight
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

    readonly property string styleName: Theme.state.paint === "scheme" ? (Theme.pal.group === "more" ? "" : Theme.pal.group + " ") + Theme.pal.name
        : Theme.state.paint === "wall" && Theme.tones.length ? Theme.pal.name : "nothing"
    readonly property string styleFrom: Theme.state.paint === "scheme" ? `palette · ${Theme.pal.group}` : Theme.state.paint === "wall" && Theme.tones.length ? "from the wallpaper" : "black · white dots · one red"
    readonly property var swatches: [Theme.fg, Theme.grey, Theme.mute, Theme.s3, Theme.s2, Theme.s1, Theme.bg, Theme.accent].concat(Qt.colorEqual(Theme.accent, Theme.red) ? [] : [Theme.red])

    // the screen's shape, by the nearest usual one: 2752 × 1152 → 21 : 9
    function aspect(w, h) {
        const all = [[32, 9], [21, 9], [16, 9], [16, 10], [3, 2], [4, 3]];
        return all.reduce((a, b) => Math.abs(b[0] / b[1] - w / h) < Math.abs(a[0] / a[1] - w / h) ? b : a).join(" : ");
    }

    // the dock: each module's key value and what it is
    readonly property string clockText: Theme.hh(clock.date) + ":" + Qt.formatTime(clock.date, "mm")
    readonly property var dockVals: [
        [`${used}/9`, "cells"],
        [`${Theme.state.deck.length}/${Theme.decks.length}`, "sections"],
        [`${Theme.state.bar.filter(b => Theme.bars.includes(b)).length}/${Theme.bars.length}`, "tray"],
        [clockText, "clock"],
        [({ wall: "WALL", scheme: "PAL" })[Theme.state.paint] ?? "NONE", styleName],
        [`${Rules.store.gapsIn}/${Rules.store.gapsOut}`, "gaps"],
        [disp.hz, "hz · " + disp.name],
        [Math.round(Sys.vol * 100), Sys.muted ? "out · muted" : "out %"],
        [Rules.modes[Rules.mode].short, "mode"],
        [Rules.store.repeatDelay, "delay ms"],
        [Rules.store.dpmsAfter || "—", Rules.store.dpmsAfter ? "min to dark" : "never dark"],
        [!Rgb.parts.length ? "—" : !Rgb.store.on ? "OFF" : Rgb.lit ? Rgb.store.level + "%" : "DARK", "level"],
        [meta.name ?? "GLYPH", "running"]
    ]
    // under the open module's name
    readonly property var heads: [homePage.head, deckPage.head, barPage.head, "desktop · the home screen, live", stylePage.head,
        "desktop · hyprland", `system · ${disp.name} ${disp.model ?? ""}`, audioPage.head,
        `system · ${Rules.modes[Rules.mode].name}${Rules.store.ultra ? " · no motion · no blur" : " · cpu profile only"}`,
        "system · keyboard · mouse · touchpad", "system · minutes without input · hypridle", lightsPage.head, "more · quickshell"]

    SystemClock { id: clock; enabled: root.visible; precision: SystemClock.Minutes }
    readonly property string who: (Theme.state.name || Quickshell.env("USER")).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    readonly property string hello: { const h = clock.date.getHours(); return h < 5 ? "good night" : h < 12 ? "good morning" : h < 18 ? "good afternoon" : "good evening"; }
    property bool dim: false // look's colon, off half the time when the home clock blinks
    Timer { running: root.visible && Theme.state.blink; interval: 500; repeat: true; onTriggered: root.dim = !root.dim; onRunningChanged: root.dim = false }

    // SHELL's mark on a 25 × 25 matrix cut to a circle: 16 points on a ring and a disc
    readonly property var matrix: {
        const c = 12, lit = {}, out = [];
        for (let k = 0; k < 16; k++) {
            const a = k / 16 * Math.PI * 2;
            lit[Math.round(c + 9.5 * Math.cos(a)) + "," + Math.round(c + 9.5 * Math.sin(a))] = true;
        }
        for (let y = 0; y < 25; y++)
            for (let x = 0; x < 25; x++) {
                const d = Math.hypot(x - c, y - c);
                if (d <= 12.4) out.push({ x: x * 16 + 3, y: y * 16 + 3, on: d <= 2.6 || !!lit[x + "," + y] });
            }
        return out;
    }
    // "switch shell" only with somewhere to go: other rice.json folders next to this one
    property int shells: 1
    Process {
        running: root.visible
        command: [Quickshell.env("HOME") + "/.config/quickshell/rice/rice", "list"]
        stdout: StdioCollector { onStreamFinished: root.shells = text.trim().split("\n").length }
    }

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
        // keys a focused key, knob or bank doesn't take end up here
        Keys.onPressed: e => {
            const k = e.key, go = k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space;
            if (k === Qt.Key_Escape) root.cur < 0 ? root.close() : root.back();
            else if (root.cur < 0) {
                if (k === Qt.Key_Left || k === Qt.Key_H) root.step(-1, 0);
                else if (k === Qt.Key_Right || k === Qt.Key_L) root.step(1, 0);
                else if (k === Qt.Key_Up || k === Qt.Key_K) root.step(0, -1);
                else if (k === Qt.Key_Down || k === Qt.Key_J) root.step(0, 1);
                else if (go || k === Qt.Key_Tab) root.enter(root.sel, k === Qt.Key_Tab);
                else return;
            } else if (k === Qt.Key_BracketLeft || k === Qt.Key_BracketRight) root.nextModule(k === Qt.Key_BracketLeft ? -1 : 1);
            else if (k === Qt.Key_M && root.cur === 7) audioPage.mute();
            else if (stage.activeFocus && (go || k === Qt.Key_Tab || k === Qt.Key_Down || k === Qt.Key_Right)) root.firstKey();
            // arrows off a plain key: the key before or after it
            else if (k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Left || k === Qt.Key_Right)
                (stage.Window.activeFocusItem ?? stage).nextItemInFocusChain(k === Qt.Key_Down || k === Qt.Key_Right)?.forceActiveFocus();
            else return;
            e.accepted = true;
        }

        // drawn at 2580 × 1080: on a bigger stage (32:9, or this screen at a lower scale than the first) it sits in the middle
        Item {
            x: Math.max(0, (parent.width - width) / 2)
            y: Math.max(0, (parent.height - height) / 2)
            width: 2580
            height: 1080

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
                D { id: hc; text: root.clockText; font.pixelSize: 34 }
            }

            // ---- the wall ----
            Item {
                id: wall
                anchors.fill: parent
                visible: root.cur < 0 || grow.value < 1
                enabled: root.cur < 0
                opacity: 1 - grow.value
                // the camera goes in with the frame
                transform: Scale {
                    origin.x: root.mid(root.page).x
                    origin.y: root.mid(root.page).y
                    xScale: 1 + 0.03 * grow.value
                    yScale: xScale
                }
                layer.enabled: wallIn.running
                layer.smooth: true
                layer.textureSize: Qt.size(width * root.texScale, height * root.texScale)
                layer.effect: Halftone { progress: wallIn.value; origin: root.waveAt }

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

            }

            // ---- a module, open: a solid sheet as big as the frame just now, so the module shows only inside it as it grows ----
            Item {
                id: sheet
                x: fx.value
                y: fy.value
                width: fw.value
                height: fh.value
                clip: fw.running
                visible: root.cur >= 0 || grow.value > 0 // never `enabled: false` on the way back: keys and knobs grey out with it
                opacity: root.cur >= 0 ? 1 : grow.value // solid on the way out, fading into the wall on the way back

                Rectangle { anchors.fill: parent; color: Theme.bg }

                Item {
                    id: frame
                    readonly property var m: root.mods[root.page]
                    // stays where it is on screen while the sheet moves over it
                    x: root.whole.x - sheet.x
                    y: root.whole.y - sheet.y
                    width: root.whole.w
                    height: root.whole.h

                    Row {
                        x: 40
                        y: 30
                        spacing: 24
                        Lb { anchors.baseline: title.baseline; text: frame.m.tag; px: 13; color: Theme.mute }
                        D { id: title; text: frame.m.name.toUpperCase(); font.pixelSize: 88 }
                        Lb { anchors.baseline: title.baseline; text: root.heads[root.page]; px: 13 }
                    }
                    Lb {
                        anchors { right: parent.right; rightMargin: 40 }
                        y: 44
                        text: "‹ back to the wall · esc"
                        px: 13
                        color: Theme.fg
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.back() }
                    }

                    // ---- a2 WINDOWS: the desk to scale — the bar where it sits, two windows in the gaps, border and rounding
                    // as set; they slide when motion is on ----
                    Page {
                        i: 5
                        Item {
                            x: 40
                            y: 150
                            width: 1180
                            height: 540
                            ConsoleScreen {
                                id: wdesk
                                ctl: root
                                Repeater {
                                    model: 2
                                    Item {
                                        id: wnd
                                        required property int index
                                        readonly property real w: (wdesk.width - (wdesk.across ? wdesk.o : wdesk.l) - wdesk.o - 2 * wdesk.g) / 2
                                        x: (wdesk.across ? wdesk.o : wdesk.l) + index * (w + 2 * wdesk.g)
                                        y: wdesk.across ? wdesk.l : wdesk.o
                                        width: w
                                        height: wdesk.height - y - wdesk.o
                                        Behavior on x { enabled: Rules.store.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                                        Behavior on y { enabled: Rules.store.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                                        Behavior on width { enabled: Rules.store.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                                        Behavior on height { enabled: Rules.store.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                                        RectangularShadow {
                                            visible: Rules.store.shadow
                                            anchors.fill: parent
                                            offset.y: 8
                                            blur: 24
                                            radius: win.radius
                                            color: Qt.rgba(0, 0, 0, 0.9)
                                        }
                                        Rectangle {
                                            id: win
                                            anchors.fill: parent
                                            radius: Theme.state.rounding * wdesk.k
                                            color: Theme.s1
                                            border { width: Rules.store.border ? Math.max(1, Rules.store.border * wdesk.k) : 0; color: wnd.index ? Theme.s3 : Theme.edge }
                                            Column {
                                                x: 24
                                                y: 22
                                                width: parent.width - 48
                                                spacing: 10
                                                Lb { text: wnd.index ? "zen" : "kitty"; px: 11; color: wnd.index ? Theme.mute : Theme.fg }
                                                Repeater {
                                                    model: [0.7, 0.45, 0.85, 0.3, 0.6, 0.5]
                                                    Rectangle { required property real modelData; width: parent.width * modelData; height: 5; color: Theme.s3 }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Lb { y: 500; px: 11; color: Theme.mute; text: `to scale · ${root.aspect(root.disp.lw, root.disp.lh)} · ${root.disp.name}${wdesk.hides ? " · the bar hides" : ""} · the knobs drive it` }
                        }

                        Column {
                            x: 1290
                            y: 150
                            spacing: 36
                            Block {
                                title: "knobs"
                                note: "drag round · scroll · ←→"
                                Row {
                                    spacing: 56
                                    Knob { label: "gaps in"; to: 30; value: Rules.store.gapsIn; onMoved: v => { Rules.store.gapsIn = v; Theme.apply(); } }
                                    Knob { label: "gaps out"; to: 60; value: Rules.store.gapsOut; onMoved: v => { Rules.store.gapsOut = v; Theme.apply(); } }
                                    Knob { label: "border"; to: 6; value: Rules.store.border; onMoved: v => { Rules.store.border = v; Theme.apply(); } }
                                    Knob { label: "rounding"; to: 40; value: Theme.state.rounding; onMoved: v => Theme.state.rounding = v } // shell.qml applies it
                                    Knob { label: "panels %"; to: 100; step: 5; value: Theme.state.corners; onMoved: v => Theme.state.corners = v }
                                }
                            }
                            Block {
                                title: "effects"
                                Row {
                                    spacing: 12
                                    Key { text: "blur"; on: Rules.store.blur; onHit: { Rules.store.blur = !on; Theme.apply(); } }
                                    Key { text: "shadow"; on: Rules.store.shadow; onHit: { Rules.store.shadow = !on; Theme.apply(); } }
                                    Key { text: "motion"; on: Rules.store.motion; onHit: { Rules.store.motion = !on; Rules.motion(); } }
                                }
                            }
                            // local: what game mode leaves alone (Rules.store.game*); dnd — only auto game mode sets it
                            Block {
                                title: "in a game, keep"
                                note: "lamp off = game mode drops it"
                                Row {
                                    spacing: 12
                                    Key { text: "gaps"; on: Rules.store.gameGaps; onHit: { Rules.store.gameGaps = !on; Theme.apply(); } }
                                    Key { text: "motion"; on: Rules.store.gameMotion; onHit: { Rules.store.gameMotion = !on; Rules.motion(); } }
                                    Key { text: "blur"; on: Rules.store.gameBlur; onHit: { Rules.store.gameBlur = !on; Theme.apply(); } }
                                    Key { text: "shadow"; on: Rules.store.gameShadow; onHit: { Rules.store.gameShadow = !on; Theme.apply(); } }
                                    Key { text: "dnd"; on: Rules.store.gameDnd; onHit: Rules.store.gameDnd = !on }
                                }
                            }
                        }
                    }

                    // ---- c2 DISPLAY: the screens as hypr placed them (click picks, drag moves — it docks to a neighbour,
                    // Rules.dock/place), the picked one's brightness, size, scale and rate; night light for all ----
                    Page {
                        i: 6
                        Item {
                            x: 40
                            y: 150
                            width: 1180
                            height: 540

                            Item {
                                id: dmap
                                readonly property var ms: Rules.mons
                                // a screen being dragged: where it would land (logical px); held there until hypr answers
                                property string held: ""
                                property var at: null
                                onMsChanged: held = ""
                                readonly property real x0: Math.min(...ms.map(m => m.x))
                                readonly property real y0: Math.min(...ms.map(m => m.y))
                                readonly property real bw: Math.max(...ms.map(m => m.x + m.lw)) - x0
                                readonly property real bh: Math.max(...ms.map(m => m.y + m.lh)) - y0
                                readonly property real k: Math.min(width / bw, height / bh)
                                width: 600
                                height: 502
                                Repeater {
                                    model: dmap.ms
                                    Rectangle {
                                        id: sc
                                        required property var modelData
                                        readonly property bool on: modelData.name === root.disp.name
                                        readonly property var p: dmap.held === modelData.name && dmap.at ? dmap.at : modelData
                                        x: (p.x - dmap.x0) * dmap.k + 3
                                        y: (p.y - dmap.y0) * dmap.k + 3
                                        z: dmap.held === modelData.name ? 1 : 0
                                        width: modelData.lw * dmap.k - 6
                                        height: modelData.lh * dmap.k - 6
                                        color: Theme.bg
                                        border { width: on ? 1.5 : 1; color: on ? Theme.fg : Theme.mute }
                                        Behavior on border.color { ColorAnimation { duration: Theme.t } }
                                        Image {
                                            anchors { fill: parent; margins: 2 }
                                            fillMode: Image.Tile
                                            source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12"><circle cx="6" cy="6" r="1.3" fill="#${Theme.hex(sc.on ? Theme.s3 : Theme.s2)}"/></svg>`)
                                        }
                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 12
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: scN.implicitWidth + 20
                                                height: scN.implicitHeight
                                                color: Theme.bg
                                                D { id: scN; anchors.centerIn: parent; text: sc.modelData.name; font.pixelSize: 44; color: sc.on ? Theme.fg : Theme.grey }
                                            }
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: scL.implicitWidth + 16
                                                height: scL.implicitHeight + 4
                                                color: Theme.bg
                                                Lb { id: scL; anchors.centerIn: parent; px: 11; color: sc.on ? Theme.fg : Theme.grey; text: `${sc.modelData.model} · ${sc.modelData.w} × ${sc.modelData.h} @ ${sc.modelData.hz}` }
                                            }
                                        }
                                        TapHandler { onTapped: root.pickMon = sc.modelData.name }
                                        HoverHandler { cursorShape: root.multi ? Qt.OpenHandCursor : Qt.PointingHandCursor }
                                        // drag: it docks to a neighbour (Rules.dock); dropped — Rules.place. Not while hypr hasn't
                                        // answered the last drop (it would count from old places). Untargeted, the shift is in
                                        // window px, and the stage is scaled
                                        DragHandler {
                                            target: null
                                            enabled: root.multi && (!dmap.held || active)
                                            cursorShape: Qt.ClosedHandCursor
                                            onActiveTranslationChanged: {
                                                if (!active) return;
                                                const m = sc.modelData, k = Theme.s * dmap.k;
                                                dmap.at = Rules.dock({ x: m.x + activeTranslation.x / k, y: m.y + activeTranslation.y / k, w: m.lw, h: m.lh },
                                                                     dmap.ms.filter(o => o.name !== m.name).map(o => ({ x: o.x, y: o.y, w: o.lw, h: o.lh })), 16 / dmap.k);
                                            }
                                            onActiveChanged: {
                                                const m = sc.modelData;
                                                if (active) {
                                                    root.pickMon = m.name;
                                                    dmap.at = null;
                                                    dmap.held = m.name;
                                                    return;
                                                }
                                                if (dmap.at && (dmap.at.x !== m.x || dmap.at.y !== m.y)) Rules.place(m.name, dmap.at.x, dmap.at.y);
                                                else dmap.held = "";
                                            }
                                        }
                                    }
                                }
                            }
                            Lb { y: 520; px: 11; color: Theme.mute; text: root.multi ? "as hyprland placed them · drag one to move it" : "as hyprland placed it" }

                            // brightness: an external screen over DDC (services/Ddc), a built-in panel's backlight; else none
                            Knob {
                                x: 700
                                enabled: !!root.ddc || root.ownBri
                                size: 300
                                n: 44
                                numPx: 100
                                live: true
                                label: root.ddc ? `brightness · ddc · ${root.disp.name}` : root.ownBri ? `brightness · ${root.disp.name}` : `brightness · no ddc on ${root.disp.name}`
                                value: root.ddc ? Math.round(root.ddc.value * 100) : root.ownBri ? Math.round(Sys.bri * 100) : 0
                                onMoved: v => root.ddc ? root.ddc.set(v / 100) : Sys.setBri(v / 100)
                            }
                            Column {
                                x: 700
                                y: 400
                                D { text: `${root.disp.lw}×${root.disp.lh}`; font.pixelSize: 48 }
                                Lb { topPadding: 12; px: 11; text: `logical · ${root.want.scale ? "" : "auto · "}× ${root.disp.scale} · ${root.disp.hz} hz` }
                            }
                        }

                        Item {
                            x: 1290
                            y: 150
                            Column {
                                spacing: 36
                                Block {
                                    title: "screen"
                                    Bank { minW: 84; opts: root.sorted; cur: root.sorted.indexOf(root.mon); onPicked: i => root.pickMon = root.sorted[i] }
                                }
                                Block {
                                    title: "scale"
                                    Bank {
                                        minW: 84
                                        opts: Rules.scales
                                        cur: root.want.scale ? Rules.scales.indexOf(String(root.want.scale)) : 0
                                        onPicked: i => Rules.set(root.disp.name, "scale", i ? +Rules.scales[i] : 0)
                                    }
                                }
                                Block {
                                    title: "refresh"
                                    note: "hz"
                                    Bank {
                                        minW: 84
                                        opts: root.disp.rates.map(String)
                                        cur: root.disp.rates.indexOf(root.want.refresh)
                                        onPicked: i => Rules.set(root.disp.name, "refresh", root.disp.rates[i])
                                    }
                                }
                            }
                            Column {
                                x: 600
                                spacing: 36
                                Block {
                                    title: "on this screen"
                                    Row {
                                        spacing: 12
                                        Key { text: "bar"; on: Theme.scr(root.mon, "bar"); onHit: Theme.setScr(root.mon, "bar", !on) }
                                        Key { text: "home"; on: Theme.scr(root.mon, "home"); onHit: Theme.setScr(root.mon, "home", !on) }
                                        // every screen's own place, scale and rate forgotten — back to the hypr config (Rules.forget)
                                        Key { text: "hypr config"; mom: true; enabled: Object.keys(Rules.store.outs).length > 0; onHit: Rules.forget() }
                                    }
                                }
                                Block {
                                    title: "all screens"
                                    Row {
                                        spacing: 34
                                        Key { anchors.verticalCenter: parent.verticalCenter; text: "night light"; on: Sys.night; onHit: Sys.toggleNight() }
                                        Knob {
                                            anchors.verticalCenter: parent.verticalCenter
                                            beside: true
                                            size: 120
                                            n: 26
                                            numPx: 28
                                            label: "warmth · k"
                                            from: 2500
                                            to: 6500
                                            step: 100
                                            value: Rules.store.warmth
                                            onMoved: v => {
                                                Rules.store.warmth = v;
                                                if (Rules.store.night) Rules.night();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- a3 POWER: the mode as four big keys, dots for how hard each pushes; what it changes, honestly: on a
                    // desktop there's no main screen, so ultra leaves every rate alone (Rules.setMode) ----
                    Page {
                        i: 8
                        Column {
                            x: 40
                            y: 150
                            spacing: 34
                            Block {
                                title: "mode"
                                note: "dots = how hard it pushes"
                                Row {
                                    id: modes
                                    property int at: 0
                                    spacing: 6
                                    activeFocusOnTab: true
                                    onActiveFocusChanged: if (activeFocus) at = Rules.mode
                                    Keys.onPressed: e => {
                                        const d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0;
                                        if (d) at = Math.max(0, Math.min(Rules.modeCount - 1, at + d));
                                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) Rules.setMode(at);
                                        else return;
                                        e.accepted = true;
                                    }
                                    Repeater {
                                        model: Rules.modes.slice(0, Rules.modeCount)
                                        Rectangle {
                                            id: mk
                                            required property var modelData
                                            required property int index
                                            readonly property bool on: index === Rules.mode
                                            readonly property bool ring: modes.activeFocus && index === modes.at
                                            readonly property real r: Theme.corner(10)
                                            width: 270
                                            height: 300
                                            topLeftRadius: index === 0 ? r : 0
                                            bottomLeftRadius: index === 0 ? r : 0
                                            topRightRadius: index === Rules.modeCount - 1 ? r : 0
                                            bottomRightRadius: index === Rules.modeCount - 1 ? r : 0
                                            color: on ? Theme.s2 : Theme.s1
                                            border { width: ring ? 1.5 : 1; color: ring ? Theme.fg : mh.hovered ? Theme.mute : Theme.s3 }
                                            Behavior on color { ColorAnimation { duration: Theme.t } }
                                            RectangularShadow { anchors.fill: lamp; visible: mk.on; radius: 3; blur: 12; color: Theme.fade(Theme.fg, 0.55) }
                                            Rectangle { id: lamp; x: 22; y: 22; width: 60; height: 6; radius: 3; color: mk.on ? Theme.fg : Theme.s3 }
                                            Column {
                                                x: 22
                                                anchors.verticalCenter: parent.verticalCenter
                                                D { text: mk.modelData.short; font.pixelSize: 80; color: mk.on ? Theme.fg : Theme.grey }
                                                Lb { topPadding: 14; text: mk.modelData.name; px: 13; color: mk.on ? Theme.fg : Theme.grey }
                                            }
                                            Row {
                                                x: 22
                                                anchors { bottom: parent.bottom; bottomMargin: 20 }
                                                spacing: 6
                                                Repeater {
                                                    model: 4
                                                    Rectangle {
                                                        required property int index
                                                        width: 10
                                                        height: 10
                                                        radius: 5
                                                        color: index <= mk.index ? mk.on ? Theme.fg : Theme.grey : Theme.s3
                                                    }
                                                }
                                            }
                                            HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    modes.forceActiveFocus();
                                                    modes.at = mk.index;
                                                    Rules.setMode(mk.index);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Lb {
                                px: 11
                                text: Rules.store.ultra ? `ultra · ${Rules.mon.name ? Rules.rates[0] + " hz, " : ""}no motion, no blur, no shadows · your settings come back when you leave`
                                    : "cpu profile only · refresh, motion and looks stay as you set them"
                            }
                        }
                        Column {
                            x: 1290
                            y: 150
                            spacing: 34
                            Block {
                                title: `what ${Rules.modes[Rules.mode].name} changes`
                                note: "yours = left as you set it"
                                Grid {
                                    columns: 2
                                    spacing: 12
                                    Cell { label: "cpu profile"; value: ["SAVER", "SAVER", "BALANCED", "PERFORMANCE"][Rules.mode] }
                                    Cell { label: "refresh rate"; value: Rules.store.ultra && Rules.mon.name ? Rules.rates[0] + " HZ" : "YOURS" }
                                    Cell { label: "motion"; value: Rules.store.ultra ? "OFF" : "YOURS" }
                                    Cell { label: "blur · shadows"; value: Rules.store.ultra ? "OFF" : "YOURS" }
                                }
                            }
                            Block {
                                title: "this machine"
                                Cell { label: "performance profile · power-profiles-daemon"; value: PowerProfiles.hasPerformanceProfile ? "AVAILABLE" : "MISSING" }
                            }
                        }
                    }

                    // ---- b3 INPUT: a key held down, played out at the knobs' values: the first at once, the pause, then the rate ----
                    Page {
                        id: inPage
                        i: 9
                        property int n: 0 // how many have come; 0 — the key is up
                        Timer {
                            running: inPage.visible && root.visible
                            repeat: true
                            interval: inPage.n === 0 ? 700 : inPage.n === 1 ? delayK.v : 1000 / rateK.v
                            onTriggered: inPage.n = (inPage.n + 1) % 41
                        }
                        Column {
                            x: 40
                            y: 150
                            Block {
                                title: "key repeat"
                                note: "played out at your values"
                                Row {
                                    spacing: 40
                                    Rectangle {
                                        width: 200
                                        height: 200
                                        radius: Theme.corner(40)
                                        color: inPage.n ? Theme.fg : Theme.s1
                                        border { width: 1; color: Theme.s3 }
                                        D { anchors.centerIn: parent; text: "A"; font.pixelSize: 96; color: inPage.n ? Theme.ink : Theme.fg }
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 22
                                        Row {
                                            spacing: 16
                                            D { id: dlN; text: Math.round(delayK.v); font.pixelSize: 72 }
                                            Lb { anchors.baseline: dlN.baseline; text: "ms · first pause"; px: 13 }
                                        }
                                        Row {
                                            spacing: 16
                                            D { id: rtN; text: Math.round(rateK.v); font.pixelSize: 72 }
                                            Lb { anchors.baseline: rtN.baseline; text: "a second · after that"; px: 13 }
                                        }
                                    }
                                }
                            }
                            Row {
                                topPadding: 48
                                spacing: 5
                                Repeater {
                                    model: 40
                                    Rectangle { required property int index; width: 24; height: 24; radius: 12; color: index < inPage.n ? Theme.fg : Theme.s2 }
                                }
                            }
                            Lb { topPadding: 20; px: 11; color: Theme.mute; text: "hold a key · the first comes at once, then the pause, then the rate" }
                        }
                        Column {
                            x: 1290
                            y: 150
                            spacing: 30
                            Block {
                                title: "knobs"
                                note: "drag round · scroll · ←→"
                                Row {
                                    spacing: 64
                                    Knob { id: delayK; size: 150; n: 36; label: "delay · ms"; from: 150; to: 600; step: 10; value: Rules.store.repeatDelay; onMoved: v => { Rules.store.repeatDelay = v; Rules.input(); } }
                                    Knob { id: rateK; size: 150; n: 36; label: "rate · /s"; from: 10; to: 60; value: Rules.store.repeatRate; onMoved: v => { Rules.store.repeatRate = v; Rules.input(); } }
                                    Knob { size: 150; n: 36; label: "scroll · %"; from: 10; to: 100; step: 5; value: Rules.store.scroll; onMoved: v => { Rules.store.scroll = v; Rules.input(); } }
                                    Knob { size: 150; n: 36; label: "pointer"; from: -100; to: 100; step: 5; value: Rules.store.sens; onMoved: v => { Rules.store.sens = v; Rules.input(); } }
                                }
                            }
                            Block {
                                title: "pointer"
                                Row {
                                    spacing: 12
                                    Key { minW: 220; text: "natural scroll"; on: Rules.store.natural; onHit: { Rules.store.natural = !on; Rules.input(); } }
                                    Key { minW: 220; text: "tap to click"; on: Rules.store.tap; onHit: { Rules.store.tap = !on; Rules.input(); } }
                                    Key { minW: 220; text: "off while typing"; on: Rules.store.typingOff; onHit: { Rules.store.typingOff = !on; Rules.input(); } }
                                    Key { minW: 220; text: "flat accel"; on: Rules.store.flat; onHit: { Rules.store.flat = !on; Rules.input(); } }
                                }
                            }
                            Block {
                                title: "layout switch"
                                note: "between keyboard layouts"
                                Bank {
                                    minW: 120
                                    opts: Rules.switches.map(s => s[0])
                                    cur: Rules.store.kbSwitch
                                    onPicked: i => {
                                        Rules.store.kbSwitch = i;
                                        Rules.input();
                                    }
                                }
                            }
                        }
                    }

                    // ---- c3 IDLE: the hour as a line of dots that dim at every step, the marks dragged along it (past 60 is
                    // never), the same three on knobs for the keyboard. A mark previews as it moves; hypridle hears on release ----
                    Page {
                        i: 10
                        Item {
                            id: idleLine
                            x: 40
                            y: 150
                            width: 1180
                            height: 540
                            readonly property var at: [lockM.v, dpmsM.v, sleepM.v]
                            Repeater {
                                model: 61
                                Rectangle {
                                    required property int index
                                    readonly property int lvl: idleLine.at.filter(m => m && m <= index).length
                                    x: index * 18
                                    y: 356
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: Sys.caffeine ? Theme.fg : [Theme.fg, Theme.grey, Theme.mute, Theme.s3][lvl]
                                }
                            }
                            // never: an empty ring past the line
                            Rectangle { x: 1112; y: 352; width: 18; height: 18; radius: 9; color: "transparent"; border { width: 1.5; color: Theme.mute } }
                            Repeater {
                                model: [0, 15, 30, 45, 60]
                                Lb { required property int modelData; x: modelData * 18 + 5 - width / 2; y: 396; text: modelData; px: 13 }
                            }
                            Lb { x: 1098; y: 420; text: "never"; px: 11 }
                            Mark { id: lockM; row: 0; label: "lock"; value: Rules.store.lockAfter; onMoved: v => { Rules.store.lockAfter = v; Rules.idle(); } }
                            Mark { id: dpmsM; row: 1; label: "screen off"; value: Rules.store.dpmsAfter; onMoved: v => { Rules.store.dpmsAfter = v; Rules.idle(); } }
                            Mark { id: sleepM; row: 2; label: Rules.hibernateOn ? "sleep · hibernate" : "sleep"; value: Rules.store.sleepAfter; onMoved: v => { Rules.store.sleepAfter = v; Rules.idle(); } }
                            Row {
                                y: 480
                                spacing: 34
                                Repeater {
                                    model: [["awake", Theme.fg], ["locked", Theme.grey], ["dark", Theme.mute], ["asleep", Theme.s3]]
                                    Row {
                                        required property var modelData
                                        spacing: 10
                                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: parent.modelData[1] }
                                        Lb { text: parent.modelData[0]; px: 11 }
                                    }
                                }
                            }
                        }
                        Column {
                            x: 1290
                            y: 150
                            spacing: 32
                            Block {
                                title: "after"
                                note: "drag round · scroll · ←→ a minute · past 60 is never"
                                Row {
                                    spacing: 72
                                    Repeater {
                                        model: [["lock", "lockAfter"], ["screen off", "dpmsAfter"], [Rules.hibernateOn ? "hibernate" : "sleep", "sleepAfter"]]
                                        Knob {
                                            required property var modelData
                                            size: 160
                                            n: 36
                                            numPx: v > 60 ? 26 : 48
                                            text: v > 60 ? "NEVER" : Math.round(v)
                                            label: modelData[0]
                                            from: 1
                                            to: 61
                                            value: Rules.store[modelData[1]] || 61
                                            onMoved: v => {
                                                Rules.store[modelData[1]] = v > 60 ? 0 : v;
                                                Rules.idle();
                                            }
                                        }
                                    }
                                }
                            }
                            Block {
                                title: "right now"
                                Row {
                                    spacing: 18
                                    Key { text: "caffeine"; on: Sys.caffeine; onHit: Sys.caffeine = !on }
                                    Lb { anchors.verticalCenter: parent.verticalCenter; px: 11; color: Theme.mute; text: "stays awake until it's off · ignores the marks" }
                                }
                            }
                            Block {
                                title: "sleep into"
                                Row {
                                    spacing: 4
                                    Key {
                                        last: false
                                        text: "suspend"
                                        on: !Rules.hibernateOn
                                        onHit: {
                                            Rules.store.hibernate = false;
                                            Rules.idle();
                                        }
                                    }
                                    Key {
                                        first: false
                                        enabled: Rules.canHibernate
                                        text: Rules.canHibernate ? "hibernate" : "hibernate · needs swap"
                                        on: Rules.hibernateOn
                                        onHit: {
                                            Rules.store.hibernate = true;
                                            Rules.idle();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- e3 SHELL: the mark lit on a round matrix, the rice's name; do not disturb, reload, switch ----
                    Page {
                        i: 12
                        Row {
                            x: 40
                            y: 150
                            spacing: 70
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 400
                                height: 400
                                Repeater {
                                    model: root.matrix
                                    Rectangle {
                                        required property var modelData
                                        x: modelData.x
                                        y: modelData.y
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: modelData.on ? Theme.fg : Theme.s2
                                    }
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Lb { text: "running now"; px: 13 }
                                D { topPadding: lead + 24; bottomPadding: lead + 24; text: root.meta.name ?? "GLYPH"; font.pixelSize: 160 }
                                Lb { text: root.meta.tagline ?? ""; px: 13 }
                                Lb { topPadding: 10; px: 11; color: Theme.mute; text: `${root.matrix.length} dots · the mark on a round matrix` }
                            }
                        }
                        Column {
                            x: 1290
                            y: 150
                            spacing: 34
                            Block {
                                title: "shell"
                                Row {
                                    spacing: 18
                                    Key { minW: 240; text: "do not disturb"; on: Theme.state.dnd; onHit: Theme.state.dnd = !on }
                                    Lb { anchors.verticalCenter: parent.verticalCenter; px: 11; color: Theme.mute; text: "notifications wait in quick" }
                                }
                            }
                            Block {
                                title: "actions"
                                note: "hollow keys do one thing and spring back"
                                Row {
                                    spacing: 12
                                    Key { minW: 240; mom: true; text: "reload the shell"; onHit: Quickshell.reload(false) }
                                    // only with another shell to go to: rice.json folders next to this one
                                    Key {
                                        minW: 240
                                        mom: true
                                        enabled: root.shells > 1
                                        text: root.shells > 1 ? "switch shell" : `switch shell · only ${(root.meta.name ?? "glyph").toLowerCase()}`
                                        onHit: {
                                            root.close();
                                            Quickshell.execDetached(["qs", "-c", "rice"]);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- d1 LOOK: the home screen as it will be — follows every key on the right ----
                    Page {
                        i: 3
                        Item {
                            x: 40
                            y: 150
                            width: 1180
                            height: 540
                            ConsoleScreen {
                                ctl: root
                                Orb { visible: Theme.state.orb; x: 600; y: 70; scale: 340 / 1100; transformOrigin: Item.TopLeft }
                                Row {
                                    x: 80
                                    y: 64
                                    visible: Theme.state.homeClock
                                    D { id: homeH; text: Theme.hh(clock.date); font.pixelSize: 140 }
                                    D { text: ":"; font.pixelSize: 140; opacity: root.dim ? 0.2 : 1 }
                                    D { text: Qt.formatTime(clock.date, "mm"); font.pixelSize: 140 }
                                    Lb { visible: !Theme.state.clock24; anchors.baseline: homeH.baseline; leftPadding: 14; text: clock.date.getHours() < 12 ? "am" : "pm"; px: 13 }
                                }
                                Lb { x: 86; y: 226; visible: Theme.state.homeClock; text: Qt.locale("en_US").toString(clock.date, "dddd · d MMMM"); px: 13 }
                                Text {
                                    x: 84
                                    y: 290
                                    visible: Theme.state.homeHello
                                    textFormat: Text.StyledText
                                    text: `${root.hello.charAt(0).toUpperCase() + root.hello.slice(1)},<br><font color="${Theme.grey}">${root.who}.</font>`
                                    font { family: Theme.mono; pixelSize: 34 }
                                    lineHeight: 1.25
                                    color: Theme.fg
                                }
                                Item {
                                    anchors { right: parent.right; rightMargin: 56 }
                                    y: 84
                                    width: 190
                                    height: 190
                                    visible: Theme.state.homeBento && Theme.scr(root.mon, "home")
                                    Repeater {
                                        model: root.cells.filter(c => c.fits)
                                        Rectangle {
                                            required property var modelData
                                            x: modelData.col * 66
                                            y: modelData.row * 66
                                            width: modelData.span * 66 - 8
                                            height: 58
                                            radius: modelData.span === 1 && root.rounds.includes(modelData.id) ? 29 : Theme.corner(12)
                                            color: Theme.s1
                                            border { width: 1; color: Theme.s2 }
                                        }
                                    }
                                }
                                // Glyph's edges: the volume on the right, what's playing along the bottom
                                Seg { visible: Theme.state.edges; anchors { right: parent.right; rightMargin: 14 } y: 140; width: 4; height: 114; n: 12; vertical: true; f: Sys.muted ? 0 : Sys.vol }
                                Seg { visible: Theme.state.edges; x: 440; anchors { bottom: parent.bottom; bottomMargin: 12 } width: 234; height: 4; n: 24; f: Media.player?.length > 0 ? Media.position / Media.player.length : 0 }
                            }
                            Lb { y: 500; px: 11; color: Theme.mute; text: `your screen · ${root.aspect(root.disp.lw, root.disp.lh)} · ${root.disp.name} · follows every key on the right` }
                        }
                        Column {
                            x: 1290
                            y: 150
                            spacing: 34
                            Block {
                                title: "home screen"
                                Row {
                                    spacing: 12
                                    Key { minW: 162; text: "light"; on: Theme.light; onHit: Theme.setLight(!Theme.light) }
                                    Key { minW: 162; text: "dot grid"; on: Theme.state.grid; onHit: Theme.state.grid = !on }
                                    Key { minW: 162; text: "orb"; on: Theme.state.orb; onHit: Theme.state.orb = !on }
                                    Key { minW: 162; text: "24 hours"; on: Theme.state.clock24; onHit: Theme.state.clock24 = !on }
                                    Key { minW: 162; text: "blink"; on: Theme.state.blink; onHit: Theme.state.blink = !on }
                                    Key { minW: 162; text: "edges"; on: Theme.state.edges; onHit: Theme.state.edges = !on }
                                }
                            }
                            // local: what home shows — each part, or all of it at once (home/Home.qml)
                            Block {
                                title: "on home"
                                Row {
                                    readonly property bool all: Theme.state.homeClock && Theme.state.homeHello && Theme.state.homeBento
                                    spacing: 12
                                    Key { minW: 162; text: "clock"; on: Theme.state.homeClock; onHit: Theme.state.homeClock = !on }
                                    Key { minW: 162; text: "greeting"; on: Theme.state.homeHello; onHit: Theme.state.homeHello = !on }
                                    Key { minW: 162; text: "widgets"; on: Theme.state.homeBento; onHit: Theme.state.homeBento = !on }
                                    Key {
                                        mom: true
                                        text: parent.all ? "hide all" : "show all"
                                        onHit: {
                                            const v = !parent.all;
                                            Theme.state.homeClock = v;
                                            Theme.state.homeHello = v;
                                            Theme.state.homeBento = v;
                                        }
                                    }
                                }
                            }
                            Block {
                                title: "you"
                                Row {
                                    spacing: 12
                                    // the name in the greeting; empty — $USER
                                    Rectangle {
                                        width: 420
                                        height: 72
                                        radius: Theme.corner(8)
                                        color: Theme.s1
                                        border { width: nameIn.activeFocus ? 1.5 : 1; color: nameIn.activeFocus ? Theme.fg : Theme.s3 }
                                        Lb { x: 16; y: 12; text: "name · empty = $user"; px: 10 }
                                        TextInput {
                                            id: nameIn
                                            x: 16
                                            y: 34
                                            width: parent.width - 32
                                            text: Theme.state.name
                                            maximumLength: 24
                                            activeFocusOnTab: true
                                            font { family: Theme.mono; pixelSize: 20; letterSpacing: 1.2 }
                                            color: Theme.fg
                                            selectionColor: Theme.s3
                                            clip: true
                                            onTextEdited: Theme.state.name = text
                                            Text { visible: !nameIn.text; text: Quickshell.env("USER"); font: nameIn.font; color: Theme.mute }
                                            Keys.onPressed: e => {
                                                if (e.key !== Qt.Key_Escape && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter) return;
                                                stage.forceActiveFocus();
                                                e.accepted = true;
                                            }
                                        }
                                    }
                                    Key {
                                        minW: 220
                                        mom: true
                                        text: "wallpapers ›"
                                        onHit: {
                                            root.close();
                                            root.wallRequested();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- a1 HOME (prefs/ConsoleHome) ----
                    Page {
                        i: 0
                        ConsoleHome { id: homePage; x: 40; y: 150; ctl: root; live: root.page === 0 && sheet.visible && root.shown }
                    }

                    // ---- b1 DECK (prefs/ConsoleDeck) ----
                    Page {
                        i: 1
                        ConsoleDeck { id: deckPage; x: 40; y: 150; ctl: root }
                    }

                    // ---- c1 BAR (prefs/ConsoleBar) ----
                    Page {
                        i: 2
                        ConsoleBar { id: barPage; x: 40; y: 150; ctl: root }
                    }

                    // ---- e1 STYLE (prefs/ConsoleStyle) ----
                    Page {
                        i: 4
                        ConsoleStyle {
                            id: stylePage
                            x: 40
                            y: 150
                            onWallRequested: {
                                root.close();
                                root.wallRequested();
                            }
                        }
                    }

                    // ---- e2 AUDIO (prefs/ConsoleAudio) ----
                    Page {
                        i: 7
                        ConsoleAudio { id: audioPage; x: 40; y: 150; live: root.page === 7 && sheet.visible && root.shown }
                    }

                    // ---- d3 LIGHTS (prefs/ConsoleLights) ----
                    Page {
                        i: 11
                        ConsoleLights { id: lightsPage; x: 40; y: 150; live: root.page === 11 && sheet.visible && root.shown }
                    }
                }

                // on its way back to the wall it still looks alive, but nothing on it takes a press or the wheel
                MouseArea {
                    anchors.fill: parent
                    visible: root.cur < 0
                    acceptedButtons: Qt.AllButtons
                    onWheel: {}
                }
            }

            // the dock: every module, its key value; the open one outlined with the accent dot
            Row {
                x: 72
                y: 848
                visible: root.cur >= 0 || grow.value > 0
                enabled: root.cur >= 0
                opacity: grow.value
                spacing: 12
                Repeater {
                    model: root.mods.length
                    Tile {}
                }
            }

            // ---- the frame: on the selected module, around the open one ----
            Item {
                x: fx.value
                y: fy.value
                width: fw.value
                height: fh.value
                Rectangle { anchors.fill: parent; color: "transparent"; border { width: 1.5; color: Theme.fg } }
                Brackets { anchors.fill: parent; size: 18 + 12 * grow.value; w: 2 + grow.value; color: Theme.fg }
            }

            // ---- the keys ----
            Row {
                x: 72
                anchors { bottom: parent.bottom; bottomMargin: 36 }
                spacing: 40
                Repeater {
                    model: root.cur < 0 ? [["←↑↓→", "module"], ["↵", "open it"], ["tab", "straight to its keys"], ["click", "open"]]
                        : (({
                            0: [["tab", "next key"], ["↵ · space", "press"], ["←→", "pick a cell"], ["shift ←→", "move it"], ["drag", "swap cells"]],
                            1: [["tab", "next key"], ["↵ · space", "press"], ["shift ←→", "reorder"], ["drag", "along the strip"]],
                            2: [["tab", "next key"], ["↵ · space", "press"], ["←→", "along a bank"], ["shift ←→", "reorder the tray"], ["drag", "along the bar"]],
                            3: [["tab", "next key"], ["↵ · space", "press"]],
                            4: [["tab", "next key"], ["←→", "next swatch"], ["hover", "preview it"], ["↵", "set it"]],
                            5: [["tab", "next key"], ["↵ · space", "press"], ["←→", "turn a knob"]],
                            6: [["tab", "next key"], ["↵ · space", "press"], ["←→", "along a bank"], ["drag", "move a screen"]],
                            7: [["tab", "next key"], ["←→", "volume"], ["↑↓", "a device"], ["↵ · space", "press"], ["m", "mute"]],
                            8: [["tab", "the modes"], ["←→", "mode"], ["↵ · space", "set it"]],
                            9: [["tab", "next key"], ["↵ · space", "press"], ["←→", "turn a knob"]],
                            10: [["tab", "next knob"], ["←→", "a minute"], ["drag", "a mark on the line"]],
                            11: [["tab", "next key"], ["↵ · space", "press"], ["←→", "along a bank · the level"]],
                            12: [["tab", "next key"], ["↵ · space", "press"]]
                        })[root.cur] ?? []).concat([["[ ]", "next module"]])
                    Hint { required property var modelData; k: modelData[0]; text: modelData[1] }
                }
            }
            Hint {
                anchors { right: parent.right; rightMargin: 72; bottom: parent.bottom; bottomMargin: 36 }
                k: "esc"
                text: root.cur < 0 ? "close" : "back to the wall"
                TapHandler { onTapped: root.cur < 0 ? root.close() : root.back() }
            }
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

    // an open module's insides: only the one on show, so tab walks its keys alone. The sheet hides it on the wall
    component Page: Item {
        required property int i
        width: 2436
        height: 712
        visible: root.page === i
    }
    readonly property real tileW: (2436 - 12 * 12) / 13
    // a module in the dock: address and dot, name, its key value, what that is
    component Tile: Rectangle {
        id: tile
        required property int index
        readonly property var d: root.mods[index]
        readonly property bool open: root.cur === index
        width: root.tileW
        height: 136
        color: "transparent"
        border { width: open ? 1.5 : 1; color: open ? Theme.fg : th.hovered ? Theme.mute : Theme.s2 }
        Behavior on border.color { ColorAnimation { duration: Theme.t } }
        Lb { x: 14; y: 12; text: tile.d.tag; px: 10; color: Theme.mute }
        Rectangle { anchors { right: parent.right; rightMargin: 14 } y: 15; width: 6; height: 6; radius: 3; color: tile.open ? Theme.accent : Theme.s3 }
        Lb { x: 14; y: 38; text: tile.d.name; px: 11; color: Theme.fg }
        D { x: 14; y: 66; width: parent.width - 28; elide: Text.ElideRight; text: root.dockVals[tile.index][0]; font.pixelSize: 30 }
        Lb { x: 14; anchors { bottom: parent.bottom; bottomMargin: 12 } width: parent.width - 28; elide: Text.ElideRight; text: root.dockVals[tile.index][1]; px: 9; color: Theme.mute }
        HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.enter(tile.index) }
    }
    // a fact in a box: what it is, its value; "YOURS" (left as you set it) stays in mute
    component Cell: Rectangle {
        id: cell
        property string label
        property string value
        width: 547
        height: 124
        color: "transparent"
        border { width: 1; color: Theme.s2 }
        Lb { x: 22; y: 20; text: cell.label; px: 11 }
        D { x: 22; anchors { bottom: parent.bottom; bottomMargin: 20 } text: cell.value; font.pixelSize: 44; color: cell.value === "YOURS" ? Theme.mute : Theme.fg }
    }
    // an idle mark: a stem down to the line, its minutes and name. Drag along the line, past 60 is never (0). It keeps its own v
    // while it moves; moved(v) on release or after 400 ms still
    component Mark: Item {
        id: mk
        property int row
        property string label
        property int value
        property int v: value
        signal moved(int v)
        function put(m) {
            m = m > 60.5 ? 0 : Math.max(1, Math.round(m));
            if (m === v) return;
            v = m;
            wait.restart();
        }
        onValueChanged: if (!ma.pressed && !wait.running) v = value
        Timer { id: wait; interval: 400; onTriggered: if (!ma.pressed && mk.v !== mk.value) mk.moved(mk.v) }
        x: (v || 62) * 18 + 5
        y: 20 + row * 100
        width: 200
        height: 361 - y
        Behavior on x { NumberAnimation { duration: 120 } }
        Rectangle { width: 1; height: parent.height; color: ma.pressed ? Theme.fg : Theme.mute }
        // past the line there's no room on the right: the label goes left of its stem
        Column {
            x: mk.v ? 14 : -14 - width
            D { text: mk.v || "NEVER"; font.pixelSize: 52 }
            Lb { topPadding: 8; text: mk.label; px: 13; color: Theme.fg }
        }
        MouseArea {
            id: ma
            x: mk.v ? 0 : -parent.width
            width: parent.width
            height: 100
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            // where on it the drag took hold, on the line: the mark moves by the drag, it doesn't jump to the pointer
            property real grab: 0
            onPressed: e => grab = mapToItem(mk.parent, e.x, 0).x - mk.x
            onPositionChanged: e => mk.put((mapToItem(mk.parent, e.x, 0).x - grab - 5) / 18)
            onReleased: {
                wait.stop();
                if (mk.v !== mk.value) mk.moved(mk.v);
            }
        }
    }
    // a module in its cell of the wall
    component Slot: Module {
        required property int i
        readonly property var d: root.mods[i]
        x: root.box(i).x
        y: root.box(i).y
        width: root.box(i).w
        tag: d.tag
        name: d.name
        on: root.sel === i
        onOpened: root.enter(i)
    }
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
