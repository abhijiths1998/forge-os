// A glass popup under a bar button (Wi-Fi, Bluetooth, sound, battery).
// Clicking anywhere else closes it.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

PopupWindow {
    id: popup
    property Item button
    property int contentWidth: 320
    default property alias content: column.data

    anchor.item: button
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 10
    implicitWidth: contentWidth
    implicitHeight: column.implicitHeight + 28
    color: "transparent"

    HyprlandFocusGrab {
        windows: [popup]
        active: popup.visible
        onCleared: popup.visible = false
    }

    Glass {
        anchors.fill: parent
        strong: true
        Column {
            id: column
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8
        }
    }
}
