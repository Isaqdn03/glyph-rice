import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs

// горячий край: курсор задержался у правого края — быстрые настройки выезжают (Quick.peek). Полоска 2px по нижним 80%:
// верхний угол и полосы прокрутки у края почти не задевает
PanelWindow {
    id: root

    signal triggered

    // local: gone while this monitor shows a fullscreen window. An overlay layer above a fullscreen game blocks
    // Hyprland's direct scanout (CANDIDATE in `hyprctl monitors`), so the game would always go through the compositor
    visible: Theme.state.quickHover && !(Hyprland.monitorFor(screen)?.activeWorkspace?.hasFullscreen ?? false)
    anchors { right: true; bottom: true }
    implicitWidth: 2
    implicitHeight: Math.round(screen.height * 0.8)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "glyph-hot"

    HoverHandler { id: hov; onHoveredChanged: hovered ? dwell.restart() : dwell.stop() }
    Timer { id: dwell; interval: 150; onTriggered: if (hov.hovered) root.triggered() }
}
