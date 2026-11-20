// The notification centre (Super+N, or a click on the clock): everything
// that came in, newest first, with do not disturb at the top.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.widgets

PanelWindow {
    id: panel
    visible: Shell.isOpen("notifications")
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    anchors { top: true }
    margins { top: 6 }
    implicitWidth: 420
    implicitHeight: Math.min(640, content.implicitHeight + 32)
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "forge-notification-centre"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    HyprlandFocusGrab {
        windows: [panel]
        active: panel.visible
        onCleared: Shell.close("notifications")
    }

    Glass {
        anchors.fill: parent
        strong: true
        focus: true
        Keys.onEscapePressed: Shell.close("notifications")

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Header {
                Layout.fillWidth: true
                title: "Notifications"
                showSwitch: false
            }
            Toggle {
                Layout.fillWidth: true
                icon: Forged.dnd.enabled ? Icons.bellOff : Icons.bell
                title: "Do not disturb"
                detail: Forged.dnd.enabled ? "Notifications wait here, quietly" : "Pop-ups are on"
                on: Forged.dnd.enabled === true
                onToggled: Forged.set("dnd", "toggle")
            }
            Label {
                visible: Notifs.history.length === 0
                Layout.alignment: Qt.AlignHCenter
                Layout.margins: 20
                text: "Nothing new"
                dim: true
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: list.implicitHeight
                visible: Notifs.history.length > 0
                clip: true
                Column {
                    id: list
                    width: content.width
                    spacing: 8
                    Repeater {
                        model: Notifs.history
                        NotificationCard {
                            required property var modelData
                            notification: modelData
                            width: list.width
                        }
                    }
                }
            }
            HoverButton {
                visible: Notifs.history.length > 0
                Layout.alignment: Qt.AlignRight
                Layout.preferredWidth: clear.implicitWidth + 24
                Layout.preferredHeight: 30
                radius: 15
                onClicked: Notifs.dismissAll()
                Label { id: clear; anchors.centerIn: parent; text: "Clear all"; size: 12; font.weight: Font.DemiBold }
            }
        }
    }
}
