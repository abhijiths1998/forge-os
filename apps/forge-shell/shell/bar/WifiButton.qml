// Wi-Fi: its strength in the bar; the popup lists networks and joins them.
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets
import qs.popups

HoverButton {
    id: button
    readonly property var w: Forged.wifi
    visible: w.available !== false || w.wired === true
    Layout.preferredWidth: 30
    Layout.fillHeight: true
    Layout.margins: 3
    radius: height / 2
    onClicked: e => {
        if (e.button === Qt.MiddleButton) Forged.set("wifi", "toggle");
        else popup.visible = !popup.visible;
    }

    Icon {
        anchors.centerIn: parent
        size: 17
        text: button.w.wired ? Icons.wired
            : !button.w.enabled ? Icons.wifiOff
            : !button.w.ssid ? Icons.wifi[0]
            : Icons.wifi[Math.max(1, Math.min(4, Math.ceil((button.w.signal || 0) / 25)))]
        opacity: button.w.enabled || button.w.wired ? 1 : 0.55
    }

    WifiPopup { id: popup; button: button }
}
