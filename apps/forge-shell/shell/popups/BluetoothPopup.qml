// Bluetooth: on/off and paired devices (with their battery); a click
// connects or disconnects one. Pairing new devices: blueman.
import QtQuick
import Quickshell
import qs.services
import qs.widgets

BarPopup {
    id: popup
    readonly property var b: Forged.bluetooth
    property string error: ""

    Header {
        title: "Bluetooth"
        on: popup.b.enabled === true
        onSwitched: Forged.set("bluetooth", popup.b.enabled ? "off" : "on")
    }
    Label {
        visible: popup.b.enabled === true && !(popup.b.devices || []).length
        dim: true
        size: 12
        text: "No paired devices yet"
    }
    Repeater {
        model: popup.b.enabled ? (popup.b.devices || []) : []
        ListRow {
            required property var modelData
            icon: modelData.icon.indexOf("audio") >= 0 ? Icons.headphones : Icons.bluetooth
            title: modelData.name
            detail: (modelData.connected ? "Connected" : "Paired") + (modelData.battery !== null ? "  ·  " + modelData.battery + "%" : "")
            current: modelData.connected
            busy: modelData.busy
            onClicked: Forged.run(modelData.connected ? "bt-disconnect" : "bt-connect", modelData.address, "",
                                  err => popup.error = err)
        }
    }
    Label { visible: popup.error !== ""; text: popup.error; color: Theme.danger; size: 12; width: parent.width; wrapMode: Text.Wrap }
    ListRow {
        icon: Icons.plus
        title: "Pair a new device…"
        onClicked: { popup.visible = false; Quickshell.execDetached(["blueman-manager"]); }
    }
}
