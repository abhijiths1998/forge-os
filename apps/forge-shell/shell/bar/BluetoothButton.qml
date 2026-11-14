// Bluetooth: on, off, connected; the popup connects paired devices.
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets
import qs.popups

HoverButton {
    id: button
    readonly property var b: Forged.bluetooth
    visible: b.available === true
    Layout.preferredWidth: 30
    Layout.fillHeight: true
    Layout.margins: 3
    radius: height / 2
    onClicked: e => {
        if (e.button === Qt.MiddleButton) Forged.set("bluetooth", "toggle");
        else popup.visible = !popup.visible;
    }
    Icon {
        anchors.centerIn: parent
        size: 17
        text: !button.b.enabled ? Icons.bluetoothOff : (button.b.connected || []).length ? Icons.bluetoothOn : Icons.bluetooth
        opacity: button.b.enabled ? 1 : 0.55
    }
    BluetoothPopup { id: popup; button: button }
}
