// Forge Bluetooth: the top bar's Bluetooth icon (on, off, a device
// connected) and its popup (BluetoothPopup.qml): the switch and the paired
// devices, connected with a click. The state and the actions are forged's.
import QtQuick

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid
import org.forgeos.panel

PlasmoidItem {
    id: root

    readonly property var bluetooth: forged.part("bluetooth")
    readonly property var connected: (bluetooth.devices || []).filter(d => d.connected)

    preferredRepresentation: fullRepresentation
    toolTipMainText: i18n("Bluetooth")
    toolTipSubText: !bluetooth.enabled ? i18n("Off")
                  : connected.length ? connected.map(d => d.name).join(", ")
                  : i18n("On, nothing connected")

    Forged { id: forged }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: BarButton {
        id: button
        visible: root.bluetooth.available !== false
        iconSource: root.bluetooth.enabled ? "network-bluetooth-symbolic" : "bluetooth-disabled-symbolic"
        location: Plasmoid.location
        vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        popup: BluetoothPopup {
            forged: forged
            onSettingsRequested: {
                button.close();
                runner.connectSource("systemsettings kcm_bluetooth");
            }
        }
    }
}
