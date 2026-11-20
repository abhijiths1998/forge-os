// Pop-ups in the top-right corner of the focused screen.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.widgets

PanelWindow {
    visible: Notifs.popups.length > 0 && !Shell.isOpen("notifications")
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    anchors { top: true; right: true }
    margins { top: 6; right: 10 }
    implicitWidth: 380
    implicitHeight: column.implicitHeight
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "forge-notifications"
    WlrLayershell.layer: WlrLayer.Overlay

    Column {
        id: column
        width: parent.width
        spacing: 8
        Repeater {
            model: Notifs.popups
            NotificationCard {
                required property var modelData
                notification: modelData
                width: column.width
                popup: true
            }
        }
    }
}
