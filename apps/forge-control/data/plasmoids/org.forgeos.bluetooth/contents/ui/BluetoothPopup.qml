// Forge Bluetooth's popup: the switch, then the paired devices, connected
// first, each with its kind, its battery when it reports one, and a click
// to connect or disconnect it. New devices are paired in Bluetooth settings.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.forgeos.panel

ColumnLayout {
    id: popup

    required property Forged forged
    signal settingsRequested()

    readonly property var bluetooth: forged.part("bluetooth")
    readonly property var devices: bluetooth.devices || []
    readonly property int connectedCount: devices.filter(d => d.connected).length
    property string error: ""

    // BlueZ's device icons (audio-headset, input-mouse...) as symbolic icons.
    function deviceIcon(kind) {
        const known = {
            "audio-headset": "audio-headset-symbolic", "audio-headphones": "audio-headphones-symbolic",
            "audio-card": "audio-speakers-symbolic", "input-mouse": "input-mouse-symbolic",
            "input-keyboard": "input-keyboard-symbolic", "input-gaming": "input-gaming-symbolic",
            "input-tablet": "input-tablet-symbolic", "phone": "phone-symbolic",
            "computer": "computer-symbolic", "camera-photo": "camera-photo-symbolic",
        };
        return known[kind] || "network-bluetooth-symbolic";
    }

    width: Kirigami.Units.gridUnit * 18
    spacing: Kirigami.Units.smallSpacing

    PopupHeader {
        iconSource: "network-bluetooth-symbolic"
        title: i18n("Bluetooth")
        subtitle: popup.bluetooth.available === false ? i18n("No Bluetooth adapter")
                : !popup.bluetooth.enabled ? i18n("Off")
                : popup.connectedCount === 1 ? i18n("1 device connected")
                : popup.connectedCount > 1 ? i18n("%1 devices connected", popup.connectedCount)
                : i18n("On")
        on: popup.bluetooth.enabled === true
        showSwitch: popup.bluetooth.available === true
        onToggled: checked => popup.forged.set("bluetooth", checked ? "on" : "off", error => popup.error = error)
    }

    SectionLabel {
        visible: popup.bluetooth.enabled === true && popup.devices.length > 0
        text: i18n("Devices")
    }

    PlasmaComponents.ScrollView {
        id: scroll
        visible: popup.bluetooth.enabled === true && popup.devices.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(list.implicitHeight, Kirigami.Units.gridUnit * 16)

        ColumnLayout {
            id: list
            width: scroll.availableWidth
            spacing: 2

            Repeater {
                model: popup.devices

                delegate: ListRow {
                    required property var modelData

                    iconSource: popup.deviceIcon(modelData.icon)
                    title: modelData.name
                    subtitle: modelData.busy ? (modelData.connected ? i18n("Disconnecting…") : i18n("Connecting…"))
                            : modelData.connected ? i18n("Connected") : i18n("Not connected")
                    trailing: modelData.battery !== null && modelData.battery !== undefined
                              ? modelData.battery + "%" : ""
                    current: modelData.connected
                    busy: modelData.busy
                    onClicked: {
                        if (modelData.busy) return;
                        popup.error = "";
                        popup.forged.act(modelData.connected ? "bt-disconnect" : "bt-connect", modelData.address, "",
                                         error => popup.error = error);
                    }
                }
            }
        }
    }

    Text {
        visible: popup.bluetooth.enabled !== true || popup.devices.length === 0
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: popup.bluetooth.enabled !== true ? i18n("Bluetooth is off.")
            : i18n("No paired devices yet. Pair one in Bluetooth settings.")
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
        font.pixelSize: 12
    }

    Text {
        visible: popup.error.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        wrapMode: Text.Wrap
        text: popup.error
        color: Kirigami.Theme.negativeTextColor
        font.pixelSize: 11
    }

    FooterLink {
        text: i18n("Bluetooth settings…")
        onClicked: popup.settingsRequested()
    }
}
