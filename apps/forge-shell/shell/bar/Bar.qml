// The top bar: a slim floating glass strip. Left: the Forge button
// (launcher), workspaces, the focused window. Middle: the island (clock;
// the song that's playing). Right: mode and quiet badges, app tray icons,
// battery, Wi-Fi, Bluetooth, sound, and the Control Center.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.widgets

PanelWindow {
    id: panel
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    margins { top: 6; left: 10; right: 10 }
    implicitHeight: 38
    exclusiveZone: implicitHeight + 4
    color: "transparent"
    WlrLayershell.namespace: "forge-bar"
    WlrLayershell.layer: WlrLayer.Top

    Glass {
        anchors.fill: parent
        radius: height / 2

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 4

            HoverButton {
                Layout.preferredWidth: 30
                Layout.fillHeight: true
                Layout.margins: 3
                radius: height / 2
                onClicked: Quickshell.execDetached(["forge-open", "launcher"])
                Icon { anchors.centerIn: parent; text: Icons.forge; size: 17; color: Theme.accent }
            }
            Workspaces { Layout.fillHeight: true; screenName: panel.modelData.name }
            WindowTitle { Layout.fillWidth: true; Layout.maximumWidth: 360; Layout.leftMargin: 6 }
            Item { Layout.fillWidth: true }
        }

        Island { anchors.centerIn: parent; height: parent.height - 8 }

        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            spacing: 2

            ModeBadge {}
            QuietBadge {}
            Tray { bar: panel }
            BatteryButton {}
            WifiButton {}
            BluetoothButton {}
            VolumeButton {}
            HoverButton {
                Layout.preferredWidth: 32
                Layout.fillHeight: true
                Layout.margins: 3
                radius: height / 2
                active: Shell.isOpen("control")
                onClicked: Shell.toggle("control")
                Icon {
                    anchors.centerIn: parent
                    text: Icons.control
                    size: 17
                    color: parent.active ? Theme.onAccent : Theme.text
                }
            }
        }
    }
}
