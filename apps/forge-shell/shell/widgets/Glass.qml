// A Forge Glass surface: translucent, rounded, with a hairline lit edge.
// Hyprland frosts what's behind it (the layer rules in look.lua).
import QtQuick
import qs.services

Rectangle {
    property bool strong: false
    radius: Theme.radius
    color: strong ? Theme.glassStrong : Theme.glass
    border.width: 1
    border.color: Theme.edge
}
