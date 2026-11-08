import QtQuick
import qs

// local: for layer.effect, while it moves: the item comes in as growing dots, a wave out from `origin` (item px).
// progress 0 nothing, 1 all of it. Give the layer a textureSize in device pixels, every scale above it included: Qt takes
// an explicit size as is, and anything less shows as rough text until the layer goes off
ShaderEffect {
    property real progress: 1
    property point origin: Qt.point(width / 2, height / 2)
    property real pitch: 16 // px between dots
    property real band: 420 // px, how wide the wave is
    property color ink: Theme.fg // the wave's own dots, on what's still dark
    readonly property size size: Qt.size(width, height)
    fragmentShader: Qt.resolvedUrl("shaders/halftone.frag.qsb")
}
