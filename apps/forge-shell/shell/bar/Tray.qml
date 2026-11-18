// Apps' own tray icons (Steam, Discord...): a click opens the app, a right
// click its menu.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.services
import qs.widgets

RowLayout {
    property var bar
    spacing: 0
    // Network and Bluetooth applets run only as password helpers; Forge's
    // own buttons stand for them.
    readonly property var hidden: ["nm-applet", "blueman", "udiskie"]

    Repeater {
        model: SystemTray.items.values.filter(i => !parent.hidden.some(h => (i.id || "").toLowerCase().indexOf(h) >= 0))
        HoverButton {
            id: button
            required property var modelData
            Layout.preferredWidth: 28
            Layout.fillHeight: true
            Layout.margins: 3
            radius: height / 2
            onClicked: e => {
                if (e.button === Qt.RightButton || modelData.onlyMenu) {
                    const p = bar.mapFromItem(button, 0, button.height);
                    modelData.display(bar, p.x, p.y + 6);
                } else if (e.button === Qt.MiddleButton) {
                    modelData.secondaryActivate();
                } else {
                    modelData.activate();
                }
            }
            IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                source: modelData.icon
            }
        }
    }
}
