// A full-screen overlay on the focused screen: a dimmed, frosted backdrop
// that takes the keyboard; Escape or a click outside the content closes it.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

PanelWindow {
    id: overlay
    property string name
    property bool dim: true
    default property alias content: holder.data
    signal opened()

    visible: Shell.isOpen(name)
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "forge-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) opened()

    Rectangle {
        anchors.fill: parent
        color: overlay.dim ? Theme.alpha("#0b0c14", 0.45) : "transparent"
        MouseArea { anchors.fill: parent; onClicked: Shell.close(overlay.name) }
    }
    Item {
        id: holder
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Shell.close(overlay.name)
    }
}
